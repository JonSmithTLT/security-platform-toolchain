# images/result-normalizers/Dockerfile
# Converts raw tool outputs to the shared SPT tool-result schema.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT result normalizers image"

USER root

COPY images/result-normalizers/result-normalizers.py /usr/local/lib/spt/result-normalizers.py
COPY images/result-normalizers/run-result-normalizers.sh /usr/local/bin/run-result-normalizers
RUN sed -i 's/\r$//' \
        /usr/local/lib/spt/result-normalizers.py \
        /usr/local/bin/run-result-normalizers \
    && chmod +x /usr/local/bin/run-result-normalizers

USER spt

ENV NORMALIZER_INPUT=/artifacts/results \
    NORMALIZER_FORMAT=auto \
    NORMALIZER_OUTPUT="" \
    ARTIFACTS_DIR=/artifacts

CMD ["run-result-normalizers"]
