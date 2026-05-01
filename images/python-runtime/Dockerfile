# syntax=docker/dockerfile:1
# images/python-runtime/Dockerfile
# Python 3.11 runtime base with core-python wheelhouse pre-installed.
# Downstream tool images that need Python utilities inherit from this instead
# of spt-base so they get requests, pyyaml, click, rich, jsonschema, etc.
# without each image reinstalling them independently.
#
# Requires spt-python-wheelhouse-py311 to be built first:
#   make python-wheelhouse-image && make python-runtime

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
ARG WHEELHOUSE_IMAGE=registry.internal/security-platform/spt-python-wheelhouse-py311:latest

FROM python:3.11-slim AS py311
FROM ${WHEELHOUSE_IMAGE} AS wheelhouse
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT Python 3.11 runtime base with core-python pre-installed"

USER root

COPY --from=py311 /usr/local/ /usr/local/
COPY --from=py311 /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /usr/local/lib/spt-python-libs/
COPY --from=py311 /usr/lib/x86_64-linux-gnu/libssl.so.3 /usr/local/lib/spt-python-libs/
COPY --from=wheelhouse /wheelhouse/py311/core-python/ /tmp/spt-wheels/
COPY --from=wheelhouse /requirements/py311/core-python.lock /tmp/spt-wheels/

RUN --mount=type=cache,target=/root/.cache/pip \
    printf '/usr/local/lib/spt-python-libs\n' > /etc/ld.so.conf.d/spt-python-libs.conf \
    && ldconfig \
    && python3 --version \
    && python3 -c "import ssl; print(ssl.OPENSSL_VERSION)" \
    && python3 -m pip install \
        --no-index \
        --find-links /tmp/spt-wheels/ \
        -r /tmp/spt-wheels/core-python.lock \
    && rm -rf /tmp/spt-wheels

USER spt
