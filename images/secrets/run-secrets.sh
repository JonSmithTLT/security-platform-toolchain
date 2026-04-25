#!/usr/bin/env bash
# images/secrets/run-secrets.sh
# Runs Gitleaks and/or TruffleHog for secret detection.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${SECRETS_TOOLS:=gitleaks,trufflehog}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/secrets"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
TOTAL_FINDINGS=0

_run_gitleaks() {
    log_info "Running Gitleaks"
    gitleaks detect \
        --source="${TARGET_REPO}" \
        --report-format=json \
        --report-path="${RAW_DIR}/gitleaks.json" \
        --exit-code=0 \
        2>&1 | tee -a "${ARTIFACTS_DIR}/logs/secrets.log" \
        || true
    COUNT=$(jq '. | if type=="array" then length else 0 end' \
        "${RAW_DIR}/gitleaks.json" 2>/dev/null || echo 0)
    log_info "  Gitleaks findings: ${COUNT}"
    TOTAL_FINDINGS=$(( TOTAL_FINDINGS + COUNT ))
}

_run_trufflehog() {
    log_info "Running TruffleHog"
    trufflehog filesystem "${TARGET_REPO}" \
        --json \
        2>&1 | tee "${RAW_DIR}/trufflehog.jsonl" | \
        tee -a "${ARTIFACTS_DIR}/logs/secrets.log" || true
    COUNT=$(wc -l < "${RAW_DIR}/trufflehog.jsonl" 2>/dev/null || echo 0)
    log_info "  TruffleHog findings: ${COUNT}"
    TOTAL_FINDINGS=$(( TOTAL_FINDINGS + COUNT ))
}

IFS=',' read -ra TOOLS <<< "${SECRETS_TOOLS}"
for TOOL in "${TOOLS[@]}"; do
    case "${TOOL// /}" in
        gitleaks)   _run_gitleaks   ;;
        trufflehog) _run_trufflehog ;;
        *) log_warn "Unknown secret scanner: ${TOOL}" ;;
    esac
done

log_info "Total secret findings: ${TOTAL_FINDINGS}"
[[ "${TOTAL_FINDINGS}" -gt 0 ]] && STATUS=failure

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool secrets \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}" \
    --extra "finding_count=${TOTAL_FINDINGS}"

log_info "Secret scanning finished (${STATUS}) in ${DURATION}s"
