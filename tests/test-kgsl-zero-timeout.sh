#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
apply="$root/scripts/apply-mesa-patches.sh"
check="$root/scripts/check-kgsl-zero-timeout.sh"
fixture="$root/tests/fixtures/tu_knl_kgsl_stock.cc"
patch="$root/patches/kgsl-zero-timeout-poll.patch"

[[ -x "$apply" ]] || { echo "apply-mesa-patches.sh missing"; exit 1; }
[[ -x "$check" ]] || { echo "check-kgsl-zero-timeout.sh missing"; exit 1; }
[[ -f "$patch" ]] || { echo "kgsl-zero-timeout-poll.patch missing"; exit 1; }
[[ -f "$fixture" ]] || { echo "stock fixture missing"; exit 1; }

set +e
"$check" "$fixture" >/dev/null 2>&1
stock_code=$?
set -e
[[ "$stock_code" -ne 0 ]] || { echo "stock wait_timestamp_safe must fail zero-timeout check"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mesa="$tmpdir/mesa"
mkdir -p "$mesa/src/freedreno/vulkan"
cp "$fixture" "$mesa/src/freedreno/vulkan/tu_knl_kgsl.cc"

"$apply" "$mesa"
"$check" "$mesa/src/freedreno/vulkan/tu_knl_kgsl.cc"

patched="$mesa/src/freedreno/vulkan/tu_knl_kgsl.cc"
grep -q 'IOCTL_KGSL_CMDSTREAM_READTIMESTAMP_CTXTID' "$patched" \
  || { echo "patched source missing READTIMESTAMP poll ioctl"; exit 1; }
grep -q 'IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID' "$patched" \
  || { echo "patched source dropped WAITTIMESTAMP (bounded waits must remain)"; exit 1; }

bad="$tmpdir/bad-mesa"
mkdir -p "$bad/src/freedreno/vulkan"
printf '// no wait_timestamp_safe\n' >"$bad/src/freedreno/vulkan/tu_knl_kgsl.cc"
set +e
"$apply" "$bad" >/dev/null 2>&1
bad_code=$?
set -e
[[ "$bad_code" -ne 0 ]] || { echo "apply must fail closed when hunk does not match"; exit 1; }

grep -q 'apply-mesa-patches.sh' "$root/scripts/build-driver.sh" \
  || { echo "build-driver.sh must apply Mesa patches"; exit 1; }
grep -q 'check-kgsl-zero-timeout.sh' "$root/scripts/build-driver.sh" \
  || { echo "build-driver.sh must run zero-timeout check after patch"; exit 1; }

echo "kgsl zero-timeout tests ok"
