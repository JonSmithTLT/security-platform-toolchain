# CPython 3.11 Wheelhouse Candidate Support Matrix

Candidate target:

| Field | Value |
|---|---|
| Python | CPython 3.11 |
| OS/runtime | Rocky 8 / RHEL 8-family assumed |
| Platform | Linux x86_64 |
| Wheel baseline | `manylinux_2_17_x86_64` preferred |
| Fetch policy | `--only-binary=:all:` |
| Candidate size | 679 MB of wheels |
| Candidate wheel count | 738 |

## Group Results

| Group | Wheels | Fetch | Offline smoke | Status |
|---|---:|---|---|---|
| `core-python` | 36 | Pass | Pass | Required validated |
| `api-future-fastapi` | 22 | Pass | Pass | Required validated |
| `normalizers-reporting` | 29 | Pass | Pass | Required validated |
| `testing-dev` | 29 | Pass | Pass | Required validated |
| `data-ingest-light` | 16 | Pass | Pass | Required validated |
| `rag-light` | 10 | Pass | Pass | Required validated |
| `security-research-python` | 8 | Pass | Pass | Required validated |
| `data-science-optional` | 11 | Pass | Pass | Optional validated |
| `api-service-standard` | 12 | Pass | Pass | Optional validated |
| `dependency-audit` | 71 | Pass | Pass | Optional validated |
| `failure-log-analysis` | 23 | Pass | Pass | Optional validated |
| `fuzzing-optional` | 11 | Pass | Pass | Optional validated |
| `large-artifact-compression` | 10 | Pass | Pass | Optional validated |
| `llm-client-optional` | 18 | Pass | Pass | Optional validated |
| `ml-runtime-light` | 9 | Pass | Warn | Experimental candidate |
| `network-os-evidence` | 18 | Pass | Pass | Optional validated |
| `networking-protocol` | 45 | Pass | Pass | Optional validated |
| `profiling-debugging` | 6 | Pass | Pass | Optional validated |
| `security-parsers` | 40 | Pass | Pass | Optional validated with OS dependency notes |
| `system-automation` | 45 | Pass | Pass | Optional validated |
| `static-analysis-python` | 27 | Pass | Pass | Optional validated |
| `testing-evidence` | 15 | Pass | Pass | Optional validated |
| `testing-extended` | 35 | Pass | Pass | Optional validated |
| `ci-integration` | 35 | Pass | Pass | Optional validated |
| `packaging-build` | 73 | Pass | Pass | Optional validated |
| `reporting-extended` | 41 | Pass | Pass | Optional validated with OS dependency notes |
| `heavy-security-optional` | 43 | Pass | Pass | Optional validated |

## Compatibility Decisions

| Package | Decision | Reason |
|---|---|---|
| `cbor2` | Pin `<=5.9.0` | Newer resolver choice lacked a target wheel |
| `ujson` | Pin `<=5.10.0` | Newer resolver choice lacked a target wheel |
| `lief` | Pin `<=0.12.3` | Current target lookup exposed only older compatible wheels |
| `psutil` | Pin `<=7.1.1` | Newer resolver choice lacked a target wheel |
| `z3-solver` | Pin `<=4.15.4.0` | Newer resolver choice lacked a target wheel |
| `rapidfuzz` | Pin `<=3.13.0` | Newer resolver choice lacked a target wheel |
| `duckdb` | Pin `<=1.2.2` | Newer resolver choice lacked a target wheel |
| `pyzmq` | Pin `<=26.4.0` | Newer resolver choice lacked a target wheel |
| `line-profiler` | Pin `<=5.0.0` | Newer resolver choice lacked a target wheel |
| `httptools` | Pin `<=0.6.4` | Newer resolver choice lacked a target wheel |
| `hexdump` | Exclude | Source-only under binary-only target policy |
| `ropper` / `filebytes` | Exclude | `filebytes` did not provide a compatible wheel |
| `keystone-engine` | Exclude | No compatible CPython 3.11 manylinux wheel found |
| `watchdog` | Exclude from `system-automation` | No compatible wheel found under the conservative binary-only target query |
| `python-jenkins` | Exclude from `ci-integration` | Transitive `multi-key-dict` did not provide a compatible wheel |
| `pymaven` | Exclude from `dependency-audit` | Sdist metadata/build step failed before binary validation |
| `aiodns` / `pycares` | Exclude from `networking-protocol` | `pycares` did not provide a clean binary-only path under the conservative target query |
| `python-afl` | Exclude from paved wheelhouse | Old AFL instrumentation/runtime integration; keep host/tool specific |
| `python-systemd` | Exclude from paved wheelhouse | Binds to systemd/libsystemd and target host policy |
| `netifaces` | Exclude from paved wheelhouse | Native extension did not fit the conservative binary-only lane; `pyroute2`/`psutil` cover most needs |
| `python-snappy` | Exclude from paved wheelhouse | Requires native Snappy/libsnappy runtime policy; `zstandard` and `lz4` are included |
| `scalene` | Exclude from paved wheelhouse | Profiler/runtime tool with native/system behavior; better as a dedicated tool image or host install |

## Runtime Dependency Notes

| Package/group | Note |
|---|---|
| `python-magic` | Requires `libmagic` on the runtime host/image |
| `weasyprint` | Requires Pango/GObject/Cairo-family system libraries |
| `onnxruntime` | Wheel downloads, but the smoke container rejected its native extension because executable-stack policy blocked it; keep `ml-runtime-light` experimental until tested on representative Rocky 8 hosts |
| `pyshark` | Imports, but useful runtime work requires `tshark` on the host/image |
| `pwntools` | Smoke emits a terminal/terminfo warning in minimal containers; import still passes |

## Verification Commands

Commands run for this candidate:

```bash
FORCE_FETCH=1 make python-wheelhouse-fetch DATA_DIR=data-bundles/sources
make python-wheelhouse-image DATA_DIR=data-bundles/sources
make python-wheelhouse-smoke
make python-wheelhouse-verify DATA_DIR=data-bundles/sources
```

`make python-wheelhouse-smoke` passed overall. Experimental `ml-runtime-light`
reported the `onnxruntime` executable-stack warning above.
