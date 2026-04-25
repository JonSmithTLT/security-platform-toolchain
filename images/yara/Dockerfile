# images/yara/Dockerfile
# Offline YARA scanning.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT YARA scanner image"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        yara \
    && rm -rf /var/lib/apt/lists/*

COPY images/yara/run-yara.sh /usr/local/bin/run-yara
RUN sed -i 's/\r$//' /usr/local/bin/run-yara \
    && chmod +x /usr/local/bin/run-yara

USER spt

ENV YARA_RULES=/rules \
    YARA_TARGET=/workspace \
    ARTIFACTS_DIR=/artifacts

CMD ["run-yara"]
