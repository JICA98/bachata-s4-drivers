#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done
[[ -n "$line" ]] || die "usage: check-tip.sh --line <id>"
branch="$(line_branch "$line")"

if [[ -n "${TIP_SHA_OVERRIDE:-}" ]]; then
  printf '%s\n' "$TIP_SHA_OVERRIDE"
  exit 0
fi

require_cmd git
sha="$(git ls-remote --heads "$MESA_REPO_URL" "$branch" | awk '{print $1; exit}')"
[[ -n "$sha" && ${#sha} -eq 40 ]] || die "failed to resolve tip for $branch at $MESA_REPO_URL"
printf '%s\n' "$sha"
