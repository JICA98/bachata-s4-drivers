#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
nv="$root/scripts/next-version.sh"
[[ -x "$nv" ]] || { echo "missing next-version"; exit 1; }

mkdir -p "$root/tests/fixtures"
tags="$root/tests/fixtures/tags-sample.txt"
cat >"$tags" <<'EOF'
gen8-v1
gen8-v3
mojo-26.1-v1
mojo-26.1-v2
mojo-25.0-v1
unrelated-v9
EOF

export TAGS_FILE="$tags"
n="$(FORCE=1 "$nv" --line gen8)"
[[ "$n" == "4" ]] || { echo "expected gen8 next 4 got $n"; exit 1; }

n="$(FORCE=1 "$nv" --line mojo-26.1)"
[[ "$n" == "3" ]] || { echo "expected mojo-26.1 next 3 got $n"; exit 1; }

n="$(FORCE=1 "$nv" --line mojo-25.0)"
[[ "$n" == "2" ]] || { echo "expected mojo-25.0 next 2 got $n"; exit 1; }

export TAGS_FILE="$root/tests/fixtures/tags-empty.txt"
: >"$TAGS_FILE"
n="$(FORCE=1 "$nv" --line gen8)"
[[ "$n" == "1" ]] || { echo "expected 1 got $n"; exit 1; }

export TAGS_FILE="$tags"
export ASSETS_FILE="$root/tests/fixtures/assets-sample.txt"
cat >"$ASSETS_FILE" <<'EOF'
Turnip-gen8-v3-09df2ee-EMULATOR.zip
Turnip-mojo-26.1-v2-abcdef1-EMULATOR.zip
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f
code=$?
set -e
[[ "$code" == "2" ]] || { echo "expected exit 2 for already_released, got $code"; exit 1; }

notes_dir="$(mktemp -d)"
trap 'rm -rf "$notes_dir"' EXIT

# Same mesa SHA with a new patches-id must NOT skip (first patched rebuild).
export NOTES_FILE="$notes_dir/notes-unpatched.txt"
cat >"$NOTES_FILE" <<'EOF'
gen8 09df2ee none
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f --patches-id abc1234
code=$?
set -e
[[ "$code" == "0" ]] || { echo "expected rebuild when patches-id is new, got exit $code"; exit 1; }
n="$(FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f --patches-id abc1234)"
[[ "$n" == "4" ]] || { echo "expected gen8 next 4 for patched rebuild, got $n"; exit 1; }

# Same SHA + same patches-id already recorded → skip.
export NOTES_FILE="$notes_dir/notes-patched.txt"
cat >"$NOTES_FILE" <<'EOF'
gen8 09df2ee abc1234
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f --patches-id abc1234
code=$?
set -e
[[ "$code" == "2" ]] || { echo "expected exit 2 for same sha+patches-id, got $code"; exit 1; }

# Older unpatched zip for the same mesa SHA must not hide a later matching patches-id.
# GitHub lists newest-first; NOTES_FILE may be oldest-first. Skip if ANY row matches.
export NOTES_FILE="$notes_dir/notes-mixed-oldest-first.txt"
cat >"$NOTES_FILE" <<'EOF'
gen8 09df2ee none
gen8 09df2ee abc1234
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f --patches-id abc1234
code=$?
set -e
[[ "$code" == "2" ]] || { echo "expected exit 2 when any same-SHA release has this patches-id (oldest-first notes), got $code"; exit 1; }

export NOTES_FILE="$notes_dir/notes-mixed-newest-first.txt"
cat >"$NOTES_FILE" <<'EOF'
gen8 09df2ee abc1234
gen8 09df2ee none
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f --patches-id abc1234
code=$?
set -e
[[ "$code" == "2" ]] || { echo "expected exit 2 when any same-SHA release has this patches-id (newest-first notes), got $code"; exit 1; }

# GitHub releases JSON (newest-first): oldest unpatched + newer patched for the same SHA.
unset NOTES_FILE
export RELEASES_JSON_FILE="$notes_dir/releases-newest-first.json"
cat >"$RELEASES_JSON_FILE" <<'EOF'
[
  {
    "tag_name": "gen8-v4",
    "body": "## Turnip gen8 v4\n\n- Patches-Id: `abc1234`\n",
    "assets": [{"name": "Turnip-gen8-v4-09df2ee-EMULATOR.zip"}]
  },
  {
    "tag_name": "gen8-v3",
    "body": "## Turnip gen8 v3\n\nBuilt automatically.\n",
    "assets": [{"name": "Turnip-gen8-v3-09df2ee-EMULATOR.zip"}]
  }
]
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f --patches-id abc1234
code=$?
set -e
[[ "$code" == "2" ]] || { echo "expected exit 2 from GitHub JSON newest-first (patched v4 + unpatched v3), got $code"; exit 1; }

echo "next-version tests ok"
