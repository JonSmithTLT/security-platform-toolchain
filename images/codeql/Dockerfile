# images/codeql/Dockerfile
# CodeQL CLI wrapper for database creation and query execution.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT CodeQL analysis image"

USER root

ARG CODEQL_VERSION=2.18.4
ARG CODEQL_BUNDLE_URL=https://github.com/github/codeql-action/releases/download/codeql-bundle-v${CODEQL_VERSION}/codeql-bundle-linux64.tar.gz

RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless \
        build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "${CODEQL_BUNDLE_URL}" | tar -xz -C /opt \
    && ln -s /opt/codeql/codeql /usr/local/bin/codeql

COPY images/codeql/run-codeql.sh /usr/local/bin/run-codeql
RUN sed -i 's/\r$//' /usr/local/bin/run-codeql \
    && chmod +x /usr/local/bin/run-codeql

USER spt

ENV TARGET_REPO=/workspace \
    CODEQL_LANGUAGE=cpp \
    CODEQL_QUERIES=/queries \
    CODEQL_DB=/tmp/codeql-db \
    ARTIFACTS_DIR=/artifacts

CMD ["run-codeql"]
