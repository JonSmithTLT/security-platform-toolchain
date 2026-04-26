# Release Notes: v0.1.2

`v0.1.2` focuses on release discipline, offline build efficiency, and Python
wheelhouse scaffolding. It keeps scanner expansion modest while making the
existing bundle workflow faster, more inspectable, and easier to resume.

## Highlights

- Added CPython 3.11 wheelhouse scaffolding and offline smoke coverage.
- Added `make doctor` preflight checks for host tools, Docker/BuildKit, disk
  space, writable output paths, and slow WSL-mounted worktrees.
- Added `make native-worktree` and `make native-release-smoke` so release builds
  can run from native WSL/Linux storage instead of `/mnt/c`.
- Made release builds parallel by default through `BUILD_JOBS=4`.
- Added release stage ledger records under `artifacts/release-ledger/<TAG>/`.
- Added resumable release checkpoints with
  `RESUME_FROM=data-bundle|split|verify|upload`.
- Made GitHub Advisory DB opt-in for normal data fetches; use
  `make data-fetch-full` for full advisory data.
- Added data manifest checksum modes:
  `DATA_MANIFEST_CHECKSUM_MODE=full|dataset|metadata-only`.
- Added build timing, image size, tool inventory, drift, and data freshness
  reporting targets.
- Added release evidence and policy-check targets for source-level release
  preparation.
- Expanded BuildKit cache mounts across apt, pip, npm, and Maven-heavy builds.

## Release Validation

Recommended connected-side flow:

```bash
export REGISTRY=registry.internal/security-platform
export TAG=0.1.2
export DATA_DIR=data-bundles/sources

make native-release-smoke REGISTRY=$REGISTRY TAG=$TAG DATA_DIR=$DATA_DIR
make release-evidence REGISTRY=$REGISTRY TAG=$TAG DATA_DIR=$DATA_DIR
make release-policy-check REGISTRY=$REGISTRY TAG=$TAG
make release-restore REGISTRY=$REGISTRY TAG=$TAG RUN_FUNCTIONAL=1
```

Use `INCLUDE_GITHUB_ADVISORY_DB=1 make data-fetch` or `make data-fetch-full`
when a full advisory dataset is required.

## Known Limitations

See `KNOWN_LIMITATIONS.md`. The major limitations remain: honggfuzz is
experimental, GitNexus uses a downstream offline LadybugDB patch, Ghidra MCP
does not yet run a full analyst-session smoke by default, and OSV matching
requires mounted offline databases.
