# syntax=docker/dockerfile:1
# images/replay-runner/Dockerfile
# Replays fuzzing crash inputs and PoC files against a target binary.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT replay runner image"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gdb \
        valgrind \
        strace

COPY images/replay-runner/run-replay.sh /usr/local/bin/run-replay
RUN sed -i 's/\r$//' /usr/local/bin/run-replay \
    && chmod +x /usr/local/bin/run-replay

USER spt

ENV REPLAY_TARGET="" \
    CRASH_DIR=/workspace/crashes \
    ARTIFACTS_DIR=/artifacts \
    REPLAY_TIMEOUT=30 \
    REPLAY_USE_VALGRIND=0

CMD ["run-replay"]
