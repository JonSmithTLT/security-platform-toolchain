# Frontend Node Toolchain and Dependency Cache

This lane builds a Node 22 frontend dependency/toolchain image for the Phase 9
REVELATIONS operational UI. It is a transport artifact for air-gapped frontend
development and CI, not a mandate that every downstream image install every
package.

## Scope

The package set is defined in `requirements/frontend/package.json` and follows
the Phase 9 frontend stack:

- React, Vite, TypeScript, React Router
- OpenAPI-generated types and typed fetch
- React Query and Zod
- Tailwind, CVA, Radix primitives, lucide
- command palette, toasts, resizable panes, virtualized lists
- TanStack Table, React Flow, dagre, Recharts
- forms, markdown/JSON/code artifact viewers, CSV/YAML helpers
- Vitest, Testing Library, MSW, ESLint, Prettier
- optional Playwright package dependencies

The first blessed validation path is npm because it maps cleanly to common
Artifactory/internal npm registry setups. `pnpm` is included in the dependency
pack, but Phase 9 should choose one primary install path before CI is finalized.

## Build

```bash
make frontend-npm-fetch DATA_DIR=data-bundles/sources
make frontend-node-toolchain DATA_DIR=data-bundles/sources
make frontend-npm-smoke
make frontend-npm-verify DATA_DIR=data-bundles/sources
```

Generated data lands under:

```text
data-bundles/sources/frontend-npm/node22/
  npm-cache/
  package/package.json
  package/package-lock.json
  frontend-npm-manifest.json
  SHA256SUMS
```

Current candidate:

| Field | Value |
|---|---|
| Node | `v22.22.2` |
| Package manager | npm |
| Resolved packages | 735 |
| Cache/artifact size | about 547 MB |
| Lockfile SHA256 | `37071afb5bce8fb6d3fb44aae8544e5dd587b023cf9a800a3acb05be29be875b` |

Compatibility decision:

| Package | Decision |
|---|---|
| `eslint` / `@eslint/js` | Pin to `^9` so `eslint-plugin-jsx-a11y` remains compatible |

## Offline Use

```bash
docker run --rm --network none \
  -v "$PWD/frontend:/workspace" \
  "$REGISTRY/spt-frontend-node-toolchain:$TAG" \
  sh -lc 'cp /opt/spt-frontend/package/package-lock.json . && npm ci --offline --ignore-scripts'
```

## Air-Gap Notes

- Validation must use the internal npm registry/cache only.
- Do not allow public npm fallback in CI.
- Commit and enforce the lockfile in the real frontend app.
- Playwright package dependencies are included, but browser binaries require a
  separate offline cache/import strategy.
- Raw artifact HTML should never be rendered directly; markdown/code/JSON
  viewers must sanitize or escape untrusted content.

## Transfer

The image can be pushed to Docker Hub or saved as a tar for transfer:

```bash
docker save "$REGISTRY/spt-frontend-node-toolchain:$TAG" \
  -o "spt-frontend-node-toolchain-$TAG.tar"
sha256sum "spt-frontend-node-toolchain-$TAG.tar" \
  > "spt-frontend-node-toolchain-$TAG.tar.sha256"
```

Carry `frontend-npm-manifest.json`, `SHA256SUMS`, and the image digest with the
transfer evidence.
