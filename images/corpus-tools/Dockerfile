# syntax=docker/dockerfile:1
# images/corpus-tools/Dockerfile
# Corpus management utilities for fuzzing (minimise, deduplicate, merge).

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT corpus management tools"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        afl++ \
        rsync

COPY images/corpus-tools/manage-corpus.sh /usr/local/bin/manage-corpus
RUN sed -i 's/\r$//' /usr/local/bin/manage-corpus \
    && chmod +x /usr/local/bin/manage-corpus

USER spt

ENV CORPUS_DIR=/workspace/corpus \
    CORPUS_OUT=/artifacts/corpus-out \
    CORPUS_MODE=minimise \
    CORPUS_TARGET="" \
    ARTIFACTS_DIR=/artifacts

CMD ["manage-corpus"]
