#!/usr/bin/env bash
# data-bundles/fetch/fetch-python-wheels.sh
# Compile pinned lock files and download CPython 3.11 Linux x86_64 wheels.
# Requires Docker (runs pip-tools and pip download inside python:3.11-slim).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/artifact-cache.sh"
OUTPUT_ROOT="${1:-${ROOT_DIR}/data-bundles/sources}"
# Normalize to absolute path — docker run -v rejects relative paths and fails
# with a misleading "invalid characters for a local volume name" error.
if [[ "${OUTPUT_ROOT}" != /* ]]; then
    OUTPUT_ROOT="${ROOT_DIR}/${OUTPUT_ROOT}"
fi
mkdir -p "${OUTPUT_ROOT}"
OUTPUT_ROOT="$(cd "${OUTPUT_ROOT}" && pwd)"
WHEELS_ROOT="${OUTPUT_ROOT}/python-wheels/py311"
LOCK_ROOT="${ROOT_DIR}/requirements/py311"
IN_ROOT="${ROOT_DIR}/requirements/py311"
CACHE_STAGE="$(mktemp -d)"
trap 'rm -rf "${CACHE_STAGE}"' EXIT
LOG_DIR="${WHEELHOUSE_LOG_DIR:-${ROOT_DIR}/artifacts/python-wheelhouse-fetch}"
LOG_FILE="${LOG_DIR}/py311-fetch.log"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

restore_host_ownership() {
    local path="$1"
    [[ -e "${path}" ]] || return 0
    docker run --rm \
        -v "${path}:/target" \
        python:3.11-slim \
        sh -c "chown -R ${HOST_UID}:${HOST_GID} /target" >/dev/null 2>&1 || true
}

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
mkdir -p "${LOG_DIR}"
mkdir -p "${WHEELS_ROOT}"
restore_host_ownership "${WHEELS_ROOT}"
restore_host_ownership "${LOCK_ROOT}"
for group in "${REQUIRED_GROUPS[@]}" "${OPTIONAL_GROUPS[@]}"; do
    mkdir -p "${WHEELS_ROOT}/${group}"
done

# Cache key = digest of all .in files; if they haven't changed the wheels are identical
_WHEEL_CACHE_KEY="$(spt_cache_key "py311-wheels-v1" "$(cat "${IN_ROOT}"/*.in 2>/dev/null)")"
if [[ "${FORCE_FETCH:-0}" != "1" ]] && spt_cache_restore "${_WHEEL_CACHE_KEY}" "${CACHE_STAGE}"; then
    if [[ -d "${CACHE_STAGE}/wheels" ]]; then
        mkdir -p "${WHEELS_ROOT}"
        cp -a "${CACHE_STAGE}/wheels/." "${WHEELS_ROOT}/"
    else
        # Backward compatibility for early py311 cache entries that stored
        # wheel files at the cache root and did not include generated locks.
        mkdir -p "${WHEELS_ROOT}"
        cp -a "${CACHE_STAGE}/." "${WHEELS_ROOT}/"
        find "${WHEELS_ROOT}" -type f -name '*.lock' -delete
    fi
    if [[ -d "${CACHE_STAGE}/locks" ]]; then
        cp -a "${CACHE_STAGE}/locks/." "${LOCK_ROOT}/"
        mkdir -p "${WHEELS_ROOT}/locks"
        cp -a "${CACHE_STAGE}/locks/." "${WHEELS_ROOT}/locks/"
    fi
    if [[ -f "${LOCK_ROOT}/core-python.lock" ]]; then
        printf '==> Wheels cache hit (key=%.12s...); skipping Docker pip download\n' "${_WHEEL_CACHE_KEY}"
        printf '==> To force re-fetch: FORCE_FETCH=1 make python-wheelhouse-fetch\n'
        exit 0
    fi
    printf 'WARN: wheel cache hit did not include lock files; refreshing cache\n' >&2
    printf 'WARN: invalidating incomplete wheel cache entry: %s\n' "${_WHEEL_CACHE_KEY}" >&2
    spt_cache_invalidate "${_WHEEL_CACHE_KEY}"
fi

printf '==> Compiling lock files and downloading wheels (python:3.11-slim)\n'
printf '==> Wheelhouse fetch log: %s\n' "${LOG_FILE}"

set +e
docker run --rm -i \
    -v "${IN_ROOT}:/in:ro" \
    -v "${LOCK_ROOT}:/locks" \
    -v "${WHEELS_ROOT}:/wheels" \
    python:3.11-slim \
    python3 - 2>&1 <<'PYEOF' | tee "${LOG_FILE}"
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
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)

def run_checked(cmd, group=None, step=None):
    proc = run(cmd)
    if proc.stdout:
        print(proc.stdout.rstrip(), flush=True)
    if proc.returncode != 0:
        if group:
            print(f"ERROR: group '{group}' failed during {step}", file=sys.stderr, flush=True)
            if step == "download":
                print("HINT: This usually means a locked package has no binary wheel for the selected Python/platform target.", file=sys.stderr, flush=True)
                print("HINT: Relax or remove the dependency in the corresponding requirements/py311/*.in file, then rerun with FORCE_FETCH=1.", file=sys.stderr, flush=True)
        raise subprocess.CalledProcessError(proc.returncode, cmd, output=proc.stdout)

print("Installing pip-tools ...", flush=True)
run_checked([sys.executable, "-m", "pip", "install", "--quiet", "--upgrade", "pip", "pip-tools"], step="pip-tools install")

failed_optional = []

for group in REQUIRED + OPTIONAL:
    optional = group in OPTIONAL
    in_file  = f"/in/{group}.in"
    lock_file = f"/locks/{group}.lock"
    wheel_dir = f"/wheels/{group}"
    os.makedirs(wheel_dir, exist_ok=True)

    print(f"\n==> Group: {group}{'  [optional]' if optional else ''}", flush=True)

    try:
        run_checked([
            sys.executable, "-m", "piptools", "compile",
            "--resolver=backtracking",
            "--strip-extras",
            "--no-header",
            "--quiet",
            f"--output-file={lock_file}",
            in_file,
        ], group=group, step="compile")

        run_checked([
            sys.executable, "-m", "pip", "download",
            "--only-binary=:all:",
            "--python-version=3.11",
            "--implementation=cp",
            "--platform=manylinux_2_17_x86_64",
            "--abi=cp311",
            "--dest", wheel_dir,
            "--quiet",
            "-r", lock_file,
        ], group=group, step="download")

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
docker_rc=${PIPESTATUS[0]}
set -e
restore_host_ownership "${WHEELS_ROOT}"
restore_host_ownership "${LOCK_ROOT}"
if (( docker_rc != 0 )); then
    printf 'ERROR: python wheelhouse fetch failed; see %s\n' "${LOG_FILE}" >&2
    printf '       Last error context:\n' >&2
    tail -n 30 "${LOG_FILE}" >&2 || true
    exit "${docker_rc}"
fi

mkdir -p "${WHEELS_ROOT}/locks"
find "${LOCK_ROOT}" -maxdepth 1 -type f -name '*.lock' -exec cp -a {} "${WHEELS_ROOT}/locks/" \;
if [[ ! -f "${WHEELS_ROOT}/locks/core-python.lock" ]]; then
    printf 'ERROR: wheelhouse fetch did not produce required lock: %s/locks/core-python.lock\n' "${WHEELS_ROOT}" >&2
    exit 2
fi

rm -rf "${CACHE_STAGE:?}/"*
mkdir -p "${CACHE_STAGE}/wheels" "${CACHE_STAGE}/locks"
cp -a "${WHEELS_ROOT}/." "${CACHE_STAGE}/wheels/"
find "${LOCK_ROOT}" -maxdepth 1 -type f -name '*.lock' -exec cp -a {} "${CACHE_STAGE}/locks/" \;
spt_cache_store "${_WHEEL_CACHE_KEY}" "${CACHE_STAGE}" "py311-wheels"
printf '==> Wheels written to %s (cached as %.12s...)\n' "${WHEELS_ROOT}" "${_WHEEL_CACHE_KEY}"
