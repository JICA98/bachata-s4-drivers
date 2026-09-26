#!/usr/bin/env bash
set -euo pipefail

src="${1:-}"
[[ -f "$src" ]] || { echo "usage: check-kgsl-wait-any.sh <tu_knl_kgsl.cc>" >&2; exit 1; }

python3 - "$src" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
start = source.find("kgsl_syncobj_wait_any(")
end = source.find("u_vector_finish(&poll_fds);", start)
if start < 0 or end < 0:
    raise SystemExit("wait-any poll path missing")

body = source[start:end]
if "timestamp_cmp(lowest_timestamp, sync->timestamp)" not in body:
    raise SystemExit("wait-any must choose the oldest same-queue timestamp")
if not re.search(r"if\s*\(num_fds\s*&&\s*queue\)\s*\{\s*struct pollfd", body):
    raise SystemExit("wait-any must not create a timestamp fence when all syncobjs are FDs")

tail = source[max(start, end - 500):end]
pattern = re.compile(
    r"if\s*\(ret\s*==\s*0\)\s*\{\s*result\s*=\s*VK_TIMEOUT;\s*\}"
    r"\s*else\s+if\s*\(ret\s*>\s*0\)\s*\{\s*result\s*=\s*VK_SUCCESS;\s*\}"
    r"\s*else\s*\{\s*result\s*=\s*VK_ERROR_DEVICE_LOST;\s*\}",
    re.MULTILINE,
)
if not pattern.search(tail):
    raise SystemExit("wait-any must map poll timeout=0 to VK_TIMEOUT, ready>0 to VK_SUCCESS, errors to device loss")
print("kgsl wait-any poll result mapping ok")
PY
