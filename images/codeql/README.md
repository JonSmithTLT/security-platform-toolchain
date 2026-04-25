# codeql

Runs **GitHub CodeQL** database creation and query analysis.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_REPO` | `/workspace` | Source tree to analyse |
| `CODEQL_LANGUAGE` | `cpp` | Language pack (`cpp`, `java`, `python`, `javascript`, `go`, `csharp`, `ruby`) |
| `CODEQL_QUERIES` | `/queries` | QL queries directory or suite |
| `CODEQL_DB` | `/tmp/codeql-db` | Ephemeral database path |
| `CODEQL_BUILD_CMD` | — | Custom build command for compiled languages |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/codeql.log
└── results/codeql/
    └── raw/codeql.sarif          # SARIF v2.1 results
```

## Custom queries

Mount your QL files to `/queries`:

```bash
docker run --rm \
  -v $(pwd)/queries/codeql:/queries:ro \
  -v $(pwd):/workspace:ro \
  -v artifacts:/artifacts \
  ghcr.io/jonsmithtlt/spt-codeql:latest
```
