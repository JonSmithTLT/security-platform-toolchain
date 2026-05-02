# CPython 3.11 Linux x86_64 Wheelhouse Refresh Plan

This plan extends the existing `spt-python-wheelhouse-py311` lane into a
team-wide enablement pack for CPython 3.11 on Linux x86_64. It is not a new
package server proposal, and it is not a forced migration. Existing Python 3.6
and older flows continue to run while Python 3.11 becomes a validated internal
target for teams that are ready to test or migrate.

## Target

| Field | Initial value | Validation required |
|---|---|---|
| Python runtime | CPython 3.11 | Confirm patch version used by CI/base image |
| OS family | Rocky Linux 8 / RHEL 8-family assumed | Confirm exact team image |
| CPU/platform | Linux x86_64 | Confirm CI runners and developer images |
| Runtime glibc | 2.28 expected for Rocky 8-family | Confirm on oldest supported host |
| Wheel baseline | `manylinux_2_17_x86_64` preferred | Confirm distro and glibc floor |
| Accepted Python tags | `cp311`, `abi3`, `py3-none-any` | Verify per wheel filename/tag |
| Normal install mode | Binary wheels only | Source builds only by documented exception |
| Package source | Existing internal PyPI/mirror/artifacts | No public PyPI fallback in validation |

Older Linux is supported only if both layers agree:

- The CPython 3.11 interpreter/base image must run on the target distro and
  glibc.
- The wheels must have compatible tags for that runtime, preferably
  `manylinux_2_17_x86_64` or a lower/equivalent baseline accepted by the target.

`manylinux_2_17_x86_64` is generally the practical floor for modern CPython
3.11 native wheels on glibc Linux. If the team target is older than glibc 2.17,
Alpine/musl, or a vendor-hardened image with missing shared libraries, the
wheelhouse can still be useful but those targets need their own compatibility
lane or documented exceptions.

For the current expected Rocky 8/RHEL 8-family target, use
`manylinux_2_17_x86_64` as the conservative default. Accept
`manylinux_2_28_x86_64` only after validation on the real team image, since it
matches the expected glibc floor more closely and may exclude older hosts.

The repo already contains a CPython 3.11 wheelhouse flow:

| Asset | Purpose |
|---|---|
| `requirements/py311/*.in` | Curated package group inputs |
| `requirements/py311/*.lock` | Pinned generated locks |
| `data-bundles/fetch/fetch-python-wheels.sh` | Compiles locks and downloads binary wheels |
| `images/python-wheelhouse-py311/` | Data-carrier image for wheels, locks, hashes, manifest |
| `examples/python-wheelhouse-smoke/run-python-wheelhouse-smoke.sh` | Offline install and import smoke tests |
| `make python-wheelhouse-fetch` | Build/update candidate wheelhouse content |
| `make python-wheelhouse-image` | Build wheelhouse carrier image |
| `make python-wheelhouse-smoke` | Validate offline installation by group |
| `make python-wheelhouse-verify` | Verify `SHA256SUMS` |

Current candidate validation results are summarized in
`docs/python-311-wheelhouse-support-matrix.md`.

## Short Implementation Plan

1. Confirm the exact Linux baseline: CI image, developer image, distro version,
   glibc version, OpenSSL policy, and whether `manylinux_2_17_x86_64` is the
   correct minimum.
2. Inventory Python dependencies across the two Python projects, the Python
   test framework, and CI/container glue.
3. Compare the inventory with the current internal package source and classify
   each dependency by Python tag, ABI tag, platform tag, wheel/sdist status,
   native OS library needs, and owning repo/team.
4. Map packages into release groups and decide which groups block the initial
   supported pack.
5. Refresh candidate `.in` and lock files, then download/build a binary-only
   wheelhouse for CPython 3.11 Linux x86_64.
6. Validate each group in clean Python 3.11 environments with public egress
   disabled, `pip check`, import smoke tests, and selected native/package
   probes.
7. Publish validated wheels, locks, hashes, manifest, and support matrix to the
   existing internal package/artifact infrastructure.
8. Document adoption commands for venv, requirements files, CI/Jenkins, and
   package request handling.
9. Establish a refresh cadence and request process so package updates do not
   drift back into one-off project work.

## Dependency Inventory Table

Use this table as the working inventory format. It deliberately separates
"present in mirror" from "validated for CPython 3.11 Linux x86_64".

