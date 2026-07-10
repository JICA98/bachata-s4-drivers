#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line="${1:-}"
[[ -n "$line" ]] || die "usage: build-driver.sh <line_id>"
branch="$(line_branch "$line")"
root="$(cd "$(dirname "$0")/.." && pwd)"

require_cmd git meson ninja aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ python3 unzip file readelf

work="$root/work/$line"
src="$work/mesa"
build="$work/build"
prefix="$work/prefix"
dist="$root/dist"
cross="$root/meson/aarch64-linux-gnu.ini"
mkdir -p "$work" "$dist"

log "line=$line branch=$branch"

if [[ ! -d "$src/.git" ]]; then
  git clone --depth=1 --branch "$branch" "$MESA_REPO_URL" "$src"
else
  git -C "$src" remote set-url origin "$MESA_REPO_URL"
  git -C "$src" fetch --depth=1 origin "$branch"
  git -C "$src" checkout -f FETCH_HEAD
fi
commit="$(git -C "$src" rev-parse HEAD)"
short="${commit:0:7}"
log "commit=$commit"

# Older mesa (e.g. mojo/25.0) conflicts with glibc C11 once_flag/call_once.
# Mirror the guards present on newer mesa branches.
threads_h="$src/src/c11/threads.h"
threads_c="$src/src/c11/impl/threads_posix.c"
if [[ -f "$threads_h" ]] && ! grep -q '__once_flag_defined' "$threads_h"; then
  log "patching c11 threads for glibc once_flag compatibility"
  python3 - "$threads_h" "$threads_c" <<'PY'
from pathlib import Path
import sys

header = Path(sys.argv[1])
text = header.read_text(encoding="utf-8")
old = "typedef pthread_once_t  once_flag;\n#  define ONCE_FLAG_INIT PTHREAD_ONCE_INIT"
new = (
    "#ifndef __once_flag_defined\n"
    "typedef pthread_once_t  once_flag;\n"
    "#  define ONCE_FLAG_INIT PTHREAD_ONCE_INIT\n"
    "#endif"
)
if old in text:
    text = text.replace(old, new, 1)
    header.write_text(text, encoding="utf-8")
    print(f"patched {header}")

src = Path(sys.argv[2])
if src.is_file():
    ctext = src.read_text(encoding="utf-8")
    cold = (
        "void\n"
        "call_once(once_flag *flag, void (*func)(void))\n"
        "{\n"
        "    pthread_once(flag, func);\n"
        "}\n"
    )
    cnew = (
        "#ifndef __once_flag_defined\n"
        "void\n"
        "call_once(once_flag *flag, void (*func)(void))\n"
        "{\n"
        "    pthread_once(flag, func);\n"
        "}\n"
        "#endif\n"
    )
    if cold in ctext and "#ifndef __once_flag_defined\nvoid\ncall_once" not in ctext:
        src.write_text(ctext.replace(cold, cnew, 1), encoding="utf-8")
        print(f"patched {src}")
PY
fi

if [[ -n "${FORCE_VERSION:-}" ]]; then
  version="$FORCE_VERSION"
else
  set +e
  version="$(FORCE="${FORCE:-0}" "$root/scripts/next-version.sh" --line "$line" --sha "$commit")"
  code=$?
  set -e
  if [[ "$code" -eq 2 ]]; then
    log "already released for $line @$short — nothing to do"
    exit 0
  fi
  [[ "$code" -eq 0 ]] || die "next-version failed (exit $code)"
fi
log "version=v$version"

rm -rf "$build" "$prefix"
mkdir -p "$prefix"

run_meson() {
  # shellcheck disable=SC2068
  meson setup "$build" "$src" \
    --cross-file "$cross" \
    --prefix "$prefix" \
    --libdir lib \
    --buildtype release \
    "$@"
}

if ! run_meson \
  -Dplatforms=x11 \
  -Dgallium-drivers= \
  -Dvulkan-drivers=freedreno \
  -Dfreedreno-kmds=kgsl \
  -Degl=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dopengl=false \
  -Dllvm=disabled \
  -Dshared-llvm=disabled \
  -Dbuild-tests=false \
  -Dxmlconfig=disabled; then
  log "primary meson setup failed; retry with minimal platforms"
  rm -rf "$build"
  run_meson \
    -Dplatforms= \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Degl=disabled \
    -Dllvm=disabled \
    -Dbuild-tests=false
fi

ninja -C "$build" install

lib="$(find "$prefix" -name 'libvulkan_freedreno.so' -type f | head -n1)"
[[ -n "$lib" && -f "$lib" ]] || die "libvulkan_freedreno.so not found under $prefix"

driver_version="Vulkan 1.4.0"
icd_src="$(find "$prefix" -name '*freedreno*.json' -type f | head -n1 || true)"
if [[ -n "${icd_src:-}" ]]; then
  api="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["ICD"].get("api_version",""))' "$icd_src" || true)"
  [[ -n "$api" ]] && driver_version="Vulkan $api"
fi

zip_path="$("$root/scripts/package-driver.sh" \
  --line "$line" \
  --version "$version" \
  --commit "$commit" \
  --branch "$branch" \
  --library "$lib" \
  --driver-version "$driver_version" \
  --outdir "$dist")"

if [[ "${SKIP_VALIDATE:-0}" != "1" ]]; then
  "$root/scripts/validate-driver.sh" "$zip_path"
fi

log "built $zip_path"
printf '%s\n' "$zip_path"
