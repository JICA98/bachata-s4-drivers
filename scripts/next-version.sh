#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""
sha=""
patches_id="none"
repo="${GITHUB_REPOSITORY:-JICA98/bachata-s4-drivers}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    --sha) sha="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --patches-id) patches_id="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$line" ]] || die "usage: next-version.sh --line <id> [--sha <sha>] [--patches-id <id>] [--repo owner/name]"
[[ -n "$patches_id" ]] || patches_id="none"

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

# Print every patches-id recorded for this line+short SHA (one per line).
# Skip a rebuild when ANY of those ids equals the current patches-id. GitHub
# lists releases newest-first and older unpatched zips for the same mesa SHA
# still exist; do not use only the last array element.
emit_release_patches_ids() {
  LINE="$1" SHORT="$2" python3 -c '
import json, os, re, sys

line = os.environ["LINE"]
short = os.environ["SHORT"]
data = json.load(sys.stdin)
pat = re.compile(
    r"^Turnip-"
    + re.escape(line)
    + r"-v[0-9]+-"
    + re.escape(short)
    + r"-EMULATOR\.zip$"
)
ids = []
for rel in data:
    names = [a.get("name") or "" for a in (rel.get("assets") or [])]
    if not any(pat.match(name) for name in names):
        continue
    body = rel.get("body") or ""
    match = re.search(r"Patches-Id: `([^`]+)`", body)
    ids.append(match.group(1) if match else "none")
print("\n".join(ids) if ids else "none")
'
}

recorded_patches_id() {
  local want_line="$1" want_short="$2"
  if [[ -n "${NOTES_FILE:-}" ]]; then
    awk -v line="$want_line" -v short="$want_short" '
      $1==line && $2==short { print $3; found=1 }
      END { if (!found) print "none" }
    ' "$NOTES_FILE"
    return 0
  fi
  if [[ -n "${RELEASES_JSON_FILE:-}" ]]; then
    emit_release_patches_ids "$want_line" "$want_short" <"$RELEASES_JSON_FILE"
    return 0
  fi
  # Fixture-driven tests set ASSETS_FILE; do not hit the network.
  if [[ -n "${ASSETS_FILE:-}" ]]; then
    echo none
    return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    # gh api --jq does not accept --arg; pipe JSON into python instead.
    gh api "repos/${repo}/releases?per_page=100" 2>/dev/null \
      | emit_release_patches_ids "$want_line" "$want_short" \
      || echo none
    return 0
  fi
  echo none
}

if [[ -n "$short" && "${FORCE:-0}" != "1" ]]; then
  if list_assets | grep -E "^Turnip-${line//./\\.}-v[0-9]+-${short}-EMULATOR\\.zip$" >/dev/null; then
    recorded="$(recorded_patches_id "$line" "$short")"
    if printf '%s\n' "$recorded" | grep -Fxq -- "$patches_id"; then
      echo "already_released" >&2
      exit 2
    fi
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