| Package | Current version | Candidate py311 version | Used by | Source file | Internal candidate status | Wheel tag | ABI tag | Platform tag | Sdist only? | OS libraries | Blocking? | Notes |
|---|---:|---:|---|---|---|---|---|---|---|---|---|---|
| `jsonschema` | TBD | From `core-python.lock` | Toolchain/core | `requirements/py311/core-python.in` | TBD | TBD | TBD | TBD | No | None expected | Yes | Existing core group |
| `requests` | TBD | From `core-python.lock` | Toolchain/core, tests | `requirements/py311/core-python.in` | TBD | `py3-none-any` expected | None | Any | No | CA bundle via `certifi` | Yes | Also appears in proposed testing/API stacks |
| `fastapi` | TBD | From `api-future-fastapi.lock` | API service migration | `requirements/py311/api-future-fastapi.in` | TBD | `py3-none-any` expected | None | Any | No | None expected | Initial decision | Existing future API group |
| `sqlalchemy` | TBD | From `data-ingest-light.lock` | Data ingest | `requirements/py311/data-ingest-light.in` | TBD | `py3-none-any` expected | None | Any | No | Driver-dependent | Initial decision | `greenlet` wheel availability is the native risk |
| `cryptography` | TBD | From `security-research-python.lock` | Security tooling | `requirements/py311/security-research-python.in` | TBD | TBD | `abi3`/`cp311` expected | manylinux | No | OpenSSL policy must be confirmed | Yes | Native wheel must be verified |
| `yara-python` | TBD | From `security-research-python.lock` | Security analysis | `requirements/py311/security-research-python.in` | TBD | TBD | `cp311` expected | manylinux | Possible | YARA/libyara policy must be confirmed | Initial decision | Treat as native validation package |
| `python-magic` | TBD | From `security-research-python.lock` | Security analysis | `requirements/py311/security-research-python.in` | TBD | `py3-none-any` expected | None | Any | No | `libmagic` required at runtime | Yes if used | Already documented runtime OS dependency |
| `numpy` | TBD | From optional locks | Data science/RAG/ML | multiple `requirements/py311/*.in` | TBD | TBD | `cp311` expected | manylinux | No | BLAS/OpenMP wheel behavior | Optional | Keep optional unless a project requires it |
| `pyarrow` | TBD | From `data-science-optional.lock` | Data processing | `requirements/py311/data-science-optional.in` | TBD | TBD | `cp311` expected | manylinux | No | Native binary size/runtime libs | Optional | Heavy optional group |
| `onnxruntime` | TBD | From `ml-runtime-light.lock` | ML inference | `requirements/py311/ml-runtime-light.in` | TBD | TBD | `cp311` expected | manylinux | No | CPU feature baseline | Experimental | Heavy optional group; runtime probe must pass before support |

Inventory commands to start from this repo:

```bash
rg -n "^(FROM|RUN .*pip|pip install|python -m pip|requirements|tox|nox|pytest|PYTHON|python3)" \
  requirements images examples scripts common Makefile docker-compose.yml
rg --files -g 'requirements*.txt' -g 'pyproject.toml' -g 'setup.cfg' \
  -g 'setup.py' -g 'tox.ini' -g 'noxfile.py' -g 'Dockerfile' -g 'Jenkinsfile'
```

Run equivalent scans in the two Python projects and the Python test framework.
Bring the results into the table above before deciding final blocking groups.

## Missing or Incompatible Package Report

Track each failing package with enough evidence to avoid package-name-only
decisions.

| Package | Requested by | Failure mode | Evidence to capture | Resolution |
|---|---|---|---|---|
| TBD | Repo/team | Internal mirror has no `cp311` Linux x86_64 wheel | `pip download --only-binary=:all:` output and index URL | Add wheel or choose compatible version |
| TBD | Repo/team | Mirror has sdist only | Candidate filename and metadata | Build/promote wheel or mark unsupported |
| TBD | Repo/team | Wrong platform tag | Actual wheel filename | Fetch/build manylinux x86_64 wheel |
| TBD | Repo/team | Wrong ABI/Python tag | Actual wheel filename | Select cp311/abi3-compatible release |
| TBD | Repo/team | Runtime OS library missing | Import/probe failure log | Add OS package to base image docs or group notes |
| TBD | Repo/team | Resolver conflict | Lock compile output | Pin intentional version or split groups |

False py311-ready advertising should be recorded when the internal source has
metadata or package versions that appear installable for Python 3.11 but the
actual compatible wheel is missing, wrong-platform, wrong-ABI, or source-only.

## Proposed Package Groups

The repo currently uses focused wheelhouse groups. For team-wide adoption, keep
the existing groups as implementation-friendly files and publish this support
taxonomy in the manifest/docs:

