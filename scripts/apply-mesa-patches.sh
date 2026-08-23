#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

src="${1:-}"
[[ -n "$src" && -d "$src" ]] || die "usage: apply-mesa-patches.sh <mesa-src>"

root="$(cd "$(dirname "$0")/.." && pwd)"
patches="$root/patches"
shopt -s nullglob
files=("$patches"/*.patch)
if [[ ${#files[@]} -eq 0 ]]; then
  log "no patches in $patches"
  exit 0
fi

require_cmd patch
src="$(cd "$src" && pwd)"
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)
for p in "${files[@]}"; do
  log "applying $(basename "$p")"
  if ! patch -d "$src" -p1 --batch --fuzz=0 <"$p"; then
    die "failed to apply $(basename "$p") onto $src"
  fi
done
