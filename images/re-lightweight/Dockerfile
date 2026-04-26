# syntax=docker/dockerfile:1
# images/re-lightweight/Dockerfile
# Lightweight reverse-engineering triage tools.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT lightweight RE triage image"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        binutils \
        file \
        libimage-exiftool-perl \
        python3-magic \
        xxd

COPY images/re-lightweight/run-re-lightweight.sh /usr/local/bin/run-re-lightweight
RUN sed -i 's/\r$//' /usr/local/bin/run-re-lightweight \
    && chmod +x /usr/local/bin/run-re-lightweight

USER spt

ENV RE_TARGET=/workspace \
    RE_MAX_FILES=100 \
    ARTIFACTS_DIR=/artifacts

CMD ["run-re-lightweight"]
