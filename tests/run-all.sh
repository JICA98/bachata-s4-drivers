#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
shopt -s nullglob
for t in "$root"/tests/test-*.sh; do
  echo "RUN $t"
  if bash "$t"; then
    echo "PASS $t"
  else
    echo "FAIL $t"
    fail=1
  fi
done
exit "$fail"
