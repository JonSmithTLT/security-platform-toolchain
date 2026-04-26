# images/ghidra-exporter/Dockerfile
# Controlled headless Ghidra export workflows.

ARG GHIDRA_BASE_IMAGE=registry.internal/security-platform/spt-ghidra-base:latest
FROM ${GHIDRA_BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT Ghidra exporter image"

USER root

COPY images/ghidra-exporter/run-ghidra-exporter.sh /usr/local/bin/run-ghidra-exporter
RUN sed -i 's/\r$//' /usr/local/bin/run-ghidra-exporter \
    && chmod +x /usr/local/bin/run-ghidra-exporter

USER spt

ENV GHIDRA_HOME=/opt/ghidra \
    GHIDRA_EXPORT_MODE=headless-basic \
    GHIDRA_TARGET=/workspace \
    GHIDRA_PROJECT=/tmp/ghidra-project \
    GHIDRA_PROJECT_NAME=spt-project \
    GHIDRA_ANALYSIS_TIMEOUT=120 \
    ARTIFACTS_DIR=/artifacts

CMD ["run-ghidra-exporter"]
