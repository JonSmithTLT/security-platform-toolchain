#!/usr/bin/env bash
# images/fuzzing/run-fuzzing.sh
# Dispatches coverage-guided harness fuzzing by FUZZ_ENGINE.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${FUZZ_ENGINE:=afl}"
: "${FUZZ_TARGET:?FUZZ_TARGET must be set to the compiled harness path}"

case "${FUZZ_ENGINE}" in
    afl)
        exec run-afl "$@"
        ;;
    libfuzzer)
        exec run-libfuzzer "$@"
        ;;
    honggfuzz)
        exec run-honggfuzz "$@"
        ;;
    *)
        log_error "Unsupported FUZZ_ENGINE=${FUZZ_ENGINE}; expected afl, libfuzzer, or honggfuzz"
        exit 2
        ;;
esac
