#!/usr/bin/env bash
set -euo pipefail
python3 - "$1" <<'PY'
import json
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
finding = "unknown"
m = re.search(r"ERROR: AddressSanitizer: ([^\s]+)", text)
if m:
    finding = m.group(1)
frames = []
for line in text.splitlines():
    if re.match(r"\s*#\d+\s+", line):
        frames.append(line.strip())
top = frames[0] if frames else ""
loc = ""
if top:
    m = re.search(r"(\S+:\d+:\d+|\S+:\d+)", top)
    if m:
        loc = m.group(1)
print(json.dumps({"sanitizer": "asan", "crash_type": finding, "frames": frames, "top_frame": top, "source_location": loc}))
PY
