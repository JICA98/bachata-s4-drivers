#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""
version=""
commit=""
branch=""
library=""
driver_version="Vulkan 1.4.0"
outdir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --library) library="$2"; shift 2 ;;
    --driver-version) driver_version="$2"; shift 2 ;;
    --outdir) outdir="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$line" && -n "$version" && -n "$commit" && -n "$branch" && -n "$library" && -n "$outdir" ]] \
  || die "usage: package-driver.sh --line --version --commit --branch --library --outdir [--driver-version]"
[[ -f "$library" ]] || die "library not found: $library"
[[ "$version" =~ ^[0-9]+$ ]] || die "version must be an integer: $version"
[[ ${#commit} -ge 7 ]] || die "commit sha too short"

shortsha="${commit:0:7}"
asset="Turnip-${line}-v${version}-${shortsha}-EMULATOR.zip"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$library" "$stage/libvulkan_freedreno.so"

api_ver="$(printf '%s' "$driver_version" | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
[[ "$api_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || api_ver="1.4.0"

cat >"$stage/freedreno_icd.aarch64.json" <<EOF
{
  "file_format_version": "1.0.1",
  "ICD": {
    "library_path": "libvulkan_freedreno.so",
    "library_arch": "64",
    "api_version": "${api_ver}"
  }
}
EOF

export PKG_LINE="$line"
export PKG_VERSION="$version"
export PKG_BRANCH="$branch"
export PKG_COMMIT="$commit"
export PKG_DRIVER_VERSION="$driver_version"
export PKG_META_PATH="$stage/meta.json"

python3 <<'PY'
import json
import os

meta = {
    "schemaVersion": 1,
    "name": f"Turnip {os.environ['PKG_LINE']} v{os.environ['PKG_VERSION']}",
    "description": (
        "glibc Turnip for Bachata S4 from whitebelyash/mesa-unified@"
        f"{os.environ['PKG_BRANCH']}"
    ),
    "author": "bachata-s4-drivers",
    "packageVersion": str(os.environ["PKG_VERSION"]),
    "vendor": "Mesa",
    "driverVersion": os.environ["PKG_DRIVER_VERSION"],
    "minApi": 31,
    "libraryName": "libvulkan_freedreno.so",
    "abi": "linux-aarch64-glibc",
    "sourceRepo": "https://github.com/whitebelyash/mesa-unified",
    "sourceBranch": os.environ["PKG_BRANCH"],
    "sourceCommit": os.environ["PKG_COMMIT"],
    "line": os.environ["PKG_LINE"],
    "releaseVersion": int(os.environ["PKG_VERSION"]),
}
with open(os.environ["PKG_META_PATH"], "w", encoding="utf-8") as fh:
    json.dump(meta, fh, indent=2)
    fh.write("\n")
PY

mkdir -p "$outdir"
out_abs="$(cd "$outdir" && pwd)/$asset"
rm -f "$out_abs"
export PKG_STAGE="$stage"
export PKG_OUT="$out_abs"
python3 <<'PY'
import os
import zipfile

stage = os.environ["PKG_STAGE"]
out = os.environ["PKG_OUT"]
names = (
    "libvulkan_freedreno.so",
    "freedreno_icd.aarch64.json",
    "meta.json",
)
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for name in names:
        zf.write(os.path.join(stage, name), arcname=name)
PY
printf '%s\n' "$out_abs"
