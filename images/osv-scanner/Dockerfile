# images/osv-scanner/Dockerfile
# Offline-capable OSV dependency vulnerability scanning.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT OSV scanner image"

USER root

ARG OSV_SCANNER_VERSION=2.3.0
RUN curl -fsSL \
        "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/osv-scanner_linux_amd64" \
        -o /usr/local/bin/osv-scanner \
    && chmod +x /usr/local/bin/osv-scanner

COPY images/osv-scanner/run-osv-scanner.sh /usr/local/bin/run-osv-scanner
RUN sed -i 's/\r$//' /usr/local/bin/run-osv-scanner \
    && chmod +x /usr/local/bin/run-osv-scanner

USER spt

ENV TARGET_REPO=/workspace \
    OSV_OFFLINE=1 \
    OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=/osv-db \
    ARTIFACTS_DIR=/artifacts

CMD ["run-osv-scanner"]
