# benchmarks/cec_suite_cpp

**This folder vs the other two:** `cec_suite_cpp` holds **the benchmark problems
themselves** - the standalone C++ ports of the CEC functions and their input
data, plus the nested `cec_tools` helper library, CLIs, MEX bridge, and tests
that drive the suites. `cec_reference_results` holds *published result tables
we compare against*.

One subfolder per suite, each with `src/` (the C++ port) and `input_data/`
(rotation/shift/shuffle files and converted assets):

```text
cec2011/src/      cec2011/input_data/        22 real-world problems
cec2013/src/      cec2013/input_data/        standard 28-function suite
cec2013lsgo/src/  cec2013lsgo/input_data/    large-scale (15 functions)
cec2017/src/      cec2017/input_data/        30 functions
cec2020/src/      cec2020/input_data/        10 functions
cec_tools/        include/, src/, tests/     C++ helper library and CLIs
```

All five suites are ported to standalone C++20 and validated against committed
ground-truth data (see `docs/reference/porting_notes.md`). Provenance is summarized in
the suite headers and `docs/reference/reference_inventory.md`.

Do not place MATLAB/R/C-only/Python/Cython files here (the language-contract
check forbids `*.m`, `*.R`, `*.c`, `*.py`, `*.pyx` under `cec_suite_cpp`), and do
not put GSK optimizer code here - that lives under `src/`.

## Change-impact checklist

| Change | Required verification |
|---|---|
| Edit a suite source file under `cec2011/src`, `cec2017/src`, etc. | Rebuild C++ with `cmake --build build -j`, run `ctest --test-dir build --output-on-failure`, rebuild the MEX bridge before MATLAB CEC runs. |
| Edit `cec_tools/include` or `cec_tools/src` | Rebuild C++ CLIs/tests and rerun CTest. Rebuild MEX if the MEX bridge or benchmark ABI is affected. |
| Edit input data | Treat as a benchmark-port change; rerun all affected suite tests and document provenance in `docs/reference/reference_inventory.md`. |
| Add a new suite | Add factory support, suite metadata, tests, docs, and result-schema notes before exposing it in runners. |

The C++ tests use committed deterministic point sets, not random smoke checks.
That makes them suitable for detecting tiny porting regressions in benchmark
values, bounds, optima, and reference quirks.
