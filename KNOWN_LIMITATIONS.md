# Known Limitations

This file records limitations for `v0.1.1-smoke`. These are not blockers for
the smoke release, but they should be understood before treating the bundle as a
polished release candidate.

## Version Pinning

- Several tools installed through Ubuntu packages are pinned only by the Ubuntu
  base image and package repository state at build time.
- `HONGGFUZZ_REF` defaults to `master`; a release candidate should pin it to a
  commit SHA or release tag.
- `GITNEXUS_SOURCE_COMMIT` defaults to `unknown` unless passed at build time.
- Some data sources are time-sensitive and should be represented in generated
  bundle manifests and checksums.

## GitNexus LadybugDB Patch

- `spt-gitnexus` applies a downstream patch to GitNexus
  `dist/core/lbug/lbug-adapter.js`.
- The patch enables path-based offline `LOAD EXTENSION` behavior for LadybugDB
  `fts` and `vector` extensions and avoids online `INSTALL` fallback when
  `GITNEXUS_OFFLINE=1` or `SPT_OFFLINE=1`.
- The Docker build fails if the expected upstream patch targets are not found.
- This should eventually become an upstream GitNexus feature, configuration
  option, or documented patch with a source commit checksum.

## honggfuzz

- honggfuzz is installed in the fuzzing image and `FUZZ_ENGINE=honggfuzz` is
  accepted.
- It is still experimental and non-gating in `v0.1.1-smoke`.
- AFL++ and libFuzzer are the first-class fuzzing engines for this release.
- Promotion to first-class should require real campaign execution, crash
  collection, replay metadata, normalized output parity, and release-gating
  smoke coverage.

## Ghidra

- `ghidra-exporter` supports mode-based wrappers for headless and MCP-scripted
  workflows, but slow/full binary analysis is not part of the default functional
  smoke.
- `ghidra-mcp` smoke validates runtime and installed MCP metadata. It does not
  validate a full analyst session against a production Ghidra server.
- Ghidra version changes require rebuilding/tagging the affected Ghidra images.

## OSV Offline Matching

- The OSV Scanner image contains the scanner binary.
- True offline vulnerability matching requires the OSV offline database mounted
  at runtime.
- Some richer dependency-resolution behavior may be unavailable in OSV offline
  mode depending on ecosystem and scanner support.

## Data Bundle Sensitivity

- Full data bundles may trigger AV, EDR, DLP, mail gateway, or repository
  scanning tools.
- Public advisory and rule datasets can contain PoC strings, exploit commands,
  suspicious indicators, RCE snippets, webshell examples, or scanner fixtures.
- The bundle is not intended to contain live malware samples, real credentials,
  proprietary target data, or private incident data.

## CI Scope

- The current strongest validation is local Docker smoke testing.
- A polished release candidate should add automated CI for schemas, shell
  syntax, Makefile targets, documentation links, and generated manifest checks.
- Full Docker image build and functional smoke may be too heavy for hosted CI,
  but should be run on a controlled connected build host before release.

## Restore Validation

- Publishing is not complete until release assets are reassembled, checksummed,
  loaded with `docker load`, and verified with `make verify-offline`.
- A stronger release candidate should run at least one functional smoke from
  the reloaded image bundle.
