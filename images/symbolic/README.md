# symbolic

Symbolic execution using **angr** (default) or **KLEE**.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SYMBOLIC_ENGINE` | `angr` | Engine to use (`angr` \| `klee`) |
| `TARGET_BINARY` | *(required)* | Path to the ELF binary to analyse |
| `SYMBOLIC_TIMEOUT` | `600` | Wall-clock timeout in seconds |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Outputs

```
$ARTIFACTS_DIR/
├── job-report.json
├── logs/symbolic.log
└── results/symbolic/
    └── raw/
        ├── angr-results.json     # angr findings (unconstrained PC, errors)
        └── klee-out/             # KLEE output directory (klee mode)
```

## Notes

* angr performs bounded depth-first state exploration (200 steps by default).
  Increase by editing `angr-explore.py` or override via a custom entrypoint.
* KLEE requires an LLVM bitcode (`.bc`) file — compile with
  `clang -emit-llvm -c target.c -o target.bc`.
* angr is memory-intensive; allocate at least 4 GB for non-trivial binaries.
