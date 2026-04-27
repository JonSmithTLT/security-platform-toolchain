# Future Work

Working notes after the `0.1.1` offline bundle and restore validation, updated
after `0.1.2` wheelhouse and gitnexus offline work.

---

## Prioritized Backlog

Ordered by the adjusted priority from v0.1.2 feedback review. Do not add more
scanners before the release workflow is resumable, inspectable, and cheap to
rerun. The toolchain should produce reliable artifacts, normalized outputs,
candidate correlations, and release evidence. Canonical authority, durable
identity, and final deduplication belong in platform/importer contracts.

### Tier 1 — Release discipline and quick wins

- [x] **Release preflight doctor** — `make doctor` checks Docker/BuildKit,
  disk space, WSL path placement, required host tools, GitHub CLI auth,
  writable output dirs, and whether the repo is on a slow mounted filesystem
  before a long release run starts
- [x] **Release stage ledger** — each release step writes a small JSON record
  with command, inputs, start/end time, status, produced artifacts, checksums,
  and logsv; this becomes the durable state file for resumable releases
- [x] **Build timing report** — capture per-image build durations and final
  sizes in `artifacts/build-metrics/build-report.md`; prioritize the slowest
  images and catch build-time regressions
- [x] **Backlog/release-state reconciliation** — mark which backlog items are
  implemented, partial, or stale by comparing docs, Makefile targets, and
  generated artifacts; keeps Future Work from drifting after rapid iteration
- [x] **Host path safety guard** — warn or fail release targets when running
  from `/mnt/c`, OneDrive, or other known slow/sync-heavy paths unless
  `ALLOW_SLOW_WORKTREE=1` is set
- [x] **Python 3.11 wheelhouse** (`spt-python-wheelhouse-py311`) — scaffolding complete in v0.1.2
- [x] **`make help`** — self-documenting Makefile via inline `##` comments
- [x] **Explicit cleanup targets** — `make clean-bundles`, `clean-artifacts`, `clean-data-sources`, `clean-all-generated`
- [x] **Image size tracking** — `make image-sizes` emits a markdown table; catches silent bloat before release
- [x] **Move release builds off `/mnt/c`** — `make native-worktree` syncs a fast WSL/Linux build copy and `make doctor` blocks slow mounted paths by default
- [x] **Resumable release workflow** — `RESUME_FROM=data-bundle|split|verify|upload` skips earlier expensive stages while preserving stage-ledger evidence
- [x] **GitHub Advisory DB optional fetch** — default `make data-fetch` skips the expensive GitHub Advisory DB; use `INCLUDE_GITHUB_ADVISORY_DB=1 make data-fetch` or `make data-fetch-full` for full advisory data
- [x] **Data manifest checksum modes** — `DATA_MANIFEST_CHECKSUM_MODE=full|dataset|metadata-only`; default `dataset` avoids per-file hashing during normal release iteration
- [x] **Tool version inventory / drift report** — `make tool-versions-declared`, `make tool-versions-installed`, and `make tool-drift-check` capture declared pins, installed probes, and drift evidence
- [x] **Parallel builds** — `make -j N build-all`; explicit dep edges already mostly exist
- [x] **BuildKit cache mounts** — apt, pip, npm, and Maven-heavy Dockerfile steps use BuildKit cache mounts
- [x] **pigz / gzip bundle compression** — `docker save` and data bundle tars pipe through `pigz` (falls back to `gzip`); 50–65% smaller image bundle, 70–80% smaller data bundle; `docker load` handles gzip natively
- [x] **Data bundle freshness dashboard** — `make data-check-freshness` reads `metadata.json` timestamps and reports age vs. expected cadence
- [x] **Incremental NVD fetch** — `NVD_INCREMENTAL=1 make data-fetch` uses `lastModStartDate`/`lastModEndDate` from prior metadata when available and falls back to full feeds otherwise
- [x] **Auto core count for builds** — `BUILD_JOBS=$(shell nproc 2>/dev/null || echo 4)` with fallback
- [x] **Default `SKIP_HONGGFUZZ=1`** — skip by default; opt in with `SKIP_HONGGFUZZ=0`

### Tier 2 — High-value capabilities, after release discipline is solid

- [x] **Platform self-scanning release evidence** — `make release-evidence` collects SBOM per image, Grype scan per image, OSV scan, secret scan, image size table, tool inventory, checksums, artifact manifest, and a release evidence summary
- [x] **Image metadata contract** — require standard OCI labels for source
  repo/ref, tool versions, wheelhouse group, license hints, build timestamp,
  and SPT schema version; feeds inventory, release notes, and drift reports
