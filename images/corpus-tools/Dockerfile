# images/corpus-tools/Dockerfile
# Corpus management utilities for fuzzing (minimise, deduplicate, merge).

FROM registry.internal/security-platform/spt-base:latest

LABEL org.opencontainers.image.description="SPT corpus management tools"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        afl++ \
        rsync \
    && rm -rf /var/lib/apt/lists/*

COPY images/corpus-tools/manage-corpus.sh /usr/local/bin/manage-corpus
RUN chmod +x /usr/local/bin/manage-corpus

USER spt

ENV CORPUS_DIR=/workspace/corpus \
    CORPUS_OUT=/artifacts/corpus-out \
    CORPUS_MODE=minimise \
    CORPUS_TARGET="" \
    ARTIFACTS_DIR=/artifacts

CMD ["manage-corpus"]
