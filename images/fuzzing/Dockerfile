# images/fuzzing/Dockerfile
# AFL++ / libFuzzer harness image.

FROM ghcr.io/jonsmithtlt/spt-base:latest

LABEL org.opencontainers.image.description="SPT fuzzing image (AFL++)"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        afl++ \
        clang \
        llvm \
        gcc \
        g++ \
        make \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY images/fuzzing/run-fuzzing.sh /usr/local/bin/run-fuzzing
RUN chmod +x /usr/local/bin/run-fuzzing

USER spt

ENV FUZZ_TARGET="" \
    FUZZ_TIMEOUT=300 \
    FUZZ_CORPUS=/workspace/corpus \
    ARTIFACTS_DIR=/artifacts \
    AFL_SKIP_CPUFREQ=1

# AFL++ requires /proc/sys/kernel/core_pattern access — use --privileged or
# --security-opt seccomp:unconfined when running this image.
CMD ["run-fuzzing"]
