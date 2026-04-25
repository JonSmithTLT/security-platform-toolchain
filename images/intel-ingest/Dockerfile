# images/intel-ingest/Dockerfile
# Offline security intelligence ingestion.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT intelligence ingestion image"

USER root

COPY images/intel-ingest/intel-ingest.py /usr/local/lib/spt/intel-ingest.py
COPY images/intel-ingest/run-intel-ingest.sh /usr/local/bin/run-intel-ingest
RUN sed -i 's/\r$//' \
        /usr/local/lib/spt/intel-ingest.py \
        /usr/local/bin/run-intel-ingest \
    && chmod +x /usr/local/bin/run-intel-ingest

USER spt

ENV INTEL_INPUT=/intel \
    INTEL_DATASET=local \
    INTEL_VERSION=unknown \
    ARTIFACTS_DIR=/artifacts

CMD ["run-intel-ingest"]