- [x] **Release policy gates** — configurable checks for max image size,
  required smoke suites, required manifests, required signatures, and allowed
  license classes; emits a human-readable pass/fail release decision
- [x] **Golden fixture contract tests for normalizers** — per-tool raw input
  fixtures plus expected `tool-result.json`; prevents schema and mapping
  regressions as adapters evolve
- [x] **License inventory** — lightweight manifest answering: what did we import, what version, from where, under what license, is it runtime/build-time/data; matters in controlled environments
- [x] **Container structure tests** — `make container-structure-test` validates built image labels, entrypoints, non-root users, and expected env shape as pre-evidence release evidence
- [x] **SARIF adapter in result-normalizers** — aggregate `tool-result.json` now exports SARIF 2.1 as a projection format for SARIF-native consumers; SPT findings remain the internal authority model
- [x] **CVE cross-reference SQLite index** — `make cve-index` joins NVD + EPSS + CISA KEV + optional GitHub Advisory + OSV into a single offline SQLite enrichment/correlation database; not canonical findings
- [x] **Delta data bundles** — `make data-delta-bundle` compares current sources against prior source checksums and publishes added/modified files plus removed-path manifest metadata
- [x] **Sanitized data bundle mode** — `make data-bundle-sanitized` via `create-sanitized-data-view.py`
- [x] **Offline egress audit mode** — `make offline-egress-audit` via `offline-egress-audit.py`
- [x] **`spt-python-runtime` base** — `images/python-runtime/Dockerfile`; promoted into `IMAGES` for v0.1.2; multi-stage COPY from the py311 wheelhouse carrier with a CPython 3.11 runtime so lock files and interpreter ABI match

### Tier 2.5 — Platform handoff contracts

- [x] **Platform handoff bundle** — `make platform-handoff-bundle` via `build-platform-handoff-bundle.py`
- [x] **Generated MCP/tool catalog** — `make tool-catalog` via `generate-tool-catalog.py`

### Tier 3 — Strategic, build in correct order

- [x] **Content-addressed artifact cache** — cache downloaded datasets,
  wheelhouses, generated SBOMs, and image bundle parts by digest so rebuilds
  and release resumes can reuse verified artifacts instead of redoing work
  - [x] Image bundle tarballs, checksums, manifests, and split parts can
    now be stored/restored by bundle SHA-256 via `make image-bundle-cache-*`.
  - [x] Data bundle tarballs, checksums, manifests, source checksums, and split
    parts can now be stored/restored by bundle SHA-256 via
    `make data-bundle-cache-*`.
  - [x] Python 3.11 wheelhouse fetches restore from a cache keyed by the
    requirement input files in `fetch-python-wheels.sh`.
  - [x] CVE SQLite index artifacts can be checksummed and stored/restored by
    SHA-256 via `make cve-index-cache-*`.
  - [x] Generated release SBOM evidence can be stored/restored by SBOM tree
    digest via `make release-sboms-cache-*`.
  - [x] Dataset-level fetch cache for large upstream sources such as GitHub
    Advisory DB and OSV DB, keyed by source/ref configuration and verified
    checksums.
  - [x] Artifact cache maintenance commands: list entries, show size by type,
    prune old entries, and verify all cached checksums.
- [x] **`spt-dependency-review`** — full image in `images/dependency-review/`; in `IMAGES` list; uses CVE index
- [x] **EPSS/KEV enrichment** — enrich observations with CVSS score/vector, EPSS probability/percentile, KEV presence, advisory aliases, fix version; part of the intelligence index path, not a separate subsystem
- [x] **Candidate finding correlation adapter** — `make candidate-correlations` via `generate-candidate-correlations.py`; emits `candidate-correlations.json` alongside tool artifacts
- [x] **Thin YAML pipeline runner (`spt-pipeline`)** — chains containers and passes artifact directories; no scheduler, no mini-Airflow; good scope is `steps[]: image, command, inputs, outputs, env, depends_on, expected_artifacts, schema_validation`
- [x] **Release upload helper** — upload manifest and `gh release upload --clobber` helper exist; remaining work is create/update release flow from manifests
- [x] **Data bundle signing** — GPG or sigstore over the bundle manifest
- [x] **Compact release summary generator** — inputs: manifests, checksums, smoke logs; output: markdown release evidence block
- [x] **`--cache-from` registry cache** — push built images with `--cache-to type=registry` after release so subsequent builds only rebuild changed layers; mainly useful for CI/CD or multi-machine builds; local BuildKit cache handles the single-machine case already; requires verifying registry supports OCI cache manifests
- [x] **Trivy image evaluation** — deferred for now; current release evidence already covers SBOM, image vulnerability scanning, secrets, Semgrep rules, and container structure checks. Add Trivy later only with a concrete IaC/misconfiguration lane and offline DB/cache plan.

