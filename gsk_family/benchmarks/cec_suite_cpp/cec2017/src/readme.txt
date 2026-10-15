CEC2017 provenance note
=======================

This folder contains the original CEC2017 `cec17_func.cpp` provenance copy and
the project-maintained standalone C++20 port `cec2017_problem.cpp`.

The old CEC distribution expected users to compile `cec17_func.cpp` directly as
a MATLAB MEX file. That is not the current project workflow. In this repository:

1. `cec17_func.cpp` is retained for provenance and comparison only.
2. `cec2017_problem.cpp` is the active standalone C++ implementation.
3. MATLAB experiments call the unified project MEX bridge
   `build/mex/gskcec_eval.<mexext>`, not a suite-local `cec17_func` MEX.
4. CEC2017 F2 is implemented and tested, but root publication-comparison
   launchers exclude it by default to match the reference protocol.

Current build commands, run from the `gsk_family` directory:

cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_mex_bridge.ps1

Validation lives in:

- `benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2017_tests.cpp`
- `benchmarks/cec_suite_cpp/cec_tools/tests/data/cec2017_expected.csv`
- `docs/reference/benchmark_protocol.md`
- `docs/reference/porting_notes.md`

