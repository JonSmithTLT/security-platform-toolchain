# schema-validator

Validates SPT artifacts against the schemas bundled in the base image.

## Inputs

| Variable | Default | Purpose |
|----------|---------|---------|
| `VALIDATE_TARGET` | `/artifacts` | Artifact directory or a single JSON file to validate |
| `SCHEMAS_DIR` | `/usr/local/share/spt/schemas` | Directory containing SPT JSON schemas |
| `ARTIFACTS_DIR` | `/artifacts` | Output artifact directory |

## Outputs

```text
logs/schema-validator.log
results/schema-validator/raw/validation-summary.json
results/schema-validator/tool-result.json
job-report.json
```
