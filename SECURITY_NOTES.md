# Security Notes

This repository builds offline security tooling and optional offline data
bundles for vulnerability research, reverse engineering, and CI/CD security
workflows.

## Data Bundle Content

The data bundle may trigger AV, EDR, DLP, mail gateway, or repository scanning
alerts. Upstream advisory and intelligence datasets can contain:

- Proof-of-concept strings
- Exploit commands
- Webshell snippets
- RCE payload examples
- Malware family indicators
- Suspicious filenames, hashes, domains, URLs, registry keys, or mutexes
- Scanner test fixtures and intentionally vulnerable dependency metadata

This is expected for vulnerability intelligence content. The data bundle is not
intended to contain:

- Live malware samples
- Real credentials
- Proprietary target data
- Customer source code
- Private incident data

If a downstream environment cannot accept AV-sensitive advisory text, publish a
sanitized data bundle variant that excludes or redacts PoC/exploit-heavy
records. Sanitized bundles have reduced vulnerability and threat-intelligence
coverage.

## Bundle Types

The image bundle contains Docker images and can be imported without the data
bundle. This is enough to start tools offline and run fixture-based smoke tests.

The data bundle is optional, but required for full offline vulnerability,
advisory, rule, and intelligence coverage. Examples include OSV databases, NVD,
GitHub Advisory Database, YARA Forge rules, Semgrep rules, CodeQL packs, CWE,
CAPEC, MITRE ATT&CK, CISA KEV, and EPSS.

## Handling Guidance

- Keep generated image and data tarballs out of Git history.
- Distribute generated bundles through GitHub Release assets, an internal
  artifact store, an internal registry, or approved removable media.
- Verify checksums before importing bundles.
- Treat full data bundles as security research material that may require
  exceptions in AV/DLP tooling.
- Do not add live malware, real secrets, or proprietary target data to
  `data-bundles/sources`.

