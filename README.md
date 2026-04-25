# security-platform-toolchain

Repeatable Docker toolchain for offline security analysis. Build the images on a
connected machine, export them as a bundle, then load and run them in an
air-gapped network without internet access. The repo provides pinned images,
wrappers, schemas, rules, queries, and examples so external tools emit
consistent artifacts for Jenkins, MCP workflows, and platform ingestion.

---

## Repository layout

```
security-platform-toolchain/
├── Makefile                    # build-all, lint, test, bundle, push
├── docker-compose.yml          # all services wired together
│
├── common/                     # shared utilities (copied into every image)
│   ├── entrypoint.sh           # standard signal-safe entrypoint
│   ├── logging.sh              # structured log helpers (info/warn/error/debug)
│   ├── emit-job-report.py      # validates & writes job-report.json
│   └── artifact-layout.md      # on-disk artifact directory specification
│
├── schemas/                    # JSON Schema (draft-07)
│   ├── job-report.schema.json
│   ├── artifact-manifest.schema.json
│   └── tool-result.schema.json
│
├── images/                     # one sub-directory per tool image
│   ├── base/                   # Ubuntu 24.04 base layer + shared scripts
│   ├── schema-validator/       # validates emitted SPT JSON artifacts
│   ├── result-normalizers/     # converts raw tool output to tool-result JSON
│   ├── c-cpp-analysis/         # clang-tidy, cppcheck, sanitizers (ASan/UBSan/TSan), scan-build, Valgrind/Helgrind, compiler hardening, libFuzzer
│   ├── coverage-tools/         # gcovr/lcov coverage reports
│   ├── fuzzing/                # AFL++
│   ├── replay-runner/          # crash replay + Valgrind
│   ├── sbom/                   # Syft (CycloneDX / SPDX)
│   ├── osv-scanner/            # OSV dependency scanning
│   ├── secrets/                # Gitleaks + TruffleHog
│   ├── image-scanner/          # Grype image/filesystem scanning
│   ├── re-lightweight/         # lightweight RE triage
│   ├── yara/                   # YARA scanning
│   ├── intel-ingest/           # offline intel ingestion
│   ├── rag-indexer/            # derived RAG indexes
│   ├── diff-impact/            # diff impact analysis
│   ├── ghidra-base/            # shared Ghidra runtime
│   ├── ghidra-exporter/        # controlled Ghidra exports
│   ├── ghidra-mcp/             # analyst/MCP Ghidra workflows
│   ├── eval-runner/            # workflow/RAG evaluations
│   ├── gitnexus/               # GitNexus CLI/MCP code intelligence graph
│   ├── semgrep/                # Semgrep SAST
│   ├── codeql/                 # CodeQL CLI
│   ├── corpus-tools/           # AFL++ corpus minimise/merge/dedup
│   └── symbolic/               # angr / KLEE symbolic execution
│
├── rules/
│   └── semgrep/                # security.yml — starter Semgrep rules
│
├── queries/
│   └── codeql/                 # security-queries.ql + qlpack.yml
│
├── examples/
│   ├── jenkins/Jenkinsfile     # declarative pipeline
│   ├── cron/run-toolchain.sh   # nightly cron driver
│   ├── mcp/toolchain.mcp.json  # MCP tool-call manifest
│   └── docker-compose/         # standalone compose example
│
└── offline-bundles/
    └── README.md               # air-gap bundle create/restore instructions
```

---

## Quick start

### Build all images

> **Warning:** Do not use `latest` in Jenkins/platform jobs; pin tags or digests.

```bash
make build-all REGISTRY=registry.internal/security-platform TAG=0.1.0
```

### Run a single tool

```bash
docker run --rm \
  -e JOB_ID=dev-001 \
  -v $(pwd):/workspace:ro \
  -v $(pwd)/artifacts:/artifacts \
  registry.internal/security-platform/spt-semgrep:0.1.0
```

### Run the full stack with docker-compose

```bash
WORKSPACE=/path/to/project docker-compose up
```

### Create an offline bundle

```bash
make bundle TAG=1.2.3
# → offline-bundles/out/spt-bundle-1.2.3.tar
```

### Publish images to one registry namespace

If the Git repo is too large to carry image tarballs, push the separate images
to one registry namespace:

```bash
make push-registry \
  REGISTRY=registry.internal/security-platform \
  TARGET_REGISTRY=docker.io/<namespace> \
  TAG=1.2.3
```

Another connected machine can pull that namespace and recreate one offline
bundle:

```bash
make pull-bundle \
  SOURCE_REGISTRY=docker.io/<namespace> \
  TAG=1.2.3
```

### Load and verify an offline bundle

```bash
make load-bundle TAG=1.2.3
make verify-offline TAG=1.2.3
```

