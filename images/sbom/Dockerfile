# images/sbom/Dockerfile
# Software Bill of Materials generator using Syft (CycloneDX / SPDX).

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT SBOM generator image"

USER root

ARG SYFT_VERSION=1.4.1
RUN curl -fsSL "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
        | sh -s -- -b /usr/local/bin "v${SYFT_VERSION}"

COPY images/sbom/run-sbom.sh /usr/local/bin/run-sbom
RUN sed -i 's/\r$//' /usr/local/bin/run-sbom \
    && chmod +x /usr/local/bin/run-sbom

USER spt

ENV TARGET_REPO=/workspace \
    SBOM_FORMAT=cyclonedx-json \
    ARTIFACTS_DIR=/artifacts \
    SYFT_CHECK_FOR_APP_UPDATE=false

CMD ["run-sbom"]
