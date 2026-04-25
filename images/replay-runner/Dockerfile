# images/replay-runner/Dockerfile
# Replays fuzzing crash inputs and PoC files against a target binary.

FROM registry.internal/security-platform/spt-base:latest

LABEL org.opencontainers.image.description="SPT replay runner image"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        gdb \
        valgrind \
        strace \
    && rm -rf /var/lib/apt/lists/*

COPY images/replay-runner/run-replay.sh /usr/local/bin/run-replay
RUN chmod +x /usr/local/bin/run-replay

USER spt

ENV REPLAY_TARGET="" \
    CRASH_DIR=/workspace/crashes \
    ARTIFACTS_DIR=/artifacts \
    REPLAY_TIMEOUT=30 \
    REPLAY_USE_VALGRIND=0

CMD ["run-replay"]