### Tier 4 — Future, after platform stabilizes

Tier 4 is now ordered by post-Tier-3 leverage: first make the new runner and
release evidence easier to use, then expose stable read-only APIs, then improve
maintenance/provenance. Avoid new scanners or heavyweight runtime lanes unless
there is a concrete workflow that needs them.

#### Tier 4A — Near-term polish on existing contracts

- [x] **Offline analyst playbooks** — curated `spt-pipeline` YAML workflows for
  dependency triage, release evidence review, fuzz crash replay,
  reverse-engineering export, and protocol fuzzing; no platform authority or
  canonical finding writes
- [x] **Interactive local TUI for release operations** — thin terminal UI over
  the release stage ledger for viewing step status, logs, artifacts, and safe
  resume points without opening multiple files
- [x] **`spt-cve-api` / API gateway** — FastAPI service exposing the CVE index
  read-only; build from the existing index and enrichment model, do not invent
  a second intelligence model
- [x] **Renovate/Dependabot config** — automated pin-staleness notifications
  for Dockerfile ARGs, Git refs, Python requirement inputs, and GitHub Actions
  examples without auto-merging release-sensitive updates

#### Tier 4B — Release provenance and build determinism

- [x] **Reproducible builds** — source date normalization, timestamp
  stabilization, deterministic archive ordering, and explicit build metadata
  policy
- [x] **SLSA / sigstore / cosign** — after release pipeline is boring; extend
  beyond current data-manifest signing into image signatures and build
  attestations
- [ ] **Python 3.12 wheelhouse** — after py311 baseline is proven stable; useful
  for Ubuntu 24.04/system Python compatibility, not a replacement for py311
- [ ] **Multi-architecture support** — linux/arm64; not while x86_64 toolchain
  and release restore flow are still the primary stabilization target

#### Tier 4C — New capability lanes, only with concrete demand

- [ ] **Nuclei image** — only if web/API scanning becomes a real near-term lane;
  requires offline template bundle, update cadence, and evidence contract
- [ ] **Offline LLM sidecar planning** — define the data-bundle pattern for
  model weights now; `spt-llm` image itself remains separate because licensing,
  hardware sizing, and update cadence differ from normal security data bundles

---

## Release And Bundle Workflow

- Add a release upload helper that can create or update the GitHub release and upload all split assets from manifests.
- Completed release workflow quick wins are tracked in Tier 1 only: advisory DB optional fetch, data manifest checksum modes, resumable release workflow, native WSL builds, cleanup targets, `make help`, image size tracking, parallel builds, and tool version inventory.

## Data Bundle

- Add a sanitized data bundle mode.
  - Exclude or redact advisory PoC text, exploit commands, webshell snippets, and other AV/DLP-sensitive content.
  - Preserve reduced metadata useful for indexing and triage.
- Split data bundle variants.
  - Core: OSV, NVD, CISA KEV, CWE, CAPEC, ATT&CK, EPSS, YARA, Semgrep, CodeQL packs, Ladybug extensions.
  - Full: core plus GitHub Advisory DB and vendor advisories.
  - Sanitized: core plus redacted advisory/intel datasets.
- Record source versions and commits more completely.
  - Git repos: commit SHA and branch/ref.
  - Downloaded feeds: URL, fetch timestamp, checksum, and source-provided version when available.
- Add full-data OSV smoke.
  - Mount the data bundle OSV DB.
  - Scan a known vulnerable fixture.
  - Assert at least one expected vulnerability match.
- Add bundle-level signing.
  - GPG or sigstore signature over the overall bundle manifest for supply chain trust.
- Completed data-source quick wins are tracked in Tier 1 only: incremental NVD fetch and `make data-check-freshness`.

## CVE Intelligence & Enrichment

- Build a CVE cross-reference index.
  - Join NVD (CVSS), EPSS (probability), CISA KEV (exploited), GitHub Advisory DB, and OSV into a single offline SQLite database.
  - Supports queries: package+version → known CVEs; CVE → CVSS/EPSS/KEV/aliases/affected packages; finding with package/CVE/CWE hints → enrichment candidates.
  - Produces intelligence observations and enrichment candidates. Does not create canonical findings or authoritative vulnerability identity — that belongs in platform/importer contracts.
  - Expose via `spt-cve-index` fetch script and a thin Python query library.
