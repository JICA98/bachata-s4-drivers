#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="$root/scripts/package-driver.sh"
val="$root/scripts/validate-driver.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

[[ -x "$pkg" ]] || { echo "package-driver.sh missing"; exit 1; }

if [[ ! -f "$root/Turnip_Gen8_V32_glibc.zip" ]]; then
  echo "SKIP package test without golden zip"
  exit 0
fi

unzip -q -o "$root/Turnip_Gen8_V32_glibc.zip" libvulkan_freedreno.so -d "$tmpdir"
lib="$tmpdir/libvulkan_freedreno.so"

out="$("$pkg" \
  --line gen8 \
  --version 1 \
  --commit 09df2ee2ba97f76d4da244bc98e843f807bfa99f \
  --branch turnip/gen8 \
  --library "$lib" \
  --driver-version "Vulkan 1.4.353" \
  --outdir "$tmpdir/dist")"

base="$(basename "$out")"
[[ "$base" == "Turnip-gen8-v1-09df2ee-EMULATOR.zip" ]] || { echo "bad name: $base"; exit 1; }
"$val" "$out"

meta_abi="$(unzip -p "$out" meta.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["abi"])')"
[[ "$meta_abi" == "linux-aarch64-glibc" ]] || { echo "bad abi in packaged meta: $meta_abi"; exit 1; }

echo "package tests ok"
