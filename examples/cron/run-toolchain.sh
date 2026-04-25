#!/usr/bin/env bash
# examples/cron/run-toolchain.sh
# Cron-job driver that runs the full security-platform-toolchain pipeline
# against a local repository clone on a schedule.
#
# Install:
#   chmod +x examples/cron/run-toolchain.sh
#   crontab -e
#   # Run every night at 02:00
#   0 2 * * * /path/to/security-platform-toolchain/examples/cron/run-toolchain.sh >> /var/log/spt-cron.log 2>&1

set -euo pipefail

# ── Configuration (override via environment) ──────────────────────────────
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
TAG="${TAG:-latest}"
TARGET_REPO="${TARGET_REPO:-/opt/repos/my-project}"
ARTIFACTS_BASE="${ARTIFACTS_BASE:-/var/spt/artifacts}"
JOB_ID="${JOB_ID:-cron-$(date +%Y%m%dT%H%M%S)}"
CODEQL_LANGUAGE="${CODEQL_LANGUAGE:-cpp}"
LOG_LEVEL="${LOG_LEVEL:-info}"

# ── Derived paths ─────────────────────────────────────────────────────────
ARTIFACTS="${ARTIFACTS_BASE}/${JOB_ID}"
mkdir -p "${ARTIFACTS}"

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Starting SPT cron run JOB_ID=${JOB_ID}"

_run() {
    local image="$1"; shift
    docker run --rm \
        -e JOB_ID="${JOB_ID}" \
        -e LOG_LEVEL="${LOG_LEVEL}" \
        -e ARTIFACTS_DIR=/artifacts \
        -v "${TARGET_REPO}:/workspace:ro" \
        -v "${ARTIFACTS}:/artifacts" \
        "$@" \
        "${REGISTRY}/${image}:${TAG}"
}

# ── Stages ────────────────────────────────────────────────────────────────
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stage: secrets"
_run spt-secrets || true

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stage: semgrep"
_run spt-semgrep \
    -v "$(pwd)/rules/semgrep:/rules:ro" \
    -e SEMGREP_RULES=/rules \
    || true

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stage: codeql"
_run spt-codeql \
    -v "$(pwd)/queries/codeql:/queries:ro" \
    -e CODEQL_LANGUAGE="${CODEQL_LANGUAGE}" \
    -e CODEQL_QUERIES=/queries \
    || true

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stage: sbom"
_run spt-sbom -e SBOM_FORMAT=cyclonedx-json || true

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stage: c-cpp-analysis"
_run spt-c-cpp-analysis || true

# ── Report ─────────────────────────────────────────────────────────────────
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Artifacts written to ${ARTIFACTS}"

# Optionally upload to Nexus
if [[ -n "${NEXUS_URL:-}" ]]; then
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Uploading artifacts to Nexus"
    docker run --rm \
        -e JOB_ID="${JOB_ID}" \
        -e GITNEXUS_MODE=upload \
        -e NEXUS_URL="${NEXUS_URL}" \
        -e NEXUS_USER="${NEXUS_USER:-}" \
        -e NEXUS_PASS="${NEXUS_PASS:-}" \
        -e NEXUS_REPO="${NEXUS_REPO:-spt-artifacts}" \
        -v "${ARTIFACTS}:/artifacts" \
        "${REGISTRY}/spt-gitnexus:${TAG}"
fi

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] SPT cron run ${JOB_ID} complete"
