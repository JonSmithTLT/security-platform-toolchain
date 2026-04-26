# images/fuzzing/Dockerfile
# Coverage-guided compiled harness fuzzing image.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT fuzzing image (AFL++, libFuzzer, optional honggfuzz)"

ARG HONGGFUZZ_REPO=https://github.com/google/honggfuzz.git
ARG HONGGFUZZ_REF=master

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        afl++ \
        binutils \
        binutils-dev \
        clang \
        cmake \
        file \
        gcc \
        g++ \
        git \
        libblocksruntime-dev \
        make \
        ninja-build \
        libclang-rt-18-dev \
        libipt-dev \
        libssl-dev \
        libunwind-dev \
        llvm \
        llvm-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --branch "${HONGGFUZZ_REF}" "${HONGGFUZZ_REPO}" /tmp/honggfuzz \
    || (git clone --depth=1 "${HONGGFUZZ_REPO}" /tmp/honggfuzz && git -C /tmp/honggfuzz fetch --depth=1 origin "${HONGGFUZZ_REF}" && git -C /tmp/honggfuzz checkout FETCH_HEAD) \
    && make -C /tmp/honggfuzz \
    && install -m 0755 /tmp/honggfuzz/honggfuzz /usr/local/bin/honggfuzz \
    && cp -a /tmp/honggfuzz/hfuzz_cc/hfuzz-* /usr/local/bin/ \
    && chmod +x /usr/local/bin/hfuzz-* \
    && rm -rf /tmp/honggfuzz

RUN honggfuzz 2>&1 | head -20 >/usr/local/share/spt/honggfuzz-help.txt || true \
    && rm -rf /var/lib/apt/lists/*

COPY images/fuzzing/run-fuzzing.sh /usr/local/bin/run-fuzzing
COPY images/fuzzing/run-afl.sh /usr/local/bin/run-afl
COPY images/fuzzing/run-libfuzzer.sh /usr/local/bin/run-libfuzzer
COPY images/fuzzing/run-honggfuzz.sh /usr/local/bin/run-honggfuzz
COPY images/fuzzing/collect-crashes.sh /usr/local/bin/collect-crashes
RUN sed -i 's/\r$//' /usr/local/bin/run-fuzzing \
        /usr/local/bin/run-afl \
        /usr/local/bin/run-libfuzzer \
        /usr/local/bin/run-honggfuzz \
        /usr/local/bin/collect-crashes \
    && chmod +x /usr/local/bin/run-fuzzing /usr/local/bin/run-afl /usr/local/bin/run-libfuzzer /usr/local/bin/run-honggfuzz /usr/local/bin/collect-crashes

USER spt

ENV FUZZ_ENGINE=afl \
    FUZZ_TARGET="" \
    FUZZ_TIMEOUT=300 \
    FUZZ_CORPUS=/workspace/corpus \
    FUZZ_OUTPUT_CORPUS=/artifacts/results/fuzzing/evidence/seeds \
    ARTIFACTS_DIR=/artifacts \
    SPT_ASAN_OPTIONS_SYMBOLIZED=abort_on_error=1:symbolize=1:detect_leaks=0 \
    SPT_ASAN_OPTIONS_AFL=abort_on_error=1:symbolize=0:detect_leaks=0 \
    HONGGFUZZ_REF="${HONGGFUZZ_REF}" \
    HONGGFUZZ_REPO="${HONGGFUZZ_REPO}" \
    UBSAN_OPTIONS=abort_on_error=1:print_stacktrace=1 \
    AFL_SKIP_CPUFREQ=1 \
    AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

# AFL++ requires /proc/sys/kernel/core_pattern access — use --privileged or
# --security-opt seccomp:unconfined when running this image.
CMD ["run-fuzzing"]
