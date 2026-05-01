# frontend-node-toolchain

Node 22 frontend toolchain and npm dependency-cache artifact for the Phase 9
REVELATIONS operational UI.

This image is intended for connected-side build/promotion and air-gap transfer.
It carries:

- Node 22 and npm
- Corepack enabled
- `requirements/frontend/package.json`
- generated `package-lock.json`
- npm cache contents for offline `npm ci`
- `frontend-npm-manifest.json`
- `SHA256SUMS`

## Build

```bash
make frontend-npm-fetch
make frontend-node-toolchain
make frontend-npm-smoke
make frontend-npm-verify
```

## Offline Install Pattern

```bash
docker run --rm --network none \
  -v "$PWD/frontend:/workspace" \
  "$REGISTRY/spt-frontend-node-toolchain:$TAG" \
  sh -lc 'cp /opt/spt-frontend/package/package-lock.json . && npm ci --offline --ignore-scripts'
```

## Notes

- npm is the first blessed validation path because it maps cleanly to common
  internal npm/Artifactory setups.
- `pnpm` is included in the dependency pack for future use, but the project
  should bless one install path before Phase 9 CI is finalized.
- Playwright package dependencies are included, but browser binaries still need
  a separate internal/offline cache strategy.