- Add EPSS/KEV enrichment pipeline.
  - Any finding with a CVE ID can be auto-annotated with EPSS score, KEV status, CVSS base score, and first known exploitation date.
  - Feeds directly into finding deduplication and prioritization.
- Add SARIF adapter in result-normalizers.
  - Convert `tool-result.json` → SARIF 2.1.
  - Enables GitHub Advanced Security upload, VS Code problem matcher, and Azure DevOps import.
  - One adapter makes every tool's output portable with no per-tool changes.

## Analysis Pipeline & Orchestration

- Add candidate finding correlation adapter.
  - Sibling artifact alongside `findings.json` under each tool's `normalized/` directory.
    `tool-result.json` may reference it in an outputs list but it is its own schema-validated file.
  - Artifact placement example:
    `artifacts/results/semgrep/normalized/findings.json`
    `artifacts/results/semgrep/normalized/candidate-correlations.json`
  - Fingerprint signal types: `rule_id + normalized_file + line_range`, stack hashes, crash signature hashes, package/CVE/CWE overlap, source location overlap.
  - Schema uses soft fields only — no `canonical_finding_uid`, no `deduped_into`, no authority claims:
    - `candidate_relationship_type`: `possibly_related` | `same_rule_same_location` | `same_stack_signature` | `shared_cwe_pattern` | `same_dependency_cve`
    - `confidence`: 0.0–1.0
    - `signals`: list of contributing signals with type and weight
    - `source_observation_refs`: references to source observations
    - `target_observation_refs`: references to target observations
    - `recommended_action`: `review` | `attach_as_context` | `ignore_low_confidence`
  - Platform importer converts this into platform recommendations, entity correlation candidates, or nothing. Toolchain never mutates canonical finding identity.
- Add thin pipeline orchestration (`spt-pipeline`).
  - YAML-driven step runner that chains tool containers and passes artifact directories between steps.
  - No external workflow engine required; just `docker run` sequences with artifact handoff.
  - FastAPI wheelhouse group is the natural runtime for the orchestrator.
- Add `spt-dependency-review` image.
  - Accepts repo lockfiles (requirements.txt, package-lock.json, go.sum, Cargo.lock, pom.xml).
  - Scores them against the CVE cross-reference index offline.
  - Distinct from image scanning; covers source-level dependency risk.
- Add `spt-cve-api` / API gateway (future).
  - FastAPI service exposing CVE cross-reference index and normalized findings over HTTP.
  - Enables IDE and MCP tool integration without requiring direct file access.

## Tool Version Inventory & License Manifest

- Completed tool-version inventory and drift targets are tracked in Tier 1 only.
- Add a license inventory manifest.
  - Lightweight record per imported tool, Python wheel, and bundled dataset.
  - Fields: name, version, source URL, SPDX license identifier, runtime/build-time/data classification.
  - Does not need to be exhaustive initially; repo should be able to answer "what did we import and under what terms."
  - Matters in controlled/regulated deployment environments.

## Build Efficiency

- Added `spt-python-runtime` intermediate base image.
  - Python 3.11 base built from `spt-base` with `core-python` wheelhouse pre-installed.
  - Promoted for v0.1.2 after the Python 3.11 wheelhouse artifact, lock groups, and smoke tests passed release validation.
  - Tool images that need Python inherit from it rather than rebuilding from scratch.
  - Reduces build time and total image layer duplication.
- Completed build-efficiency quick wins are tracked in Tier 1 only: parallel builds, auto-detected build job count, BuildKit cache mounts, `make help`, image size tracking, pigz compression, and gzip bundle output.
- Default `SKIP_HONGGFUZZ=1` in release smoke — honggfuzz is always non-gating, always prints confusing warnings, and never contributes release evidence; skip it by default and require opt-in with `SKIP_HONGGFUZZ=0`.
- `--cache-from` registry cache — after a successful release, push images with `--cache-to type=registry` so subsequent builds pull the previous layer cache and only rebuild changed layers; large saving when only wrapper scripts changed.

## Platform Self-Security

- Add container structure tests.
  - Validate image structure (expected files present, correct permissions, correct user, env vars set).
  - Catches structural regressions before functional smoke runs.
- Add image signing (future).
  - cosign / sigstore signing of all built images for full supply chain provenance.
  - SLSA level 2 attestations for the build process.
- Platform self-scanning release evidence is tracked in Tier 2 only.

## Missing Tools

