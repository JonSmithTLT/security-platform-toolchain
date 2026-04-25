# corpus-tools

Fuzzing corpus management: **minimise**, **deduplicate**, and **merge** corpora.

## Modes (`CORPUS_MODE`)

| Mode | Description |
|------|-------------|
| `minimise` | Use `afl-cmin` to reduce corpus to the smallest set with equivalent coverage |
| `merge` | `rsync`-merge multiple corpus directories |
| `deduplicate` | Remove byte-for-byte duplicate files |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CORPUS_MODE` | `minimise` | Operation to perform |
| `CORPUS_DIR` | `/workspace/corpus` | Input corpus directory |
| `CORPUS_OUT` | `/artifacts/corpus-out` | Output directory |
| `CORPUS_TARGET` | — | Instrumented binary (required for `minimise`) |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/corpus-tools.log
└── corpus-out/     # processed corpus files
```
