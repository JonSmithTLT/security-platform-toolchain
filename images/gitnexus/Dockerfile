# images/gitnexus/Dockerfile
# GitNexus CLI/MCP code intelligence image.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
ARG NODE_IMAGE=node:22-bookworm-slim
ARG GITNEXUS_VERSION=1.6.3
ARG GITNEXUS_SOURCE_COMMIT=unknown

FROM ${NODE_IMAGE} AS gitnexus-builder

ARG GITNEXUS_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        python3 \
    && npm install -g "gitnexus@${GITNEXUS_VERSION}" \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT GitNexus code intelligence image"

ARG GITNEXUS_VERSION
ARG GITNEXUS_SOURCE_COMMIT

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gitnexus-builder /usr/local/bin/node /usr/local/bin/node
COPY --from=gitnexus-builder /usr/local/bin/gitnexus /usr/local/bin/gitnexus
COPY --from=gitnexus-builder /usr/local/lib/node_modules/gitnexus /usr/local/lib/node_modules/gitnexus

COPY images/gitnexus/scripts/patch-gitnexus-offline-ladybug.sh /tmp/patch-gitnexus-offline-ladybug.sh
RUN chmod +x /tmp/patch-gitnexus-offline-ladybug.sh \
    && /tmp/patch-gitnexus-offline-ladybug.sh \
    && rm /tmp/patch-gitnexus-offline-ladybug.sh \
    && rm -f /usr/local/lib/node_modules/gitnexus/dist/core/lbug/lbug-adapter.js.orig

COPY images/gitnexus/gitnexus.sh /usr/local/bin/run-gitnexus
RUN ln -sf ../lib/node_modules/gitnexus/dist/cli/index.js /usr/local/bin/gitnexus \
    && sed -i 's/\r$//' /usr/local/bin/run-gitnexus \
    && chmod +x /usr/local/bin/run-gitnexus

USER spt

ENV GITNEXUS_MODE=version \
    GITNEXUS_TARGET=/workspace \
    GITNEXUS_ANALYZE_ARGS="" \
    HOME=/tmp/spt-home \
    GITNEXUS_SOURCE_REPO="https://github.com/abhigyanpatwari/GitNexus" \
    GITNEXUS_SOURCE_REF="${GITNEXUS_VERSION}" \
    GITNEXUS_SOURCE_COMMIT="${GITNEXUS_SOURCE_COMMIT}" \
    GITNEXUS_PACKAGE_NAME=gitnexus \
    GITNEXUS_PACKAGE_PATH=/usr/local/lib/node_modules/gitnexus \
    GITNEXUS_LADYBUG_EXTENSIONS_DIR=/data/ladybug-extensions \
    GITNEXUS_OFFLINE="" \
    SPT_OFFLINE="" \
    ARTIFACTS_DIR=/artifacts

CMD ["run-gitnexus"]
