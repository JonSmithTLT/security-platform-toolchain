# images/c-cpp-analysis/Dockerfile
# Static analysis for C/C++ projects using clang-tidy, cppcheck, and scan-build.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT C/C++ static analysis image"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        clang \
        clang-tidy \
        clang-tools \
        cppcheck \
        bear \
        cmake \
        ninja-build \
        gcc \
        g++ \
        make \
    && rm -rf /var/lib/apt/lists/*

COPY images/c-cpp-analysis/run-analysis.sh /usr/local/bin/run-analysis
RUN sed -i 's/\r$//' /usr/local/bin/run-analysis \
    && chmod +x /usr/local/bin/run-analysis

USER spt

ENV TARGET_REPO=/workspace \
    ARTIFACTS_DIR=/artifacts \
    CPPCHECK_SEVERITY=warning \
    CLANG_TIDY_CHECKS="-*,clang-analyzer-*,cert-*,bugprone-*"

CMD ["run-analysis"]
