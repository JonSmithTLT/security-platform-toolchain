# syntax=docker/dockerfile:1
# images/ghidra-mcp/Dockerfile
# Bethington GhidraMCP runtime for analyst and Ghidra Server workflows.

ARG GHIDRA_BASE_IMAGE=registry.internal/security-platform/spt-ghidra-base:latest
FROM ${GHIDRA_BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT bethington GhidraMCP image"

USER root

ARG GHIDRA_VERSION=12.0.4
ARG GHIDRA_MCP_REPO=https://github.com/bethington/ghidra-mcp.git
ARG GHIDRA_MCP_REF=v5.5.0

ENV GHIDRA_HOME=/opt/ghidra \
    GHIDRA_MCP_HOME=/opt/ghidra-mcp \
    GHIDRA_MCP_REF=${GHIDRA_MCP_REF} \
    GHIDRA_MCP_PORT=8089 \
    GHIDRA_MCP_BIND_ADDRESS=127.0.0.1 \
    GHIDRA_MCP_MODE=smoke \
    JAVA_OPTS="-Xmx4g -XX:+UseG1GC"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-21-jdk \
        maven

RUN git init "${GHIDRA_MCP_HOME}" \
    && cd "${GHIDRA_MCP_HOME}" \
    && git remote add origin "${GHIDRA_MCP_REPO}" \
    && git fetch --depth 1 origin "${GHIDRA_MCP_REF}" \
    && git checkout --detach FETCH_HEAD \
    && git rev-parse HEAD > .spt-source-revision \
    && chown -R spt:spt "${GHIDRA_MCP_HOME}"

RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=cache,target=/root/.m2 \
    cd "${GHIDRA_MCP_HOME}" \
    && python3 -m pip install --disable-pip-version-check -r requirements.txt \
    && if [ -d tools ]; then \
        python3 -m tools.setup ensure-prereqs --ghidra-path "${GHIDRA_HOME}" && \
        python3 -m tools.setup build && \
        python3 -m tools.setup deploy --ghidra-path "${GHIDRA_HOME}"; \
       else \
        ./ghidra-mcp-setup.sh --setup-deps --ghidra-path "${GHIDRA_HOME}" --ghidra-version "${GHIDRA_VERSION}" && \
        ./ghidra-mcp-setup.sh --build-only --ghidra-path "${GHIDRA_HOME}" --ghidra-version "${GHIDRA_VERSION}" && \
        ./ghidra-mcp-setup.sh --deploy --skip-build --ghidra-path "${GHIDRA_HOME}" --ghidra-version "${GHIDRA_VERSION}"; \
       fi \
    && mkdir -p /opt/ghidra-mcp-artifacts \
    && find "${GHIDRA_MCP_HOME}" /root/.config/ghidra \
        \( -name 'GhidraMCP*.jar' -o -name 'GhidraMCP*.zip' \) \
        -type f -exec cp -f {} /opt/ghidra-mcp-artifacts/ \; 2>/dev/null \
    && chown -R spt:spt "${GHIDRA_MCP_HOME}" /opt/ghidra-mcp-artifacts

COPY images/ghidra-mcp/run-ghidra-mcp.sh /usr/local/bin/run-ghidra-mcp
RUN sed -i 's/\r$//' /usr/local/bin/run-ghidra-mcp \
    && chmod +x /usr/local/bin/run-ghidra-mcp

USER spt

ENV ARTIFACTS_DIR=/artifacts

CMD ["run-ghidra-mcp"]
