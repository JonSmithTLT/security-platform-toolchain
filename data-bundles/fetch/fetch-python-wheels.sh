#!/usr/bin/env bash
# data-bundles/fetch/fetch-python-wheels.sh
# Compile pinned lock files and download CPython 3.11 Linux x86_64 wheels.
# Requires Docker (runs pip-tools and pip download inside python:3.11-slim).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_ROOT="${1:-${ROOT_DIR}/data-bundles/sources}"
WHEELS_ROOT="${OUTPUT_ROOT}/python-wheels/py311"
LOCK_ROOT="${ROOT_DIR}/requirements/py311"
IN_ROOT="${ROOT_DIR}/requirements/py311"

REQUIRED_GROUPS=(
    core-python
    api-future-fastapi
    normalizers-reporting
    testing-dev
    data-ingest-light
    rag-light
    security-research-python
)

OPTIONAL_GROUPS=(
    data-science-optional
    ml-runtime-light
)

mkdir -p "${LOCK_ROOT}"
for group in "${REQUIRED_GROUPS[@]}" "${OPTIONAL_GROUPS[@]}"; do
    mkdir -p "${WHEELS_ROOT}/${group}"
done

printf '==> Compiling lock files and downloading wheels (python:3.11-slim)\n'

docker run --rm \
    -v "${IN_ROOT}:/in:ro" \
    -v "${LOCK_ROOT}:/locks" \
    -v "${WHEELS_ROOT}:/wheels" \
    python:3.11-slim \
    python3 - <<'PYEOF'
import subprocess, sys, os, json, hashlib, datetime, pathlib

REQUIRED = [
    "core-python",
    "api-future-fastapi",
    "normalizers-reporting",
    "testing-dev",
    "data-ingest-light",
    "rag-light",
    "security-research-python",
]
OPTIONAL = ["data-science-optional", "ml-runtime-light"]

def run(cmd, **kw):
    print(f"  $ {' '.join(str(c) for c in cmd)}", flush=True)
    subprocess.run(cmd, check=True, **kw)

print("Installing pip-tools ...", flush=True)
run([sys.executable, "-m", "pip", "install", "--quiet", "--upgrade", "pip", "pip-tools"])

failed_optional = []

for group in REQUIRED + OPTIONAL:
    optional = group in OPTIONAL
    in_file  = f"/in/{group}.in"
    lock_file = f"/locks/{group}.lock"
    wheel_dir = f"/wheels/{group}"
    os.makedirs(wheel_dir, exist_ok=True)

    print(f"\n==> Group: {group}{'  [optional]' if optional else ''}", flush=True)

    try:
        run([
            sys.executable, "-m", "piptools", "compile",
            "--resolver=backtracking",
            "--strip-extras",
            "--no-header",
            "--quiet",
            f"--output-file={lock_file}",
            in_file,
        ])

        run([
            sys.executable, "-m", "pip", "download",
            "--only-binary=:all:",
            "--python-version=3.11",
            "--implementation=cp",
            "--platform=manylinux_2_17_x86_64",
            "--abi=cp311",
            "--dest", wheel_dir,
            "--quiet",
            "-r", lock_file,
        ])

        count = len(list(pathlib.Path(wheel_dir).glob("*.whl")))
        print(f"    {count} wheel(s) downloaded", flush=True)

    except subprocess.CalledProcessError as exc:
        if optional:
            print(f"WARNING: optional group '{group}' failed — {exc}", file=sys.stderr, flush=True)
            failed_optional.append(group)
        else:
            print(f"ERROR: required group '{group}' failed", file=sys.stderr)
            sys.exit(1)

# SHA256SUMS
print("\n==> Generating SHA256SUMS ...", flush=True)
sums = []
for whl in sorted(pathlib.Path("/wheels").rglob("*.whl")):
    digest = hashlib.sha256(whl.read_bytes()).hexdigest()
    rel = whl.relative_to("/wheels")
    sums.append(f"{digest}  {rel}\n")
pathlib.Path("/wheels/SHA256SUMS").write_text("".join(sums))
print(f"  {len(sums)} entries", flush=True)

# Manifest
print("==> Generating wheelhouse-manifest.json ...", flush=True)
manifest = []
for whl in sorted(pathlib.Path("/wheels").rglob("*.whl")):
    group = whl.parent.name
    parts = whl.stem.split("-")
    digest = hashlib.sha256(whl.read_bytes()).hexdigest()
    lock_src = f"{group}.lock" if (pathlib.Path(f"/locks/{group}.lock")).exists() else ""
    manifest.append({
        "package":         parts[0],
        "version":         parts[1] if len(parts) > 1 else "",
        "filename":        whl.name,
        "group":           group,
        "sha256":          digest,
        "python_target":   "cp311",
        "platform_target": "linux_x86_64",
        "generated_at":    datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_lock":     lock_src,
    })
pathlib.Path("/wheels/wheelhouse-manifest.json").write_text(
    json.dumps({"schema_version": "1.0.0", "python": "3.11", "platform": "linux_x86_64",
                "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
                "wheels": manifest}, indent=2) + "\n"
)
print(f"  {len(manifest)} entries", flush=True)

if failed_optional:
    print(f"\nWARN: optional groups that failed: {', '.join(failed_optional)}", file=sys.stderr)

print("\n==> fetch-python-wheels complete", flush=True)
PYEOF

printf '==> Wheels written to %s\n' "${WHEELS_ROOT}"
