#!/usr/bin/env bash
set -euo pipefail

: "${PROTOCOL_TARGET_HOST:=127.0.0.1}"
: "${PROTOCOL_TARGET_PORT:=9001}"
case_file="${1:?case file required}"
nc -w 2 "${PROTOCOL_TARGET_HOST}" "${PROTOCOL_TARGET_PORT}" < "${case_file}"