| Team-facing group | Existing/proposed file mapping | Initial blocking status |
|---|---|---|
| `py311-core-dev` | `requirements/py311/core-python.in` | Blocking |
| `py311-testing-quality` | `requirements/py311/testing-dev.in` | Blocking for test framework |
| `py311-networking-protocol` | New group if required by inventory | Blocking only if used by current projects |
| `py311-api-service` | `requirements/py311/api-future-fastapi.in` | Blocking if API project starts py311 testing |
| `py311-database-clients` | Extend/split `data-ingest-light.in` after policy decisions | Conditional |
| `py311-data-processing` | `normalizers-reporting.in`, `data-science-optional.in` | Core reporting blocking, heavy data optional |
| `py311-security-crypto-analysis` | `requirements/py311/security-research-python.in` | Blocking for security tooling using it |
| `py311-reporting-docs` | `requirements/py311/normalizers-reporting.in` | Blocking |
| `py311-packaging-build` | Add only if teams need build/publish workflows | Conditional |
| `py311-heavy-optional` | `data-science-optional.in`, `ml-runtime-light.in`, future native-heavy groups | Optional/experimental |

Initial release recommendation:

| Release tier | Groups |
|---|---|
| Required paved road | `py311-core-dev`, `py311-testing-quality`, `py311-reporting-docs` |
| Project-enabling | `py311-api-service`, `py311-security-crypto-analysis`, `py311-database-clients` once inventory confirms need |
| Optional/heavy | `py311-data-processing` heavy packages, `py311-heavy-optional`, ML/runtime analysis packages |

Target breadth should be intentionally broad. The artifact can carry a large
catalog as long as the support promise stays tiered and downstream runtime
images copy only the groups they need.

Candidate additions for a broad software development, testing, and security
parser catalog:

| Area | Candidate packages |
|---|---|
| Binary parsing and file formats | `construct`, `kaitaistruct`, `construct-typing`, `bitstruct`, `hexdump`, `python-magic`, `filetype`, `olefile`, `oletools`, `msoffcrypto-tool`, `pdfminer.six`, `pypdf`, `python-docx`, `python-pptx`, `openpyxl`, `xlsxwriter` |
| Network/protocol parsing | `scapy`, `dpkt`, `dnspython`, `h11`, `h2`, `hyperframe`, `wsproto`, `websockets`, `aiohttp`, `httpx`, `paramiko`, `pyserial`, `protobuf`, `grpcio`, `grpcio-tools` |
| Security analysis | `cryptography`, `pycryptodome`, `bcrypt`, `passlib`, `pyjwt`, `pyopenssl`, `capstone`, `unicorn`, `keystone-engine`, `pyelftools`, `pefile`, `lief`, `yara-python`, `pwntools`, `ropper`, `z3-solver` |
| Testing and service mocks | `pytest-xdist`, `pytest-rerunfailures`, `pytest-benchmark`, `pytest-httpx`, `requests-mock`, `respx`, `factory-boy`, `faker`, `vcrpy`, `docker`, `testcontainers` |
| System command and shell automation | `sh`, `plumbum`, `invoke`, `fabric`, `pexpect`, `psutil`, `distro`, `shellingham`, `humanfriendly`, `colorama`, `platformdirs`, `filelock`, `subprocess-tee`, `python-on-whales`, `python-crontab`, `schedule` |
| Data and reporting | `lxml`, `beautifulsoup4`, `defusedxml`, `xmltodict`, `ijson`, `orjson`, `ujson`, `msgpack`, `cbor2`, `markdown`, `jinja2`, `pygments`, `rich`, `tabulate`, `reportlab`, `weasyprint` |
| Build and release | `pip-tools`, `build`, `twine`, `hatch`, `hatchling`, `poetry-core`, `setuptools-scm`, `auditwheel`, `check-wheel-contents` |
| Testing evidence and failure analysis | `pytest-json-report`, `pytest-metadata`, `pytest-html`, `testfixtures`, `pytest-randomly`, `pytest-repeat`, `loguru`, `python-json-logger`, `coloredlogs`, `deepdiff`, `jsonpath-ng`, `rapidfuzz`, `regex`, `dateparser`, `ruamel.yaml` |
| Dependency audit and static analysis | `pipdeptree`, `pip-audit`, `cyclonedx-bom`, `license-expression`, `virtualenv`, `bandit`, `pylint`, `flake8`, typed stub packages |
| Profiling, fuzzing, and OS evidence | `atheris`, `yappi`, `memory-profiler`, `objgraph`, `pyinstrument`, `line-profiler`, `pyroute2`, `netaddr`, `pyzmq`, `ldap3`, `paho-mqtt`, `pyshark` |
| Large artifact processing | `duckdb`, `polars`, `zstandard`, `lz4` |

