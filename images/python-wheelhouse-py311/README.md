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
| `ml-runtime-light` | onnxruntime (CPU) | Yes |

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

- Target: CPython 3.11, Linux x86_64 (`manylinux_2_17_x86_64`)
- Accepted ABI tags: `cp311`, `abi3`, `py3-none-any`
- Lock files are pinned via `pip-compile --resolver=backtracking`
- Heavy ML (torch, transformers, faiss, sentence-transformers) is explicitly excluded
- Optional groups (`data-science-optional`, `ml-runtime-light`) may fail fetch
  without blocking the required groups
- `python-magic` requires `libmagic` installed in the runtime image
