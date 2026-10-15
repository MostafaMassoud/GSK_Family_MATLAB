# scripts

Helper tooling in PowerShell and MATLAB only (no Python, per the project
contract).

| Script | Language | Purpose |
|---|---|---|
| `build_mex_bridge.ps1` | PowerShell | Build the optional `gskcec_eval` MEX bridge (MATLAB -> ported C++ benchmarks) with a MinGW-w64 C++20 toolchain into `build/mex/`. |
| `analyze_results.m` | MATLAB | Toolbox-free statistics + figures over `results/`: per-function generated-vs-reference comparison, Friedman ranks, Wilcoxon signed-rank vs the references, and boxplot/convergence PDFs. |
| `build_docs.ps1` | PowerShell | Generate the HTML documentation site + runbook (Pandoc/Doxygen, no Python) into `docs/html/`. |
| `run_all.ps1` | PowerShell | Build/test wrapper plus batch driver for one or more `configs/*.yml` experiments through `gsk_run` (defaults to `configs/smoke.yml` with `-SeedPolicy reference -RandGenerator threefry`; use `-Full` for the full standard set). |

Rebuild the C++ CLIs with `cmake --build build -j` after editing C++ sources,
headers, CLI/config parser code, tests, or `CMakeLists.txt`, then run
`ctest --test-dir build --output-on-failure`. Rebuild the MEX bridge with
`build_mex_bridge.ps1` after CEC suite source or MEX bridge changes before
running MATLAB CEC experiments.

The expected-value and bounds data used by the C++ tests is committed under
`benchmarks/cec_suite_cpp/cec_tools/tests/data/`. The external regeneration archive
is not part of this project, so scripts that depend on a removed local
reference folder are intentionally not kept here.

## Typical workflows

**Build documentation:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_docs.ps1 -Clean
```

Reads Markdown sources from `docs/` and writes the generated site to
`docs/html/`. If Pandoc is missing, the script uses a minimal fallback renderer;
if Doxygen is missing, the C++ API subsite is skipped and a warning is printed.

**Build the MATLAB CEC bridge:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_mex_bridge.ps1
```

Close MATLAB first if `build/mex/gskcec_eval.mexw64` is locked. A locked MEX
binary is a Windows file-handle issue, not a C++ compile error.

**Analyze completed results:**

```matlab
addpath('scripts')   % run from the gsk_family project root
analyze_results('project_root','.', ...
                'results_root','results', ...
                'reference_root','benchmarks/cec_reference_results', ...
                'output_dir','results/analysis')
```

This script is for post-processing. It never repairs missing runs or edits
reference tables; missing data is reported rather than invented.
