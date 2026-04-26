# images/harness-builder/Dockerfile
# Harness scaffold, build, validation, and smoke image.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT harness builder image"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        afl++ \
        bear \
        clang \
        clang-format \
        clang-tidy \
        clang-tools \
        cmake \
        gcc \
        g++ \
        git \
        libclang-rt-18-dev \
        make \
        ninja-build \
        pkg-config \
        python3-jinja2 \
        file \
    && rm -rf /var/lib/apt/lists/*

COPY images/harness-builder/templates/ /opt/spt/harness-templates/
COPY images/harness-builder/run-harness-builder.sh /usr/local/bin/run-harness-builder
COPY images/harness-builder/generate-harness.sh /usr/local/bin/generate-harness
COPY images/harness-builder/build-harness.sh /usr/local/bin/build-harness
COPY images/harness-builder/smoke-harness.sh /usr/local/bin/smoke-harness
COPY images/harness-builder/validate-harness.sh /usr/local/bin/validate-harness
COPY images/harness-builder/package-harness.sh /usr/local/bin/package-harness

RUN sed -i 's/\r$//' /usr/local/bin/run-harness-builder /usr/local/bin/generate-harness /usr/local/bin/build-harness /usr/local/bin/smoke-harness /usr/local/bin/validate-harness /usr/local/bin/package-harness \
    && chmod +x /usr/local/bin/run-harness-builder /usr/local/bin/generate-harness /usr/local/bin/build-harness /usr/local/bin/smoke-harness /usr/local/bin/validate-harness /usr/local/bin/package-harness \
    && chown -R spt:spt /opt/spt/harness-templates

USER spt

ENV HARNESS_ENGINE=libfuzzer \
    HARNESS_NAME=spt_harness \
    HARNESS_TEMPLATE_DIR=/opt/spt/harness-templates \
    HARNESS_WORK_DIR=/tmp/spt-harness/generated \
    HARNESS_BUILD_DIR=/tmp/spt-harness/build \
    HARNESS_SEED=/tmp/spt-harness/corpus/seed \
    ARTIFACTS_DIR=/artifacts

CMD ["run-harness-builder"]
