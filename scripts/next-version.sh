#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""
sha=""
repo="${GITHUB_REPOSITORY:-JICA98/bachata-s4-drivers}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    --sha) sha="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$line" ]] || die "usage: next-version.sh --line <id> [--sha <sha>] [--repo owner/name]"

short=""
if [[ -n "$sha" ]]; then
  short="${sha:0:7}"
fi

list_tags() {
  if [[ -n "${TAGS_FILE:-}" ]]; then
    cat "$TAGS_FILE"
    return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${repo}/tags?per_page=100" --jq '.[].name' 2>/dev/null || true
    return 0
  fi
  git ls-remote --tags "https://github.com/${repo}.git" 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||; s/\^{}//' || true
}

list_assets() {
  if [[ -n "${ASSETS_FILE:-}" ]]; then
    cat "$ASSETS_FILE"
    return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${repo}/releases?per_page=100" --jq '.[].assets[].name' 2>/dev/null || true
    return 0
  fi
  true
}

if [[ -n "$short" && "${FORCE:-0}" != "1" ]]; then
  if list_assets | grep -E "^Turnip-${line//./\\.}-v[0-9]+-${short}-EMULATOR\\.zip$" >/dev/null; then
    echo "already_released" >&2
    exit 2
  fi
fi

max=0
prefix="${line}-v"
while IFS= read -r tag; do
  [[ -n "$tag" ]] || continue
  case "$tag" in
    "${prefix}"*)
      n="${tag#"$prefix"}"
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      if (( n > max )); then
        max=$n
      fi
      ;;
  esac
done < <(list_tags)

echo $((max + 1))
