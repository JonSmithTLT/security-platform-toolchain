# sbom

Generates a **Software Bill of Materials** using [Syft](https://github.com/anchore/syft).

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_REPO` | `/workspace` | Directory or container image to scan |
| `SBOM_FORMAT` | `cyclonedx-json` | Output format (`cyclonedx-json`, `cyclonedx-xml`, `spdx-json`, `spdx-tag-value`) |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/sbom.log
└── sbom/
    └── sbom.<format>    # e.g. sbom.cyclonedx.json
```

## Scanning a container image

```bash
docker run --rm \
  -v artifacts:/artifacts \
  -e TARGET_REPO="alpine:3.19" \
  -e SBOM_FORMAT=spdx-json \
  registry.internal/security-platform/spt-sbom:latest
```
