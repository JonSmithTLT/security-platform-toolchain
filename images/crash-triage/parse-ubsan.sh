#!/usr/bin/env bash
set -euo pipefail
python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
print(json.dumps({"sanitizer": "ubsan", "crash_type": "undefined-behavior" if "runtime error:" in text else "unknown", "frames": [], "top_frame": "", "source_location": ""}))
PY
