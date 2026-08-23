#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

src="${1:-}"
[[ -n "$src" && -f "$src" ]] || die "usage: check-kgsl-zero-timeout.sh <tu_knl_kgsl.cc>"

python3 - "$src" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
needle = "\nwait_timestamp_safe("
idx = text.find(needle)
if idx < 0:
    print("wait_timestamp_safe not found", file=sys.stderr)
    sys.exit(1)
static_at = text.rfind("static ", 0, idx)
if static_at < 0:
    print("wait_timestamp_safe is not a static function", file=sys.stderr)
    sys.exit(1)
brace_at = text.find("{", idx)
if brace_at < 0:
    print("wait_timestamp_safe has no body", file=sys.stderr)
    sys.exit(1)
depth = 0
end = None
for i in range(brace_at, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None:
    print("wait_timestamp_safe body is unclosed", file=sys.stderr)
    sys.exit(1)
fn = text[static_at:end]
poll = "IOCTL_KGSL_CMDSTREAM_READTIMESTAMP_CTXTID"
wait = "IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID"
if poll not in fn:
    print("zero-timeout poll missing IOCTL_KGSL_CMDSTREAM_READTIMESTAMP_CTXTID", file=sys.stderr)
    sys.exit(1)
if wait not in fn:
    print("bounded wait missing IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID", file=sys.stderr)
    sys.exit(1)
if fn.index(poll) > fn.index(wait):
    print("READTIMESTAMP poll must run before WAITTIMESTAMP", file=sys.stderr)
    sys.exit(1)
print("kgsl zero-timeout poll ok")
PY
