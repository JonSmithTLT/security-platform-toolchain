# secrets

Detects secrets and credentials using **Gitleaks** and **TruffleHog**.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_REPO` | `/workspace` | Source directory to scan |
| `SECRETS_TOOLS` | `gitleaks,trufflehog` | Comma-separated list of tools to run |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json        # status=failure if any secrets found
├── logs/secrets.log
└── results/secrets/
    └── raw/
        ├── gitleaks.json     # Gitleaks JSON report
        └── trufflehog.jsonl  # TruffleHog JSONL stream
```

## Exit behaviour

The job report `status` is set to `failure` if **any** finding is emitted by
either scanner.  Use this to gate CI pipelines.
