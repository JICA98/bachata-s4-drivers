#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

zip_path="${1:-}"
[[ -n "$zip_path" && -f "$zip_path" ]] || die "usage: validate-driver.sh <zip>"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
unzip -q -o "$zip_path" -d "$tmpdir"

mapfile -t entries < <(unzip -Z1 "$zip_path" | sed 's|^\./||' | sort)
expected=$'freedreno_icd.aarch64.json\nlibvulkan_freedreno.so\nmeta.json'
actual="$(printf '%s\n' "${entries[@]}" | sort)"
[[ "$actual" == "$expected" ]] || die "zip entries mismatch: got: ${entries[*]}"

while IFS= read -r e; do
  [[ -n "$e" ]] || continue
  [[ "$e" != */* && "$e" != *..* ]] || die "illegal zip entry path: $e"
done <<<"$(printf '%s\n' "${entries[@]}")"

meta="$tmpdir/meta.json"
lib="$tmpdir/libvulkan_freedreno.so"
icd="$tmpdir/freedreno_icd.aarch64.json"
[[ -f "$meta" && -f "$lib" && -f "$icd" ]] || die "missing required files after extract"

python3 - "$meta" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for k in ("schemaVersion", "name", "libraryName", "abi"):
    if k not in m:
        raise SystemExit(f"meta missing {k}")
if m.get("abi") != "linux-aarch64-glibc":
    raise SystemExit(f"bad abi: {m.get('abi')}")
if m.get("libraryName") != "libvulkan_freedreno.so":
    raise SystemExit(f"bad libraryName: {m.get('libraryName')}")
if int(m.get("schemaVersion", 0)) < 1:
    raise SystemExit("schemaVersion must be >= 1")
print("meta ok")
PY

file_out="$(file -b "$lib")"
[[ "$file_out" == *"ELF"* && "$file_out" == *"aarch64"* ]] || die "library is not ELF aarch64: $file_out"
[[ "$file_out" == *"shared object"* || "$file_out" == *"LSB shared object"* ]] || die "library is not a shared object: $file_out"

dyn="$(readelf -d "$lib" 2>/dev/null || true)"
printf '%s\n' "$dyn" | grep -q 'libc.so.6' || die "library does not link libc.so.6 (not glibc?)"

log "validate OK: $zip_path"
