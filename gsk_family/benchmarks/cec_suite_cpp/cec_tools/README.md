# CEC Tools

This folder contains C++ support code for CEC-related work only.

```text
include/gskcec/  public C++ headers (core/, benchmark/, experiment/)
src/benchmark/   data loading, suite factory, reference-result loader
src/experiment/  config parser, results-vs-reference comparison
src/cli/         gsk_list, gsk_validate, gsk_run, and gsk_bench (timing harness)
src/mex_bridge/  optional gskcec_eval MEX bridge (built by
                 scripts/build_mex_bridge.ps1; the library itself is MEX-free)
tests/unit/      C++ unit tests for the ports and tooling
tests/cli/       CLI exit-code test (ctest gskcec_cli_exit_codes): fake_matlab.cpp
                 stub MATLAB + gsk_run_exit_codes.cmake (cmake -P script)
tests/data/      ground-truth probe points and expected values (generated
                 from the ORIGINAL reference implementations; the generator
                 scripts are not bundled - see each file's header;
                 cec2013_regression.csv is a
                 self-generated regression baseline, clearly marked)
```

Suite evaluator implementations live next to their data under
`benchmarks/cec_suite_cpp/<suite>/src`; this folder holds everything shared.

After changing code in this folder, rebuild the C++ tree from the project root:

```powershell
cmake --build build -j
ctest --test-dir build --output-on-failure
```

If the change affects `src/mex_bridge/` or suite source files used by MATLAB,
also rebuild `build\mex\gskcec_eval.<mexext>` with
`scripts\build_mex_bridge.ps1`.

Do not put MATLAB GSK optimizer code here. GSK-family algorithms belong under
`src/`.