`verify-offline` starts each image with Docker networking disabled
(`--network none`) to catch accidental runtime internet dependencies.

### Run functional smoke tests

```bash
make functional-smoke REGISTRY=registry.internal/security-platform TAG=1.2.3
```

This creates a tiny local fixture under `artifacts/functional-smoke`, then runs
selected images with Docker networking disabled to prove real behavior:
Semgrep detection, result normalization, schema validation, SBOM generation,
Gitleaks execution, Grype execution, C/C++ analysis execution, coverage output,
YARA scanning, lightweight RE triage, intel ingestion, RAG indexing,
diff-impact output, and eval execution.

Smoke test levels:

| Target | Purpose |
|--------|---------|
| `make verify-offline` | Image-only startup check. Every image starts with Docker networking disabled. |
| `make functional-smoke` | Fixture-data check. Tiny local fixtures prove implemented tools work offline. |
| `make data-bundle-smoke` | Full-data discovery check. Mounted/staged data bundle contains expected OSV, YARA, Semgrep, CodeQL, and intel datasets. |

### Create an offline data bundle

Stage vulnerability intelligence and rule data under `data-bundles/sources/`,
then bundle it separately from the Docker images:

```bash
make data-fetch TAG=2026-04-25
make data-bundle TAG=2026-04-25
make data-verify TAG=2026-04-25
```

Use this for OSV databases, CWE, CAPEC, MITRE ATT&CK, CVE/NVD, CISA KEV,
EPSS, advisory databases, YARA rules, Semgrep rules, CodeQL packs, and vendor
advisories.

Normal users can import and run the image bundle without importing the data
bundle. The data bundle is optional, but required for full offline
vulnerability, advisory, rule, and intelligence coverage.

Full data bundles may trigger AV/DLP because upstream advisory and rule sources
can contain PoC strings, exploit commands, webshell snippets, suspicious
indicators, or scanner fixtures. See [`SECURITY_NOTES.md`](SECURITY_NOTES.md)
before distributing the data bundle.

Bundle variants:

| Variant | Description |
|---------|-------------|
| `intel-data-full-<TAG>.tar.zst` | Upstream advisory/intel content as-is. Maximum coverage; may trigger AV/DLP. |
| `intel-data-sanitized-<TAG>.tar.zst` | Excludes or redacts PoC/exploit-heavy records. Reduced coverage. |

Current release notes:

- Images are built and smoke-tested offline.
- Checksums are included for full tarballs and split parts.
- Image bundle is roughly 10 GB and split into GitHub Release asset chunks.
- Data bundle is separate because advisory/intel content may trigger AV/DLP.
- Known AV-sensitive source: GitHub Advisory Database entries can include
  PoC/webshell/RCE strings and may be flagged by Defender or similar tooling.

---

## Artifact layout

Every image writes its outputs to `$ARTIFACTS_DIR` following the structure
defined in [`common/artifact-layout.md`](common/artifact-layout.md).

---

## Schemas

All tool images emit JSON conforming to the schemas in [`schemas/`](schemas/):

| Schema | Purpose |
|--------|---------|
| `job-report.schema.json` | Top-level run report |
| `artifact-manifest.schema.json` | File manifest with checksums |
| `tool-result.schema.json` | Normalised findings |

---

## Planned image phases

The current platform spine is `base`, `schema-validator`, `result-normalizers`,
`semgrep`, and `gitnexus`. The newer images have first-pass implementations so
they can travel in the offline bundle and run useful offline workflows. They
should be deepened in this order:

1. `c-cpp-analysis`, `coverage-tools`, `fuzzing`, `replay-runner`
2. `sbom`, `osv-scanner`, `secrets`, `image-scanner`
3. `re-lightweight`, `yara`, `intel-ingest`, `rag-indexer`, `diff-impact`
4. `ghidra-base`, `ghidra-exporter`, `ghidra-mcp`, `eval-runner`, `codeql`, `symbolic`

`ghidra-exporter` should be the controlled batch producer for platform
ingestion. `ghidra-mcp` should be a separate reusable local RE environment for
analysts and agentic workflows.

---

## Contributing

1. Add a new image directory under `images/<name>/`.
2. Include a `Dockerfile` that accepts `ARG BASE_IMAGE` and inherits
   `FROM ${BASE_IMAGE}`.
3. Add a `run-<name>.sh` wrapper that sources `/usr/local/lib/spt/logging.sh`
   and calls `emit-job-report` at the end.
4. Ensure the wrapper can run with Docker `--network none`.
5. Update `Makefile`, `docker-compose.yml`, and add a `README.md` for the image.

---

## License

MIT — see [LICENSE](LICENSE).
