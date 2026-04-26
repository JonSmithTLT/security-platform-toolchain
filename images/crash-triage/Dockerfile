# images/crash-triage/Dockerfile
# Automated crash evidence improvement and sanitizer log triage.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT crash triage image"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        binutils \
        elfutils \
        file \
        gdb \
        lldb \
        llvm \
        strace \
    && (apt-get install -y --no-install-recommends ltrace || true) \
    && rm -rf /var/lib/apt/lists/*

COPY images/crash-triage/run-crash-triage.sh /usr/local/bin/run-crash-triage
COPY images/crash-triage/triage-crash.sh /usr/local/bin/triage-crash
COPY images/crash-triage/symbolize-stack.sh /usr/local/bin/symbolize-stack
COPY images/crash-triage/parse-asan.sh /usr/local/bin/parse-asan
COPY images/crash-triage/parse-ubsan.sh /usr/local/bin/parse-ubsan
COPY images/crash-triage/parse-tsan.sh /usr/local/bin/parse-tsan
COPY images/crash-triage/parse-msan.sh /usr/local/bin/parse-msan
COPY images/crash-triage/parse-valgrind.sh /usr/local/bin/parse-valgrind
COPY images/crash-triage/hash-crash.sh /usr/local/bin/hash-crash
COPY images/crash-triage/reproduce-crash.sh /usr/local/bin/reproduce-crash
COPY images/crash-triage/emit-triage-report.sh /usr/local/bin/emit-triage-report

RUN sed -i 's/\r$//' /usr/local/bin/run-crash-triage /usr/local/bin/triage-crash /usr/local/bin/symbolize-stack /usr/local/bin/parse-asan /usr/local/bin/parse-ubsan /usr/local/bin/parse-tsan /usr/local/bin/parse-msan /usr/local/bin/parse-valgrind /usr/local/bin/hash-crash /usr/local/bin/reproduce-crash /usr/local/bin/emit-triage-report \
    && chmod +x /usr/local/bin/run-crash-triage /usr/local/bin/triage-crash /usr/local/bin/symbolize-stack /usr/local/bin/parse-asan /usr/local/bin/parse-ubsan /usr/local/bin/parse-tsan /usr/local/bin/parse-msan /usr/local/bin/parse-valgrind /usr/local/bin/hash-crash /usr/local/bin/reproduce-crash /usr/local/bin/emit-triage-report

USER spt

ENV CRASH_LOG=/workspace/asan.log \
    CRASH_INPUT=/workspace/crash \
    CRASH_BINARY=/workspace/target \
    REPRO_COMMAND="" \
    ARTIFACTS_DIR=/artifacts

CMD ["run-crash-triage"]
