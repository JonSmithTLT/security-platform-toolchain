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
│   ├── c-cpp-analysis/         # clang-tidy, cppcheck, sanitizers (ASan/UBSan/TSan), scan-build, Valgrind/Helgrind, compiler hardening, libFuzzer
│   ├── fuzzing/                # AFL++
│   ├── gitnexus/               # GitNexus CLI/MCP code intelligence graph
│   ├── semgrep/                # Semgrep SAST
│   ├── codeql/                 # CodeQL CLI
│   ├── sbom/                   # Syft (CycloneDX / SPDX)
│   ├── secrets/                # Gitleaks + TruffleHog
│   ├── corpus-tools/           # AFL++ corpus minimise/merge/dedup
│   ├── replay-runner/          # crash replay + Valgrind
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

### Load and verify an offline bundle

```bash
make load-bundle TAG=1.2.3
make verify-offline TAG=1.2.3
```

`verify-offline` starts each image with Docker networking disabled
(`--network none`) to catch accidental runtime internet dependencies.

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
