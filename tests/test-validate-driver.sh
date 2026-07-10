#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
validate="$root/scripts/validate-driver.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

[[ -x "$validate" ]] || { echo "validate-driver.sh missing"; exit 1; }

golden="$root/Turnip_Gen8_V32_glibc.zip"
if [[ -f "$golden" ]]; then
  cp "$golden" "$tmpdir/good.zip"
  "$validate" "$tmpdir/good.zip"
else
  echo "SKIP full golden test (no Turnip_Gen8_V32_glibc.zip)"
fi

mkdir -p "$tmpdir/bad1"
printf 'x' >"$tmpdir/bad1/libvulkan_freedreno.so"
printf '{}' >"$tmpdir/bad1/freedreno_icd.aarch64.json"
python3 - "$tmpdir/bad1" "$tmpdir/bad-missing-meta.zip" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w") as zf:
    for name in ("libvulkan_freedreno.so", "freedreno_icd.aarch64.json"):
        zf.write(os.path.join(stage, name), arcname=name)
PY
if "$validate" "$tmpdir/bad-missing-meta.zip"; then
  echo "expected validate to fail for missing meta"
  exit 1
fi

if [[ -f "$golden" ]]; then
  mkdir -p "$tmpdir/bad2"
  unzip -q -o "$golden" -d "$tmpdir/bad2"
  python3 - "$tmpdir/bad2/meta.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p, encoding="utf-8"))
m["abi"] = "android-aarch64-bionic"
json.dump(m, open(p, "w", encoding="utf-8"))
PY
  python3 - "$tmpdir/bad2" "$tmpdir/bad-abi.zip" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w") as zf:
    for name in ("libvulkan_freedreno.so", "freedreno_icd.aarch64.json", "meta.json"):
        zf.write(os.path.join(stage, name), arcname=name)
PY
  if "$validate" "$tmpdir/bad-abi.zip"; then
    echo "expected validate to fail for wrong abi"
    exit 1
  fi
fi

echo "validate tests ok"
