# c-cpp-analysis

C/C++ analysis toolset covering **clang-tidy**, **cppcheck**, **sanitizers**
(ASan, UBSan, TSan), **scan-build**, **Valgrind/Helgrind**, compiler hardening
flags, and **libFuzzer** integration.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_REPO` | `/workspace` | Path to checked-out source tree |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |
| `CPPCHECK_SEVERITY` | `warning` | Minimum cppcheck severity (`information`, `warning`, `error`) |
| `CLANG_TIDY_CHECKS` | `-*,clang-analyzer-*,cert-*,bugprone-*` | Clang-tidy check pattern |
| `JOB_ID` | `unknown` | Pipeline run identifier |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/c-cpp-analysis.log
└── results/c-cpp-analysis/
    └── raw/
        ├── cppcheck.xml
        └── clang-tidy.txt        # only if compile_commands.json present
```

## Notes

* `clang-tidy` requires a `compile_commands.json` in `TARGET_REPO`.
  Generate one with `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` or `bear make`.
* The image runs as the non-root `spt` user.
