# syntax=docker/dockerfile:1
# images/yara/Dockerfile
# Offline YARA scanning.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT YARA scanner image"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        yara

COPY images/yara/run-yara.sh /usr/local/bin/run-yara
RUN sed -i 's/\r$//' /usr/local/bin/run-yara \
    && chmod +x /usr/local/bin/run-yara

USER spt

ENV YARA_RULES=/rules \
    YARA_TARGET=/workspace \
    ARTIFACTS_DIR=/artifacts

CMD ["run-yara"]
