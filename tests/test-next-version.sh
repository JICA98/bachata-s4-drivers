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

echo "next-version tests ok"
