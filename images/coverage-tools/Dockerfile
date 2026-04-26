# syntax=docker/dockerfile:1
# images/coverage-tools/Dockerfile
# Offline coverage collection and reporting tools.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT coverage tools image"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gcovr \
        lcov \
        llvm

COPY images/coverage-tools/run-coverage-tools.sh /usr/local/bin/run-coverage-tools
RUN sed -i 's/\r$//' /usr/local/bin/run-coverage-tools \
    && chmod +x /usr/local/bin/run-coverage-tools

USER spt

ENV TARGET_REPO=/workspace \
    COVERAGE_ROOT=/workspace \
    ARTIFACTS_DIR=/artifacts

CMD ["run-coverage-tools"]
