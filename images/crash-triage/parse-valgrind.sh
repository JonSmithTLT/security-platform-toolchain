#!/usr/bin/env bash
set -euo pipefail
python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
kind = "invalid-read" if "Invalid read" in text else "invalid-write" if "Invalid write" in text else "unknown"
print(json.dumps({"sanitizer": "valgrind", "crash_type": kind, "frames": [], "top_frame": "", "source_location": ""}))
PY
