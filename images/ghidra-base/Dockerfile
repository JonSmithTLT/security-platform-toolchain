# syntax=docker/dockerfile:1
# images/ghidra-base/Dockerfile
# Shared Ghidra runtime base for exporter and analyst/MCP images.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT shared Ghidra base image"

USER root

ARG GHIDRA_VERSION=12.0.4
ARG GHIDRA_DATE=20260303
ARG GHIDRA_URL=https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip
LABEL org.opencontainers.image.version="${GHIDRA_VERSION}"
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-21-jre-headless \
    && curl -fsSL "${GHIDRA_URL}" -o /tmp/ghidra.zip \
    && unzip -q /tmp/ghidra.zip -d /opt \
    && rm /tmp/ghidra.zip \
    && ln -s "/opt/ghidra_${GHIDRA_VERSION}_PUBLIC" /opt/ghidra

USER spt

ENV GHIDRA_HOME=/opt/ghidra

CMD ["/opt/ghidra/support/analyzeHeadless"]
