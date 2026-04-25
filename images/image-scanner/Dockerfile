# images/image-scanner/Dockerfile
# Offline container image scanning with Grype.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT image scanner image"

USER root

ARG GRYPE_VERSION=0.92.0
ENV GRYPE_DB_CACHE_DIR=/opt/grype/db
RUN mkdir -p "${GRYPE_DB_CACHE_DIR}" \
    && curl -sSfL https://get.anchore.io/grype \
        | sh -s -- -b /usr/local/bin "v${GRYPE_VERSION}" \
    && GRYPE_DB_AUTO_UPDATE=true grype db update \
    && chmod -R a+rX /opt/grype

COPY images/image-scanner/run-image-scanner.sh /usr/local/bin/run-image-scanner
RUN sed -i 's/\r$//' /usr/local/bin/run-image-scanner \
    && chmod +x /usr/local/bin/run-image-scanner

USER spt

ENV IMAGE_SCAN_TARGET=/workspace \
    GRYPE_DB_AUTO_UPDATE=false \
    GRYPE_DB_CACHE_DIR=/opt/grype/db \
    ARTIFACTS_DIR=/artifacts

CMD ["run-image-scanner"]
