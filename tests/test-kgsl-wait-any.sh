#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$root/tests/fixtures/tu_knl_kgsl_stock.cc"
check="$root/scripts/check-kgsl-wait-any.sh"
apply="$root/scripts/apply-mesa-patches.sh"

set +e
bash "$check" "$fixture" >/dev/null 2>&1
stock_code=$?
set -e
[[ "$stock_code" -ne 0 ]] || { echo "stock Mesa wait-any mapping must fail"; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mesa="$tmpdir/mesa"
mkdir -p "$mesa/src/freedreno/vulkan"
cp "$fixture" "$mesa/src/freedreno/vulkan/tu_knl_kgsl.cc"

"$apply" "$mesa" gen8
bash "$check" "$mesa/src/freedreno/vulkan/tu_knl_kgsl.cc"
other="$tmpdir/other-mesa"
mkdir -p "$other/src/freedreno/vulkan"
cp "$fixture" "$other/src/freedreno/vulkan/tu_knl_kgsl.cc"
"$apply" "$other" mojo-26.1
if bash "$check" "$other/src/freedreno/vulkan/tu_knl_kgsl.cc" >/dev/null 2>&1; then
  echo "wait-any patch must be limited to gen8" >&2
  exit 1
fi
# shellcheck source=../scripts/lib.sh
source "$root/scripts/lib.sh"
[[ "$(mesa_patch_names gen8)" == "kgsl-wait-any-correctness,kgsl-zero-timeout-poll" ]]
[[ "$(mesa_patch_names mojo-26.1)" == "kgsl-zero-timeout-poll" ]]
[[ "$(mesa_patches_id gen8)" != "$(mesa_patches_id mojo-26.1)" ]]
grep -q 'check-kgsl-wait-any.sh' "$root/scripts/build-driver.sh" \
  || { echo "build-driver.sh must verify Mesa wait-any mapping after patch"; exit 1; }
echo "kgsl wait-any tests ok"
