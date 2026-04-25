# semgrep

Runs **Semgrep** SAST scans with custom or built-in rule sets.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_REPO` | `/workspace` | Source tree to scan |
| `SEMGREP_RULES` | `/rules` | Rules directory or config string (e.g. `p/owasp-top-ten`) |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |
| `SEMGREP_TIMEOUT` | `300` | Per-rule timeout in seconds |
| `SEMGREP_JOBS` | `4` | Parallel worker count |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/semgrep.log
└── results/semgrep/
    ├── tool-result.json          # normalised findings
    └── raw/semgrep.json          # native Semgrep JSON output
```

## Custom rules

Mount your rules directory to `/rules`:

```bash
docker run --rm \
  -v $(pwd)/rules/semgrep:/rules:ro \
  -v $(pwd):/workspace:ro \
  -v artifacts:/artifacts \
  registry.internal/security-platform/spt-semgrep:latest
```
