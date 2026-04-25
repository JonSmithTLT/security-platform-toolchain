# replay-runner

Replays fuzzing **crash inputs** and **PoC files** against a target binary to
confirm reproducibility and collect crash metadata.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REPLAY_TARGET` | *(required)* | Path to the target binary |
| `CRASH_DIR` | `/workspace/crashes` | Directory of crash/PoC inputs |
| `REPLAY_TIMEOUT` | `30` | Per-replay timeout in seconds |
| `REPLAY_USE_VALGRIND` | `0` | Set to `1` to run under Valgrind |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json          # status=failure if any crash reproduced
├── logs/                    # (captured by entrypoint)
└── results/replay-runner/
    ├── raw/replay-results.json   # per-crash JSON records
    └── evidence/                 # copies of reproduced crash inputs
```

## Tips

* Build your target with AddressSanitizer (`-fsanitize=address`) for richer
  crash output.
* Mount the AFL++ `crashes/` directory from a previous fuzzing run as
  `CRASH_DIR`.
