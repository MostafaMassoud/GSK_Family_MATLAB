# scripts

Helper tooling in PowerShell and MATLAB only (no Python, per the project
contract).

| Script | Language | Purpose |
|---|---|---|
| `build_mex_bridge.ps1` | PowerShell | Build the optional `gskcec_eval` MEX bridge (MATLAB -> ported C++ benchmarks) with a MinGW-w64 C++20 toolchain into `build/mex/`, linked fully static (no MinGW runtime DLL needed at load time). |
| `analyze_results.m` | MATLAB | Toolbox-free statistics + figures over `results/`: per-function generated-vs-reference comparison, Friedman ranks, Wilcoxon signed-rank vs the references, and boxplot/convergence PDFs. |
| `compare_reference_runs.m` | MATLAB | Per-(dimension, function) comparison of two `per_run.csv` sets (e.g. a MATLAB DT-GSK campaign vs the imported Python reference runs): Best/Median/Mean, order-of-magnitude agreement, two-sided Wilcoxon rank-sum at `alpha`, paired signed-rank when the seeds match, Holm-adjusted p-values. Needs the Statistics and Machine Learning Toolbox. |
| `build_docs.ps1` | PowerShell | Generate the HTML documentation site + runbook (Pandoc/Doxygen, no Python) into `docs/html/`. |
| `run_all.ps1` | PowerShell | Build/test wrapper plus batch driver for one or more `configs/*.yml` experiments through `gsk_run` (defaults to `configs/smoke.yml`; seed policy and generator come from each config, falling back to `gsk_run`'s reference + threefry; pass `-SeedPolicy`/`-RandGenerator` only to override every config; use `-Full` for the full standard set). |

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
`docs/html/`. If Pandoc is missing, or older than 3.8 (the script passes
`--syntax-highlighting=none`, added in Pandoc 3.8), the script uses a minimal
fallback renderer and prints a warning naming the version found;
if Doxygen is missing, the C++ API subsite is skipped and a warning is printed.

**Build the MATLAB CEC bridge:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_mex_bridge.ps1
```

If the script reports that it could not replace `build/mex/gskcec_eval.mexw64`,
the bridge is loaded in a MATLAB session: run `gskcec_eval('clear'); clear mex`
there (live problem handles keep the bridge locked in memory) or close MATLAB,
then retry. A locked MEX binary is a Windows file-handle issue, not a C++
compile error.

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

- `_archive/` and `_overwrite_archive/` trees below `results_root` are ignored.
- Each run is compared only with the reference table of its own dimension; with
  no table for that dimension, `reference_mean` is blank and the Wilcoxon row
  reads `insufficient_reference`.
- With `results_root='results'`, both `results/<opt>/<suite>` (written by
  `gsk_run`) and `results/_run_all/<opt>/<suite>` (written by the launchers)
  are read. A duplicate (optimizer, suite, dimension) prints a `WARNING` and is
  labeled by its path (`_run_all/gsk` vs `gsk`). Point `results_root` at one
  layout (e.g. `results/_run_all`) to analyze a single campaign.
- Tie-aware ranks come from a local `rank_with_ties` helper (not `tiedrank`),
  so the "Toolbox-free" claim above holds: no Statistics and Machine Learning
  Toolbox is needed.

**Compare two run sets (e.g. DT-GSK vs its imported reference runs):**

```matlab
addpath('scripts')   % run from the gsk_family project root
report = compare_reference_runs('results/_run_all/dt-gsk/cec2017', ...
    'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv');
```

Each of the two inputs is a `per_run.csv` file or a folder holding
`summary/per_run.csv` or `per_run.csv`; options are `alpha` (0.05), `decades`
(1), `zero_tol` (1e-8), `out` (CSV path for the per-cell table) and `verbose`. For every (dimension, function) cell in both sets it reports
Best/Median/Mean of the per-run errors (raw objectives when there is no
optimum), and the cell verdict is `MATCH` when Median and Mean agree within
`decades` (default 1) orders of magnitude and the two-sided rank-sum test does
not reject at `alpha`, else `DIFFERS`. Duplicate run rows keep the last one
(resume history). The summary line also gives the Holm-adjusted count, since
about `alpha * cells` raw rejections are expected by chance. Unlike
`analyze_results.m`, this script needs the Statistics and Machine Learning
Toolbox (`ranksum`, `signrank`).
