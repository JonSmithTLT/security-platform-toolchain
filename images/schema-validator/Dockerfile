# images/schema-validator/Dockerfile
# Validates SPT artifact JSON files against the shared schemas.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT schema validator image"

USER root

COPY images/schema-validator/schema-validator.py /usr/local/lib/spt/schema-validator.py
COPY images/schema-validator/run-schema-validator.sh /usr/local/bin/run-schema-validator
RUN sed -i 's/\r$//' \
        /usr/local/lib/spt/schema-validator.py \
        /usr/local/bin/run-schema-validator \
    && chmod +x /usr/local/bin/run-schema-validator

USER spt

ENV VALIDATE_TARGET=/artifacts \
    SCHEMAS_DIR=/usr/local/share/spt/schemas \
    ARTIFACTS_DIR=/artifacts

CMD ["run-schema-validator"]
