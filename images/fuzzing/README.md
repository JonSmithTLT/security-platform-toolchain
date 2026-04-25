# fuzzing

Coverage-guided fuzzing with **AFL++**.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FUZZ_TARGET` | *(required)* | Path to AFL++-instrumented binary |
| `FUZZ_TIMEOUT` | `300` | Fuzzing wall-clock timeout in seconds |
| `FUZZ_CORPUS` | `/workspace/corpus` | Seed corpus directory |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |
| `AFL_SKIP_CPUFREQ` | `1` | Suppress AFL++ CPU freq warning |

## Security options required

AFL++ adjusts kernel settings at runtime:

```bash
docker run --security-opt seccomp:unconfined ...
# or
docker run --privileged ...
```

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/fuzzing.log
└── results/fuzzing/
    ├── raw/afl-out/           # full AFL++ output directory
    └── evidence/crashes/      # crash inputs (copied for easy access)
```

## Instrumenting a target

```bash
# C example
AFL_USE_ASAN=1 afl-clang-fast -o target_fuzz target.c
```
