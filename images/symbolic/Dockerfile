# images/symbolic/Dockerfile
# Symbolic execution using angr (Python) and optional KLEE support.

FROM registry.internal/security-platform/spt-base:latest

LABEL org.opencontainers.image.description="SPT symbolic execution image"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        libffi-dev \
        libssl-dev \
        python3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir angr==9.2.127

COPY images/symbolic/run-symbolic.sh /usr/local/bin/run-symbolic
COPY images/symbolic/angr-explore.py /usr/local/lib/spt/angr-explore.py
RUN chmod +x /usr/local/bin/run-symbolic

USER spt

ENV SYMBOLIC_ENGINE=angr \
    TARGET_BINARY="" \
    SYMBOLIC_TIMEOUT=600 \
    ARTIFACTS_DIR=/artifacts

CMD ["run-symbolic"]
