# Data Bundles

Data bundles carry vulnerability intelligence, rule packs, and research corpora
separately from Docker images.

The image bundle answers: "Which tools can run offline?"

The data bundle answers: "What vulnerability and research knowledge do those
tools use offline?"

## Layout

```text
data-bundles/
├── README.md
├── sources/
│   ├── cwe/
│   ├── capec/
│   ├── mitre-attack/
│   ├── cisa-kev/
│   ├── nvd/
│   ├── osv/
│   ├── epss/
│   ├── github-advisory-db/
│   ├── yara-rules/
│   ├── semgrep-rules/
│   ├── codeql-packs/
│   └── vendor-advisories/
└── out/
    ├── spt-data-bundle-<TAG>.tar
    └── spt-data-bundle-<TAG>.tar.sha256
```

## Connected-Side Flow

Fetch or stage datasets under `data-bundles/sources/`, then bundle them:

```bash
make data-fetch TAG=2026-04-25
make data-bundle TAG=2026-04-25
make data-bundle-smoke TAG=2026-04-25
```

`make data-fetch` runs every script under `data-bundles/fetch/`.
`scripts/export-data-bundle.sh` also writes a source manifest, source
checksums, full tar checksum, and split part checksums under
`data-bundles/out/`.

## Air-Gapped Flow

```bash
sha256sum -c spt-data-bundle-2026-04-25.parts.sha256
cat spt-data-bundle-2026-04-25.tar.part-* > spt-data-bundle-2026-04-25.tar
sha256sum -c spt-data-bundle-2026-04-25.tar.sha256
mkdir -p /opt/spt-data
tar -xf spt-data-bundle-2026-04-25.tar -C /opt/spt-data
```

The data bundle is optional. Import the image bundle by itself for image-only
or fixture-based smoke tests. Import the data bundle when full offline
vulnerability/intelligence coverage is required.

Full data bundles may trigger AV/DLP because public advisory and rule datasets
can include PoC strings, exploit commands, webshell snippets, suspicious
indicators, and scanner fixtures. See `SECURITY_NOTES.md`.

Mount the data read-only into tools:

```bash
docker run --rm --network none \
  -v /opt/spt-data/sources/osv:/osv-db:ro \
  -v "$PWD/project:/workspace:ro" \
  -v "$PWD/artifacts:/artifacts" \
  "$REGISTRY/spt-osv-scanner:$TAG"
```

## Recommended Sources

| Source | Purpose |
|--------|---------|
| CWE | Weakness taxonomy |
| CAPEC | Attack pattern taxonomy |
| MITRE ATT&CK | Tactics, techniques, mitigations |
| CISA KEV | Known exploited vulnerability catalog |
| NVD/CVE | CVE records and CVSS data |
| OSV | Open source vulnerability database |
| EPSS | Exploit prediction scores |
| GitHub Advisory DB | Ecosystem advisories |
| YARA rules | File and malware triage rules |
| Semgrep rules | SAST rules |
| CodeQL packs | CodeQL queries/packs |
| Vendor advisories | Product-specific vulnerability intelligence |

Keep raw source metadata, dataset version, fetch date, checksum, and license
notes with each dataset.

## Fetch Configuration

Most public sources have default URLs. Organization-specific rule/advisory
sources can be overridden through environment variables.

| Variable | Purpose |
|----------|---------|
| `NVD_YEARS` | NVD feeds to fetch. Default: `modified recent`. Example: `2024 2025 modified recent` |
| `YARA_RULES_REPO_URL` | Optional Git repo for approved YARA rules. If unset, fetches YARA Forge |
| `YARA_FORGE_RULESET` | YARA Forge ruleset to fetch when `YARA_RULES_REPO_URL` is unset. Default: `extended` |
| `SEMGREP_RULES_REPO_URL` | Semgrep rules repo. Default: `https://github.com/semgrep/semgrep-rules.git` |
| `CODEQL_PACKS` | CodeQL packs to download with `codeql pack download`. Default: `codeql/cpp-queries codeql/python-queries codeql/rust-queries` |
| `CODEQL_IMAGE` | CodeQL image used for pack downloads. Default: `$REGISTRY/spt-codeql:$TAG` |
| `CODEQL_USE_DOCKER` | Use Docker for CodeQL pack downloads when available. Default: `auto`; set `0` to force local `codeql` |
| `OSV_FETCH_MODE` | OSV DB fetch mode. Default: `direct`; set `scanner` to use local `osv-scanner` |
| `OSV_ECOSYSTEMS` | Optional space-separated OSV ecosystems to fetch. Default: all ecosystems from OSV |
| `VENDOR_ADVISORY_URLS` | Space-separated vendor advisory URLs to fetch |
| `CISA_KEV_URL` | Override CISA KEV URL |
| `CWE_URL` | Override CWE URL |
| `CAPEC_URL` | Override CAPEC URL |
| `MITRE_ATTACK_BASE_URL` | Override MITRE ATT&CK STIX base URL |
| `EPSS_URL` | Override EPSS URL |
| `NVD_FEED_BASE_URL` | Override NVD feed base URL |
| `GHSA_REPO_URL` | Override GitHub Advisory Database repo URL |

## OSV Offline Cache

The OSV fetcher downloads OSV ecosystem zip databases directly into the cache
layout expected by OSV Scanner:

```text
data-bundles/sources/osv/osv-scanner/<ecosystem>/all.zip
```

Set `OSV_FETCH_MODE=scanner` to use a locally installed `osv-scanner` instead.

## Rule Defaults

The default data fetch pulls YARA Forge Extended, public Semgrep rules, and CodeQL
packs for C/C++, Python, and Rust. Override `YARA_RULES_REPO_URL`,
`YARA_FORGE_RULESET`, `SEMGREP_RULES_REPO_URL`, or `CODEQL_PACKS` to use an
organization-approved mirror or a narrower language set.

## Sanitized Bundles

The generic archive produced by `make data-bundle` is:

```text
spt-data-bundle-<TAG>.tar
```

Use the names below only if you publish explicit release variants. Full bundles
are for maximum RE/vulnerability research coverage:

```text
intel-data-full-<TAG>.tar.zst
```

Use sanitized bundles for environments that cannot accept AV/DLP-sensitive
advisory text:

```text
intel-data-sanitized-<TAG>.tar.zst
```

Sanitized bundles should exclude or redact PoC/exploit-heavy records and will
have reduced coverage.
