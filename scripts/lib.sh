#!/usr/bin/env bash
# Shared helpers for bachata-s4-drivers scripts.
set -euo pipefail

repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  printf '%s\n' "$here"
}

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

line_branch() {
  # Usage: line_branch <line_id>
  # Prints branch name from lines.conf or dies.
  local line_id="$1"
  local conf root branch
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  conf="$root/lines.conf"
  [[ -f "$conf" ]] || die "lines.conf not found at $conf"
  branch="$(awk -F= -v id="$line_id" '$1==id {print $2; found=1} END{exit !found}' "$conf")" \
    || die "unknown line id: $line_id (not in lines.conf)"
  printf '%s\n' "$branch"
}

MESA_REPO_URL="${MESA_REPO_URL:-https://github.com/whitebelyash/mesa-unified}"

# Create a flat zip from named files in a directory (no system zip required).
# Usage: make_zip <outdir_or_stage> <out.zip> file1 [file2 ...]
make_zip() {
  local stage="$1"
  local out="$2"
  shift 2
  PKG_STAGE="$stage" PKG_OUT="$out" PKG_NAMES="$*" python3 <<'PY'
import os
import zipfile

stage = os.environ["PKG_STAGE"]
out = os.environ["PKG_OUT"]
names = os.environ["PKG_NAMES"].split()
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for name in names:
        zf.write(os.path.join(stage, name), arcname=name)
PY
}
