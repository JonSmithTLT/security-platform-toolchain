# images/rag-indexer/Dockerfile
# Derived RAG/search index generation.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT RAG indexer image"

USER root

COPY images/rag-indexer/rag-indexer.py /usr/local/lib/spt/rag-indexer.py
COPY images/rag-indexer/run-rag-indexer.sh /usr/local/bin/run-rag-indexer
RUN sed -i 's/\r$//' \
        /usr/local/lib/spt/rag-indexer.py \
        /usr/local/bin/run-rag-indexer \
    && chmod +x /usr/local/bin/run-rag-indexer

USER spt

ENV RAG_INPUT=/artifacts/results/intel-ingest/raw/chunks.jsonl \
    ARTIFACTS_DIR=/artifacts

CMD ["run-rag-indexer"]
