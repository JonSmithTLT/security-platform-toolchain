# fuzzing

Coverage-guided compiled harness fuzzing with **AFL++** and **libFuzzer**.
`honggfuzz` is installed but experimental in v0.1.1.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FUZZ_ENGINE` | `afl` | `afl`, `libfuzzer`, or `honggfuzz` |
| `FUZZ_TARGET` | *(required)* | Path to AFL++-instrumented binary |
| `FUZZ_TIMEOUT` | `300` | Fuzzing wall-clock timeout in seconds |
| `FUZZ_CORPUS` | `/workspace/corpus` | Seed corpus directory |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |
| `AFL_SKIP_CPUFREQ` | `1` | Suppress AFL++ CPU freq warning |
| `SPT_ASAN_OPTIONS_AFL` | `abort_on_error=1:symbolize=0:detect_leaks=0` | AFL++-compatible ASAN options |
| `SPT_ASAN_OPTIONS_SYMBOLIZED` | `abort_on_error=1:symbolize=1:detect_leaks=0` | Symbolized ASAN options for libFuzzer/replay |
| `HONGGFUZZ_REF` | `master` | Connected-build source ref for `google/honggfuzz` |

## Engine Status

| Engine | Status |
| --- | --- |
| `afl` | First-class, release-gating smoke |
| `libfuzzer` | First-class, release-gating smoke |
| `honggfuzz` | Installed, experimental hooks only |

`FUZZ_ENGINE=honggfuzz` is accepted and the wrapper path exists. It reserves the
standard artifact layout and emits `engine_status=experimental`. The image
builds and installs `google/honggfuzz` from source, but the release-gating
workflow still treats AFL++ and libFuzzer as the first-class engines for
v0.1.1.

Honggfuzz should become first-class only after its wrapper, smoke fixture, crash
collection, replay metadata, normalized outputs, and docs meet the same bar as
AFL++ and libFuzzer.

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
    ├── raw/afl-out/ or raw/libfuzzer-out/
    ├── evidence/crashes/
    ├── normalized/fuzz-campaign.json
    ├── normalized/crashes.json
    └── reports/fuzz-summary.md
```

## Instrumenting a target

```bash
# C example
AFL_USE_ASAN=1 afl-clang-fast -o target_fuzz target.c

# libFuzzer example
clang -g -O1 -fsanitize=fuzzer,address,undefined -o target_fuzz target.c
```
