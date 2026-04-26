# Release Notes: v0.1.1

`v0.1.1` is a smoke-tested offline security platform bundle. It expands
the image set, strengthens functional smoke coverage, and adds offline data
support for GitNexus/LadybugDB, OSV, rules, and advisory datasets.

## Highlights

- Added `harness-builder`, `protocol-fuzzing`, and `crash-triage` images.
- Promoted AFL++ and libFuzzer to first-class functional smoke coverage.
- Installed honggfuzz in the fuzzing image while keeping it experimental.
- Added boofuzz protocol/session fuzzing with a deterministic toy failure case.
- Added ASAN crash-triage parsing and normalized crash evidence.
- Reworked GitNexus from a generic Git/Nexus helper into the real
  `abhigyanpatwari/GitNexus` CLI/MCP image.
- Added a downstream GitNexus LadybugDB patch for local-first offline
  `fts`/`vector` extension loading.
- Added LadybugDB extension fetch and data-bundle smoke coverage.
- Expanded schema validation for harness, fuzzing, protocol, crash, replay,
  and corpus artifacts.
- Hardened artifact copying for Windows/WSL bind mounts.

## Functional Smoke Coverage

The main `make functional-smoke` gate now validates:

- Semgrep fixture findings.
- Result normalization.
- Schema validation.
- SBOM generation.
- Gitleaks fixture secret detection.
- Grype image/filesystem scanner startup without network update attempts.
- C/C++ analysis output.
- AFL and libFuzzer harness generation/build/smoke.
- AFL++ campaign execution.
- libFuzzer campaign execution and crash artifact collection.
- boofuzz protocol failing-case capture.
- ASAN crash triage.
- Coverage artifact generation.
- YARA fixture match.
- Lightweight RE inventory.
- Intel ingest and RAG index creation.
- Diff-impact output.
- GitNexus real git repo indexing with offline Ladybug extension loading.
- Eval runner file-content evaluation.
- Ghidra MCP environment smoke.

## Data Bundle Contents

The data bundle can include:

- OSV offline vulnerability databases.
- GitHub Advisory Database.
- NVD/CVE feeds.
- CISA KEV.
- CWE and CAPEC.
- MITRE ATT&CK STIX.
- EPSS.
- YARA Forge rules.
- Semgrep rules.
- CodeQL packs.
- LadybugDB `fts` and `vector` extensions.
- Organization-provided vendor advisories.

Full data bundles may trigger AV/DLP because public advisory and rule datasets
can include PoC strings, exploit commands, suspicious indicators, webshell
snippets, and scanner fixtures.

## Known Limitations

See `KNOWN_LIMITATIONS.md` for current limitations. The short version:

- honggfuzz is installed but not release-gating.
- Some apt package versions are inherited from Ubuntu at build time.
- GitNexus uses a downstream patch for offline Ladybug extension loading.
- Ghidra MCP smoke validates runtime availability, not an end-to-end analyst
  session.
- OSV matching requires a mounted offline OSV database.

## Release Validation

Before publishing, run:

```bash
export REGISTRY=registry.internal/revelations-security-platform
export TAG=0.1.1
export DATA_DIR=data-bundles/sources

make build-all REGISTRY=$REGISTRY TAG=$TAG
make verify-offline REGISTRY=$REGISTRY TAG=$TAG
make data-bundle-smoke TAG=$TAG DATA_DIR=$DATA_DIR
make functional-smoke REGISTRY=$REGISTRY TAG=$TAG DATA_DIR=$DATA_DIR
make smoke-honggfuzz REGISTRY=$REGISTRY TAG=$TAG || true
```

Then export and verify image/data bundles:

```bash
make bundle REGISTRY=$REGISTRY TAG=$TAG
make verify-bundle TAG=$TAG
make data-bundle TAG=$TAG DATA_DIR=$DATA_DIR
make data-verify TAG=$TAG
```
