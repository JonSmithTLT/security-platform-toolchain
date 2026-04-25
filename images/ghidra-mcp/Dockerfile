# images/ghidra-mcp/Dockerfile
# Reusable local Ghidra environment for MCP/analyst workflows.

ARG GHIDRA_BASE_IMAGE=registry.internal/security-platform/spt-ghidra-base:latest
FROM ${GHIDRA_BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT Ghidra MCP environment image"

USER root

COPY images/ghidra-mcp/run-ghidra-mcp.sh /usr/local/bin/run-ghidra-mcp
RUN sed -i 's/\r$//' /usr/local/bin/run-ghidra-mcp \
    && chmod +x /usr/local/bin/run-ghidra-mcp

USER spt

ENV GHIDRA_HOME=/opt/ghidra \
    ARTIFACTS_DIR=/artifacts

CMD ["run-ghidra-mcp"]
