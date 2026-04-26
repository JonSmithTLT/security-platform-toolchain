# harness-builder

Generates, builds, validates, smokes, and packages fuzz harness skeletons.

Supported first-class templates:

- `afl-c`
- `libfuzzer-c`

Reserved template slots:

- `honggfuzz-c`
- `unit-derived`
- `parser-file`
- `packet-replay`
- `boofuzz-protocol`

Key variables:

| Variable | Default | Description |
| --- | --- | --- |
| `HARNESS_ENGINE` | `libfuzzer` | `afl` or `libfuzzer` |
| `HARNESS_NAME` | `spt_harness` | Output binary name |
| `HARNESS_TEMPLATE` | `${HARNESS_ENGINE}-c` | Template directory |
| `HARNESS_WORK_DIR` | `/artifacts/results/harness-builder/raw/generated` | Generated source directory |
| `HARNESS_BUILD_DIR` | `/artifacts/results/harness-builder/raw/build` | Build output directory |
