# images/sbom/Dockerfile
# Software Bill of Materials generator using Syft (CycloneDX / SPDX).

FROM ghcr.io/jonsmithtlt/spt-base:latest

LABEL org.opencontainers.image.description="SPT SBOM generator image"

USER root

ARG SYFT_VERSION=1.4.1
RUN curl -fsSL "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
        | sh -s -- -b /usr/local/bin "v${SYFT_VERSION}"

COPY images/sbom/run-sbom.sh /usr/local/bin/run-sbom
RUN chmod +x /usr/local/bin/run-sbom

USER spt

ENV TARGET_REPO=/workspace \
    SBOM_FORMAT=cyclonedx-json \
    ARTIFACTS_DIR=/artifacts

CMD ["run-sbom"]
