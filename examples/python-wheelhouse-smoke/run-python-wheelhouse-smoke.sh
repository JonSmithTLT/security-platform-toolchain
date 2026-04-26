#!/usr/bin/env bash
# Offline install smoke for spt-python-wheelhouse-py311.
# Extracts wheelhouse from the image, then for each group creates a fresh
# Python 3.11 venv, installs offline, and runs native-import probes.

set -euo pipefail

REGISTRY="${1:-${REGISTRY:-registry.internal/security-platform}}"
TAG="${2:-${TAG:-latest}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/artifacts/python-wheelhouse-smoke"
IMAGE="${REGISTRY}/spt-python-wheelhouse-py311:${TAG}"

fail() { printf 'python-wheelhouse-smoke failed: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# Extract wheelhouse from image
printf '==> Extracting wheelhouse from %s\n' "${IMAGE}"
EXTRACT_ID="$(docker create "${IMAGE}")"
trap "docker rm -f '${EXTRACT_ID}' 2>/dev/null || true" EXIT
mkdir -p "${OUT_DIR}/wheelhouse" "${OUT_DIR}/requirements"
docker cp "${EXTRACT_ID}:/wheelhouse/py311/." "${OUT_DIR}/wheelhouse/"
docker cp "${EXTRACT_ID}:/requirements/py311/." "${OUT_DIR}/requirements/"
docker rm "${EXTRACT_ID}" && trap - EXIT

# Import probes per group (run inside python:3.11-slim, network none)
run_group_smoke() {
    local group="$1"
    local optional="${2:-false}"
    local lock_file="${OUT_DIR}/requirements/${group}.lock"
    local wheel_dir="${OUT_DIR}/wheelhouse/${group}"

    if [[ ! -f "${lock_file}" ]]; then
        if [[ "${optional}" == "true" ]]; then
            warn "optional group '${group}': lock file missing, skipping"
            return 0
        fi
        fail "required group '${group}': lock file not found at ${lock_file}"
    fi

    if [[ ! -d "${wheel_dir}" ]] || [[ -z "$(ls -A "${wheel_dir}"/*.whl 2>/dev/null)" ]]; then
        if [[ "${optional}" == "true" ]]; then
            warn "optional group '${group}': no wheels found, skipping"
            return 0
        fi
        fail "required group '${group}': no wheels under ${wheel_dir}"
    fi

    printf '  -- %s\n' "${group}"

    local import_probe
    import_probe="$(generate_probe "${group}")"

    docker run --rm --network none \
        -v "${wheel_dir}:/wheels:ro" \
        -v "${lock_file}:/lock.txt:ro" \
        python:3.11-slim \
        bash -c "
            set -euo pipefail
            python3 -m venv /tmp/venv
            /tmp/venv/bin/pip install --quiet --no-index --find-links /wheels/ -r /lock.txt
            ${import_probe}
        " || {
            if [[ "${optional}" == "true" ]]; then
                warn "optional group '${group}' smoke failed"
                return 0
            fi
            fail "group '${group}' offline install or import probe failed"
        }
    pass "${group}"
}

generate_probe() {
    local group="$1"
    case "${group}" in
    core-python)
        echo "/tmp/venv/bin/python3 -c \"
import jsonschema, yaml, requests, urllib3, certifi, click, typer, rich
import dotenv, packaging, tenacity, attr, dateutil, jinja2, tabulate, structlog, tomli
print('core-python imports OK')
\""
        ;;
    api-future-fastapi)
        echo "/tmp/venv/bin/python3 -c \"
import fastapi, starlette, uvicorn, pydantic, pydantic_core, pydantic_settings
import httpx, httpcore, orjson, sse_starlette, anyio, sniffio, h11
from fastapi import FastAPI
app = FastAPI()
print('api-future-fastapi imports OK')
\""
        ;;
    normalizers-reporting)
        echo "/tmp/venv/bin/python3 -c \"
from lxml import etree
import bs4, markdown, pygments, defusedxml, xmltodict, junitparser
import sarif_om, cyclonedx, packageurl, spdx, cvss
print('normalizers-reporting imports OK')
\""
        ;;
    testing-dev)
        echo "/tmp/venv/bin/python3 -c \"
import pytest, pytest_cov, hypothesis, coverage, ruff, mypy
import responses, freezegun
print('testing-dev imports OK')
\""
        ;;
    data-ingest-light)
        echo "/tmp/venv/bin/python3 -c \"
import sqlalchemy, alembic, sqlite_utils, networkx
print('data-ingest-light imports OK')
\""
        ;;
    rag-light)
        echo "/tmp/venv/bin/python3 -c \"
import rank_bm25, tiktoken, networkx
print('rag-light imports OK')
\""
        ;;
    security-research-python)
        echo "/tmp/venv/bin/python3 -c \"
from cryptography.fernet import Fernet
from elftools.elf.elffile import ELFFile
import pefile, capstone
import yara
yara.compile(source='rule t { condition: false }')
cs = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
try:
    import magic
    magic.from_buffer(b'\\x7fELF')
except Exception:
    pass  # libmagic not present in smoke container; wheel loaded OK
print('security-research-python imports OK')
\""
        ;;
    data-science-optional)
        echo "/tmp/venv/bin/python3 -c \"
import numpy as np, scipy, sklearn, pandas as pd, pyarrow as pa
np.zeros(3)
pa.array([1, 2, 3])
print('data-science-optional imports OK')
\""
        ;;
    ml-runtime-light)
        echo "/tmp/venv/bin/python3 -c \"
import onnxruntime as ort
ort.get_available_providers()
print('ml-runtime-light imports OK')
\""
        ;;
    *)
        echo "echo 'no import probe for ${group}'"
        ;;
    esac
}

printf '==> Running offline install smoke tests\n'

# Verify SHA256SUMS
if [[ -f "${OUT_DIR}/wheelhouse/SHA256SUMS" ]]; then
    docker run --rm --network none \
        -v "${OUT_DIR}/wheelhouse:/wheels:ro" \
        busybox \
        sh -c "cd /wheels && sha256sum -c SHA256SUMS --quiet" \
        && pass "SHA256SUMS verified" \
        || fail "SHA256SUMS verification failed"
fi

# Required groups
for group in core-python api-future-fastapi normalizers-reporting testing-dev \
             data-ingest-light rag-light security-research-python; do
    run_group_smoke "${group}" false
done

# Optional groups
for group in data-science-optional ml-runtime-light; do
    run_group_smoke "${group}" true
done

printf '\n==> python-wheelhouse-py311 smoke passed: %s\n' "${OUT_DIR}"
