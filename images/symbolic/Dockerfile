# syntax=docker/dockerfile:1
# images/symbolic/Dockerfile
# Symbolic execution using angr (Python) and optional KLEE support.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT symbolic execution image"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        libffi-dev \
        libssl-dev \
        python3-dev \
    && pip3 install angr==9.2.127

COPY images/symbolic/run-symbolic.sh /usr/local/bin/run-symbolic
COPY images/symbolic/angr-explore.py /usr/local/lib/spt/angr-explore.py
RUN sed -i 's/\r$//' \
        /usr/local/bin/run-symbolic \
        /usr/local/lib/spt/angr-explore.py \
    && chmod +x /usr/local/bin/run-symbolic

USER spt

ENV SYMBOLIC_ENGINE=angr \
    TARGET_BINARY="" \
    SYMBOLIC_TIMEOUT=600 \
    ARTIFACTS_DIR=/artifacts

CMD ["run-symbolic"]
