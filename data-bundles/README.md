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
```

`make data-fetch` runs every script under `data-bundles/fetch/`.

## Air-Gapped Flow

```bash
sha256sum -c spt-data-bundle-2026-04-25.tar.sha256
mkdir -p /opt/spt-data
tar -xf spt-data-bundle-2026-04-25.tar -C /opt/spt-data
```

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
sources are opt-in through environment variables.

| Variable | Purpose |
|----------|---------|
| `NVD_YEARS` | NVD feeds to fetch. Default: `modified recent`. Example: `2024 2025 modified recent` |
| `YARA_RULES_REPO_URL` | Optional Git repo for approved YARA rules |
| `SEMGREP_RULES_REPO_URL` | Optional Git repo for approved Semgrep rules. Defaults to repo-local starter rules |
| `CODEQL_PACKS` | Optional CodeQL pack names to download with `codeql pack download` |
| `VENDOR_ADVISORY_URLS` | Space-separated vendor advisory URLs to fetch |
| `CISA_KEV_URL` | Override CISA KEV URL |
| `CWE_URL` | Override CWE URL |
| `CAPEC_URL` | Override CAPEC URL |
| `MITRE_ATTACK_BASE_URL` | Override MITRE ATT&CK STIX base URL |
| `EPSS_URL` | Override EPSS URL |
| `NVD_FEED_BASE_URL` | Override NVD feed base URL |
| `GHSA_REPO_URL` | Override GitHub Advisory Database repo URL |

## OSV Offline Cache

The OSV fetcher expects `osv-scanner` on the connected host. It runs OSV
Scanner's offline database download workflow into:

```text
data-bundles/sources/osv/
```

If `osv-scanner` is not installed, the fetcher leaves the directory in place
with metadata and prints the command to run manually.
