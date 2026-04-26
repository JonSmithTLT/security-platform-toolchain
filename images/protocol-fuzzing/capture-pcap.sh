#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACTS_DIR:=/artifacts}"
: "${PROTOCOL_TARGET_PORT:=9001}"
RAW_DIR="${ARTIFACTS_DIR}/results/protocol-fuzzing/raw/pcaps"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"
if command -v tcpdump >/dev/null 2>&1; then
    timeout "${PCAP_TIMEOUT:-30}" tcpdump -i lo -w "${RAW_DIR}/protocol.pcap" "tcp port ${PROTOCOL_TARGET_PORT}" > "${ARTIFACTS_DIR}/logs/tcpdump.log" 2>&1 &
    echo "$!" > "${ARTIFACTS_DIR}/logs/tcpdump.pid"
fi