- **Trivy** — evaluated for v0.1.2 Tier 3 and deferred. Add later only if IaC/container misconfiguration coverage becomes a real lane and the offline Trivy DB/cache/update pattern is specified.
- **`spt-dependency-review`** — described above under Analysis Pipeline.
- **Nuclei** — web/API vulnerability scanner; offline template bundle follows existing fetch pattern. Useful for API and web app security research workflows.
- **Container structure test** (Google) — owned by Tier 2 Platform Self-Security; listed here only as a candidate implementation.
- **Bandit** — Python-specific security linting; may be redundant given semgrep coverage but worth evaluating.

## Python Wheelhouse

- Add Python 3.12 wheelhouse variant (`spt-python-wheelhouse-py312`).
  - Ubuntu 24.04 system Python; complement to the existing py311 wheelhouse.
  - py311 remains the explicit dependency contract; py312 is convenience for scripts targeting system Python.
- Add internal PyPI seeding automation.
  - `make python-wheelhouse-seed-pypi` — extracts wheels from image and runs `twine upload` against configured internal PyPI.
  - Parameterize: `INTERNAL_PYPI_URL`, `INTERNAL_PYPI_USER`, `INTERNAL_PYPI_PASS`.
- Add incremental wheel update workflow.
  - Re-run only groups where `.in` file has changed since last lock compilation.
  - Avoids full re-download of all groups on minor version bumps.
- Track which tool images use which wheelhouse groups.
  - Document in a matrix; prevents silent breakage when a group is updated.

## Offline LLM (Future)

- Plan data-bundle pattern for model weights.
  - Even if `spt-llm` is months away, the fetch script structure and bundle split decisions should be made before model weights are needed.
  - Target: small quantized model (3–7B, 4–8 GB), CPU-only inference via llama.cpp or ollama.
- `spt-llm` image.
  - llama.cpp or ollama base, no model weights baked in.
  - Model weights mounted from data bundle at runtime.
  - `ml-runtime-light` wheelhouse group (onnxruntime) is a stepping stone.
- LLM-assisted findings triage.
  - Feed deduplicated, EPSS-enriched findings to an offline LLM for natural language severity summary and remediation suggestion.
  - Keep LLM output clearly marked as AI-generated; never replace human review.

## Ghidra

- Add end-to-end `ghidra-mcp` analyst workflow smoke.
  - Start MCP runtime.
  - Connect a test MCP client.
  - Open a tiny fixture project or binary.
  - Request function list, symbols, comments, and/or decompiler output.
  - Assert expected fixture output.
- Add `ghidra-exporter` smoke for all export modes.
  - `GHIDRA_EXPORT_MODE=headless-basic`
  - `GHIDRA_EXPORT_MODE=direct-script`
  - `GHIDRA_EXPORT_MODE=mcp-scripted`
- Validate existing Ghidra server/project workflows.
  - Record provenance difference between fresh local binary analysis and analyst-enriched server/project state.

## Fuzzing And Triage

- Promote honggfuzz from experimental when it meets the same bar as AFL++ and libFuzzer.
  - Real toy smoke.
  - Artifact collection.
  - Crash collection.
  - Normalized `fuzz-campaign.json` and `crashes.json`.
  - Replay command metadata.
  - Documentation.
- Expand harness-builder templates.
  - `afl-c`
  - `libfuzzer-c`
  - `honggfuzz-c`
  - `parser-file`
  - `packet-replay`
  - `boofuzz-protocol`
  - `unit-derived`
- Add crash-triage fixture coverage.
  - ASAN, UBSAN, TSAN, MSAN, Valgrind, signal/core dump examples.
  - Verify stack hash and dedup behavior.
- Add corpus-tools functional fixtures with before/after corpus assertions.

## GitNexus

- Keep the LadybugDB offline extension smoke in the main functional gate.
  - Real git repo target.
  - Git metadata path exercised.
  - Ladybug extensions staged and loaded offline.
  - Index artifact exists.
  - No `extension.ladybugdb.com` fetch attempted.
- Track upstream GitNexus changes that could break the build-time offline Ladybug patch.
  - Patch should fail loudly if upstream code layout changes.
  - Record GitNexus package version/source ref in job reports.

## Platform Quality

- Add schema coverage for all normalized outputs generated by newer images.
- Add CI jobs that separate:
  - image-only smoke
  - fixture functional smoke
  - full-data smoke
  - slow/optional Ghidra smoke
- Add a compact release summary generator.
  - Inputs: manifests, checksums, smoke logs.
  - Output: markdown release evidence block.
- Completed version inventory, `make help`, and image size tracking are owned by Tier 1.
- Container structure tests are owned by Tier 2.
- Add Renovate/Dependabot config for automated pin-staleness notifications.
