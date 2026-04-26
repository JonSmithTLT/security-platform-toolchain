# images/dependency-review/Dockerfile
# Offline dependency lockfile/SBOM review against CVE cross-reference index.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT dependency review image"

USER root

COPY images/dependency-review/run-dependency-review.sh /usr/local/bin/run-dependency-review
RUN sed -i 's/\r$//' /usr/local/bin/run-dependency-review \
    && chmod +x /usr/local/bin/run-dependency-review

USER spt

ENV TARGET_REPO=/workspace \
    DEPENDENCY_INPUT= \
    CVE_INDEX_DB=/data/spt-cve-index.sqlite \
    ARTIFACTS_DIR=/artifacts

CMD ["run-dependency-review"]