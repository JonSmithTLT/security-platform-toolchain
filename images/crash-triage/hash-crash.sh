#!/usr/bin/env bash
set -euo pipefail
python3 - "$1" <<'PY'
import hashlib
import json
import sys

data = json.loads(sys.argv[1])
frames = data.get("frames", [])
basis = "\n".join(frames[:5]) or data.get("top_frame", "") or data.get("crash_type", "unknown")
stack_hash = hashlib.sha256(basis.encode()).hexdigest()[:16]
dedup_basis = f"{data.get('sanitizer')}:{data.get('crash_type')}:{frames[0] if frames else ''}"
dedup_hash = hashlib.sha256(dedup_basis.encode()).hexdigest()[:16]
print(json.dumps({"stack_hash": stack_hash, "dedup_hash": dedup_hash, "similarity_key": dedup_basis}))
PY
