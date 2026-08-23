#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="$root/scripts/package-driver.sh"
[[ -x "$pkg" ]] || { echo "package-driver.sh missing"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
printf 'not-an-elf' >"$tmpdir/libvulkan_freedreno.so"

out="$("$pkg" \
  --line gen8 \
  --version 4 \
  --commit 09df2ee2ba97f76d4da244bc98e843f807bfa99f \
  --branch turnip/gen8 \
  --library "$tmpdir/libvulkan_freedreno.so" \
  --driver-version "Vulkan 1.4.353" \
  --patches kgsl-zero-timeout-poll \
  --patches-id abc1234 \
  --outdir "$tmpdir/dist")"

python3 - "$out" <<'PY'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zf:
    meta = json.loads(zf.read("meta.json"))
assert meta["abi"] == "linux-aarch64-glibc", meta
assert meta["patches"] == ["kgsl-zero-timeout-poll"], meta
assert meta["patchesId"] == "abc1234", meta
print("package meta patches ok")
PY
