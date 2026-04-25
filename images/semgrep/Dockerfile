# images/semgrep/Dockerfile
# Semgrep SAST scanner with custom rule support.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT Semgrep SAST image"

USER root

RUN pip3 install --no-cache-dir semgrep==1.75.0

COPY images/semgrep/run-semgrep.sh /usr/local/bin/run-semgrep
RUN sed -i 's/\r$//' /usr/local/bin/run-semgrep \
    && chmod +x /usr/local/bin/run-semgrep

USER spt

ENV TARGET_REPO=/workspace \
    SEMGREP_RULES=/rules \
    ARTIFACTS_DIR=/artifacts \
    SEMGREP_TIMEOUT=300 \
    SEMGREP_JOBS=4

CMD ["run-semgrep"]