These broad-catalog candidates are represented by optional implementation
groups under `requirements/py311/`: `networking-protocol.in`,
`security-parsers.in`, `system-automation.in`, `testing-extended.in`,
`packaging-build.in`, `reporting-extended.in`, and
`heavy-security-optional.in`. Expanded testing/evidence groups are represented
by `testing-evidence.in`, `failure-log-analysis.in`, `dependency-audit.in`,
`profiling-debugging.in`, `network-os-evidence.in`,
`large-artifact-compression.in`, `ci-integration.in`,
`static-analysis-python.in`, `fuzzing-optional.in`, and
`llm-client-optional.in`.

Initial broad-catalog fetch results:

| Result | Package/group |
|---|---|
| Included after compatibility pin | `cbor2<=5.9.0`, `ujson<=5.10.0`, `lief<=0.12.3`, `psutil<=7.1.1`, `z3-solver<=4.15.4.0`, `rapidfuzz<=3.13.0`, `duckdb<=1.2.2`, `pyzmq<=26.4.0`, `line-profiler<=5.0.0`, `httptools<=0.6.4` |
| Included in latest expansion | `orjson` and `pydantic-settings` in core, `tblib`, `stack-data`, `aiofiles`, `trio`, `pymongo`, `mistune`, `html5lib`, `bleach`, `python-frontmatter`, `pydot`, `simplejson`, `prompt-toolkit`, `questionary`, `textual`, optional `api-service-standard` with `uvicorn[standard]`, `uvloop`, `httptools`, `websockets`, `watchfiles`, optional `llm-client-optional` with `openai` and `anthropic` SDK adapters |
| Excluded from binary-only candidate | `hexdump`, `ropper`/`filebytes`, `keystone-engine`, `watchdog`, `python-jenkins`/`multi-key-dict`, `pymaven`, `aiodns`/`pycares`, `python-afl`, `python-systemd`, `netifaces`, `python-snappy`, `scalene` |
| Needs OS/runtime validation | `python-magic` with `libmagic`, `weasyprint` with Pango/GObject libraries, `onnxruntime` executable-stack policy, `pyshark` with `tshark` |

Current generated candidate size is about 679 MB of wheel files and 738 wheels
across 27 groups. This is acceptable for a data-carrier artifact; downstream
runtime images should still copy only the specific groups they need.

Packages with large native footprints or external system dependencies should
still be included where they have a realistic chance of working on the team
Linux baseline, but they should default to optional or experimental until their
runtime probes pass on representative hosts.

## Constraints File Strategy

Produce one support-level constraints file for teams:

```text
constraints-py311-linux-x86_64.txt
```

Generation strategy:

1. Compile each group from curated `.in` files with backtracking resolver.
2. Merge required group locks into the top-level constraints file.
3. Keep optional/heavy constraints separate or clearly marked so they do not
   block core installation.
4. Pin every package version. Do not use unbounded latest-version ranges in
   team-facing constraints.
5. Record intentional pins and conflicts in the refresh notes.
6. Keep raw mirror/cache contents out of the supported constraints file unless
   validation passed.

Example install pattern:

```bash
python3.11 -m venv .venv-py311
. .venv-py311/bin/activate
python -m pip install --upgrade pip
python -m pip install \
  --index-url "$INTERNAL_PYPI_URL" \
  --constraint constraints-py311-linux-x86_64.txt \
  -r requirements.txt
python -m pip check
```

For validation jobs, prefer local wheelhouse or internal-only index settings:

```bash
python -m pip install \
  --no-index \
  --find-links /opt/wheelhouse/py311/core-python \
  -r requirements/py311/core-python.lock
```

## Smoke Test Strategy

Validation must prove that installs do not silently fall back to public PyPI.

| Test | Required behavior |
|---|---|
| Clean venv per group | Start from empty Python 3.11 environment |
| Internal-only install | Use `--no-index --find-links` or internal index with public egress blocked |
| Binary-only enforcement | Use `--only-binary=:all:` during download/build validation |
| `pip check` | Fail on dependency metadata conflicts |
| Import probe | Import representative modules for every group |
| Native smoke | Run minimal runtime operation for native packages |
| Network/database smoke | Use local/mock endpoint where practical |
| Hash verification | Verify wheel hashes before promotion |
| Manifest verification | Confirm wheel filename tags match target policy |

