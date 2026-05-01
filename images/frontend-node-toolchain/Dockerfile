# images/frontend-node-toolchain/Dockerfile
# Node 22 frontend dependency/cache carrier for the Phase 9 REVELATIONS UI.
# This is both a toolchain image and a transport artifact for offline npm cache
# contents, package manifests, lockfile, checksums, and manifest metadata.

FROM node:22-bookworm-slim

LABEL org.opencontainers.image.description="SPT Node 22 frontend toolchain with Phase 9 npm dependency cache"

ENV SPT_FRONTEND_NPM_CACHE=/opt/spt-frontend/npm-cache \
    npm_config_cache=/opt/spt-frontend/npm-cache \
    npm_config_audit=false \
    npm_config_fund=false \
    npm_config_update_notifier=false

COPY data-bundles/sources/frontend-npm/node22/npm-cache/ /opt/spt-frontend/npm-cache/
COPY data-bundles/sources/frontend-npm/node22/package/ /opt/spt-frontend/package/
COPY data-bundles/sources/frontend-npm/node22/frontend-npm-manifest.json /opt/spt-frontend/frontend-npm-manifest.json
COPY data-bundles/sources/frontend-npm/node22/SHA256SUMS /opt/spt-frontend/SHA256SUMS

RUN corepack enable \
    && node --version \
    && npm --version \
    && npm cache verify --cache /opt/spt-frontend/npm-cache

WORKDIR /workspace

CMD ["node", "--version"]
