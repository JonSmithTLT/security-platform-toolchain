# result-normalizers

Converts common raw tool output into the shared SPT `tool-result.schema.json`.

## Supported Inputs

| Format | Files |
|--------|-------|
| Semgrep JSON | `*/raw/semgrep.json` |
| SARIF / CodeQL SARIF | `*/raw/*.sarif` |
| Gitleaks JSON | `*/raw/gitleaks.json` |
| TruffleHog JSONL | `*/raw/trufflehog.jsonl` |
| OSV JSON | `*/raw/*osv*.json` |
| Sanitizer logs | `*/raw/*sanitizer*.log`, `*/raw/*sanitizer*.txt` |
| Valgrind XML/text | `*/raw/*valgrind*.xml`, `*/raw/*valgrind*.log`, `*/raw/*valgrind*.txt` |
| AFL crashes | `*/raw/afl-out/*/crashes/id*` |

## Inputs

| Variable | Default | Purpose |
|----------|---------|---------|
| `NORMALIZER_INPUT` | `/artifacts/results` | Raw result file or results directory |
| `NORMALIZER_FORMAT` | `auto` | `auto`, `semgrep`, `sarif`, `codeql`, `gitleaks`, `trufflehog`, or `osv` |
| `NORMALIZER_OUTPUT` | empty | Explicit output path when normalizing one file |
| `NORMALIZER_SARIF_OUTPUT` | empty | Explicit SARIF projection output path; defaults to `results/result-normalizers/normalized/result-normalizers.sarif` |
| `ARTIFACTS_DIR` | `/artifacts` | Output artifact directory |

## Outputs

When scanning an artifact directory, normalised files are written next to each
tool's raw directory:

```text
results/<tool>/tool-result.json
results/result-normalizers/raw/normalization-summary.json
results/result-normalizers/normalized/result-normalizers.sarif
results/result-normalizers/tool-result.json
logs/result-normalizers.log
job-report.json
```

SARIF output is a projection from SPT `tool-result.json`; it is meant for
handoff to SARIF-native consumers and is not the internal authority model.
