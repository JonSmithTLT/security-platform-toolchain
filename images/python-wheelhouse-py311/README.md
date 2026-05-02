# python-wheelhouse-py311

Frozen CPython 3.11 Linux x86_64 wheelhouse artifact for the offline security
platform toolchain.

This is a **dependency artifact image**, not a runtime base image. It carries
pre-built wheels, pinned lock files, SHA256SUMS, and a manifest. Tool images
copy only the wheel groups they need.

## Groups

| Group | Purpose | Optional |
|---|---|---|
| `core-python` | Runtime utilities, HTTP, CLI, config | No |
| `api-future-fastapi` | FastAPI service layer (future migration) | No |
| `normalizers-reporting` | Output normalization, SARIF, CycloneDX, SPDX | No |
| `testing-dev` | pytest, ruff, mypy, hypothesis | No |
| `data-ingest-light` | SQLAlchemy, Alembic, SQLite, NetworkX | No |
| `rag-light` | BM25, tiktoken, NetworkX | No |
| `security-research-python` | cryptography, pyelftools, pefile, capstone, yara | No |
| `data-science-optional` | numpy, scipy, scikit-learn, pandas, pyarrow | Yes |
| `api-service-standard` | Uvicorn standard runtime extras for service images | Yes |
| `dependency-audit` | pip audit, SBOM, license, environment evidence helpers | Yes |
| `failure-log-analysis` | Logs, traceback, diff, fuzzy match, JSONPath parsing | Yes |
| `fuzzing-optional` | Hypothesis-adjacent fuzz/property test helpers | Yes |
| `large-artifact-compression` | DuckDB, Polars, compression, binary encodings | Yes |
| `llm-client-optional` | OpenAI/Anthropic SDK adapters for org LLM proxy clients | Yes |
| `ml-runtime-light` | onnxruntime (CPU); experimental until host runtime probes pass | Yes |
| `network-os-evidence` | OS/network evidence, ZeroMQ, LDAP, MQTT, packet helpers | Yes |
| `networking-protocol` | HTTP, async, DNS, SSH/serial, packet/protocol helpers | Yes |
| `profiling-debugging` | Profiling, memory, object graph, runtime debug helpers | Yes |
| `security-parsers` | File format, document, binary, XML/JSON parser helpers | Yes |
| `system-automation` | Subprocess, shell, host, Docker CLI, and terminal app helpers | Yes |
| `static-analysis-python` | Python lint/type/security analysis helpers | Yes |
| `testing-evidence` | Rich pytest reports and rerun/random/repeat helpers | Yes |
| `testing-extended` | Parallel/retry/benchmark tests, mocks, fixtures, containers | Yes |
| `ci-integration` | CI/API integration, retries, progress, dotenv/keyring helpers | Yes |
| `packaging-build` | pip-tools, build, twine, hatch, auditwheel helpers | Yes |
| `reporting-extended` | Docs, Office/PDF, report rendering, rich output | Yes |
| `heavy-security-optional` | Native-heavy RE/security analysis packages | Yes |

Current broad-catalog candidate size: about 679 MB of wheel files across 738
wheels before Docker image overhead.

See `docs/python-311-wheelhouse-support-matrix.md` for current fetch and smoke
results.

## Build

```bash
make python-wheelhouse-fetch   # download wheels into data-bundles/sources/
make python-wheelhouse-image   # build the carrier image
make python-wheelhouse-smoke   # run offline install smoke tests
make python-wheelhouse-verify  # verify SHA256SUMS
```

## Extract to internal PyPI

```bash
id=$(docker create "$REGISTRY/spt-python-wheelhouse-py311:$TAG")
docker cp "${id}:/wheelhouse/py311/." ./extracted-wheels/
docker rm "${id}"
# upload to your PyPI:
twine upload --repository-url "$INTERNAL_PYPI_URL" extracted-wheels/**/*.whl
```

## Offline install in tool images

```dockerfile
COPY --from=spt-python-wheelhouse-py311:$TAG /wheelhouse/py311/core-python/ /opt/wheels/core-python/
COPY --from=spt-python-wheelhouse-py311:$TAG /requirements/py311/core-python.lock /opt/wheels/
RUN pip install --no-index --find-links /opt/wheels/core-python/ -r /opt/wheels/core-python.lock
```

## Design contract

- Target: CPython 3.11, Linux x86_64, Rocky 8/RHEL 8-family runtime
- Preferred wheel baseline: `manylinux_2_17_x86_64`
- `manylinux_2_28_x86_64` wheels may be accepted only after validation on the
  target Rocky 8-compatible runtime
- Accepted ABI tags: `cp311`, `abi3`, `py3-none-any`
- Lock files are pinned via `pip-compile --resolver=backtracking`
- Heavy ML (torch, transformers, faiss, sentence-transformers) is explicitly excluded
- Supported optional groups must fetch and smoke successfully; experimental
  groups may warn without blocking release validation
- `python-magic` requires `libmagic` installed in the runtime image
- `weasyprint`, database clients, and native security packages may require
  additional runtime OS libraries even when their Python wheels install cleanly
- `onnxruntime` wheels download for this target, but the smoke container may
  reject its native extension if executable-stack policy is locked down; keep
  `ml-runtime-light` experimental until it passes on representative Rocky 8
  hosts
- `pyshark` imports but requires `tshark` for useful runtime work
- `hexdump`, `ropper`/`filebytes`, `keystone-engine`, `watchdog`,
  `python-jenkins`/`multi-key-dict`, `pymaven`, `aiodns`/`pycares`,
  `python-afl`, `python-systemd`, `netifaces`, `python-snappy`, and `scalene`
  are excluded from the paved binary-only wheelhouse candidate because they
  either did not produce compatible CPython 3.11 `manylinux_2_17_x86_64`
  wheels during validation or are better handled as host/tool-image-specific
  native/runtime integrations