Current repo smoke coverage already performs offline installs and import probes
through `make python-wheelhouse-smoke`. Extend it with:

| Package area | Additional probe |
|---|---|
| `cryptography` | Generate/use a local key or Fernet token |
| `yara-python` | Compile a trivial rule |
| `python-magic` | Verify import separately from `libmagic` runtime availability |
| `sqlalchemy` | Create an in-memory SQLite engine and run `select 1` |
| `fastapi` | Instantiate app and run a local TestClient if included |
| `numpy`/`pandas`/`pyarrow` | Create a small array/dataframe/table |
| Database drivers | Connection import plus documented skipped live service tests |

## Promotion and Publishing Strategy

Publish through the existing internal package/artifact infrastructure after the
candidate wheelhouse passes validation.

Artifacts to publish:

| Artifact | Purpose |
|---|---|
| Wheels | Installable validated package set |
| Group locks | Reproducible group installation |
| `constraints-py311-linux-x86_64.txt` | Team-facing version guardrail |
| `SHA256SUMS` | Integrity verification |
| `wheelhouse-manifest.json` | Package/version/filename/hash/group/status metadata |
| Support matrix | Human-readable pass/fail by group and package |
| Refresh notes | Conflict decisions, OS dependencies, exceptions |

Manifest status values should distinguish:

| Status | Meaning |
|---|---|
| `mirrored` | Present in internal source/cache only |
| `candidate` | Included in current candidate wheelhouse |
| `validated` | Installed and smoked for py311 Linux x86_64 |
| `validated-with-os-deps` | Python wheel passed, external OS library required |
| `optional` | Supported optional group that passed fetch and smoke validation |
| `experimental` | Available but not a supported paved road |
| `blocked` | Missing/incompatible/conflicting |

Do not present raw internal mirror contents as supported. The supported status
comes only from the validation run.

## Adoption Instructions

Local team test:

```bash
python3.11 -m venv .venv-py311
. .venv-py311/bin/activate
python -m pip install --upgrade pip
python -m pip install \
  --index-url "$INTERNAL_PYPI_URL" \
  --constraint constraints-py311-linux-x86_64.txt \
  -r requirements.txt
python -m pip check
pytest
```

Repository opt-in pattern:

```text
# requirements-py311.txt
-c constraints-py311-linux-x86_64.txt
-r requirements.txt
```

Jenkins/CI pattern:

```groovy
stage('Python 3.11 smoke') {
  steps {
    sh '''
      python3.11 -m venv .venv-py311
      . .venv-py311/bin/activate
      python -m pip install --upgrade pip
      python -m pip install \
        --index-url "$INTERNAL_PYPI_URL" \
        --constraint constraints-py311-linux-x86_64.txt \
        -r requirements.txt
      python -m pip check
      pytest
    '''
  }
}
```

Package request intake:

| Field | Required |
|---|---|
| Package name/version | Yes |
| Owning repo/team | Yes |
| Required group | Yes |
| Reason needed | Yes |
| Current Python 3.6 behavior | If relevant |
| CPython 3.11 wheel evidence | If known |
| OS library requirement | If known |
| Blocking date | If any |

## Open Investigation Questions

| Question | Owner | Output |
|---|---|---|
| What exact Linux baseline are we targeting? | Platform/CI | Distro, glibc, OpenSSL, CPU baseline |
| Does the internal mirror support Python/platform tag filtering? | Artifact owners | Query/upload/promotion procedure |
| Which packages are falsely advertised as py311-ready? | Wheelhouse refresh owner | Missing/incompatible package report |
| Which packages block the two Python projects? | Project owners | Blocking inventory rows |
| Which packages block the test framework? | Test framework owner | Blocking inventory rows |
| Which dependencies require OS libraries outside Python wheels? | Package owners | OS dependency table |
| Which groups block initial release? | Team leads | Support tier decision |
| What minimum matrix lets teams start testing? | Platform + project owners | Required groups and pass criteria |
| How are refreshes and requests handled? | Artifact owners | Cadence and request SLA |
| How do we prevent public PyPI fallback? | CI/platform | Network and pip configuration proof |

## Initial Done Criteria

- Exact Linux baseline confirmed.
- Inventory complete for the two projects, test framework, CI scripts, and
  container bases.
- Required groups install in clean Python 3.11 environments using only internal
  package sources or the local wheelhouse.
- `pip check`, hash verification, and import/native smoke tests pass.
- Support matrix distinguishes validated, optional, experimental, and blocked
  packages.
- Validated artifacts are published to the existing internal infrastructure.
- Teams have copy/paste adoption instructions and a package request process.
