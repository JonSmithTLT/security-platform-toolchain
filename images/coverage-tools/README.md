# coverage-tools

Collects offline coverage artifacts using `gcovr`, `lcov`, and LLVM tools.

If `.gcda` files are present under `COVERAGE_ROOT`, the image emits gcovr JSON
and XML plus lcov trace data. If no coverage files exist, it emits an empty
valid coverage result so pipelines stay deterministic.
