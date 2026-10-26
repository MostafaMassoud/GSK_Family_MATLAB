# gsk_family

`gsk_family` is a self-contained hybrid MATLAB/C++ research project around the
Gaining-Sharing Knowledge (GSK) algorithm family and the CEC benchmark suites.

**Start here:** [RUNBOOK.md](../RUNBOOK.md) - prerequisites, your first run step by
step, and parallel runs in MATLAB.

- CEC benchmark suites (CEC2011, CEC2013, CEC2013LSGO, CEC2017, CEC2020)
  are standalone C++20 ports under `benchmarks/` - no MATLAB, R or MEX
  needed to evaluate them.
- The seven GSK-family optimizers (gsk, agsk, apgsk, atmals-gsk, egsk,
  fdb-agsk, dt-gsk) are MATLAB implementations under `src/`, with provenance and
  known behavior differences documented in `docs/`. DT-GSK, the seventh, is a
  MATLAB port of the DT-GSK reference implementation v2.46 (MIT license);
  its record is
  [src/optimizers/dt-gsk/README.md](src/optimizers/dt-gsk/README.md) and its
  algorithm page [docs/algorithms/dt-gsk.md](docs/algorithms/dt-gsk.md).
- Public optimizer IDs, CLI/config names, result folders, and reference folders
  use hyphenated slugs (`atmals-gsk`, `fdb-agsk`, `dt-gsk`). MATLAB entry-point
  function names keep underscores where MATLAB requires valid identifiers, for
  example `atmals_gsk_optimize`, `fdb_agsk_optimize` and `dt_gsk_optimize`.
- The project is MATLAB and C++ only (no other languages or generated
  bindings; helper scripts are PowerShell or MATLAB).

Start with [docs/reference/project_structure.md](docs/reference/project_structure.md) (folder
map), [docs/reference/architecture.md](docs/reference/architecture.md) (layers and execution
model), [docs/reference/benchmark_protocol.md](docs/reference/benchmark_protocol.md)
(budgets/targets/statistics), and
[docs/reference/porting_notes.md](docs/reference/porting_notes.md) (per-suite fidelity record
and preserved reference quirks).

For a publication-quality overview that explains the algorithms, formulas,
worked examples, reproducibility controls, extension points, and common
pitfalls in one place, read
[docs/research/researcher_handbook.md](docs/research/researcher_handbook.md).

## Code Author And Algorithm References

**Code Author:** Mostafa Elsayed Ahmed Masoud, PhD Candidate in Operations
Research, Department of Operations Research, Faculty of Graduate Studies for
Statistical Research, Cairo University, Giza 12613, Egypt

**ORCID:** <https://orcid.org/0009-0003-8415-2158> · **Email:**
<moustafa.masoud@gmail.com>

Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud. Keep this notice and the
author attribution in copies and derivative works (details in
[LICENSES.md](LICENSES.md)).

This repository is a MATLAB/C++ implementation and reproducibility toolkit. If
you use an optimizer in a paper, thesis, benchmark study, or derivative
implementation, cite both this software package and the original algorithm
paper(s) below. The detailed licensing and provenance record is in
[LICENSES.md](LICENSES.md), and machine-readable software metadata is provided
in [CITATION.cff](CITATION.cff) and [codemeta.json](codemeta.json).

| Implemented optimizer | Primary reference paper |
|---|---|
| GSK | Mohamed, A. W.; Hadi, A. A.; Mohamed, A. K. "Gaining-sharing knowledge based algorithm for solving optimization problems: a novel nature-inspired algorithm." *International Journal of Machine Learning and Cybernetics*, 11, 1501-1529, 2020. DOI: [10.1007/s13042-019-01053-x](https://doi.org/10.1007/s13042-019-01053-x). |
| AGSK | Mohamed, A. W.; Hadi, A. A.; Mohamed, A. K.; Awad, N. H. "Evaluating the performance of adaptive gaining-sharing knowledge based algorithm on CEC 2020 benchmark problems." *2020 IEEE Congress on Evolutionary Computation (CEC)*, 1-8, 2020. DOI: [10.1109/CEC48606.2020.9185901](https://doi.org/10.1109/CEC48606.2020.9185901). |
| APGSK | Mohamed, A. W.; Abutarboush, H. F.; Hadi, A. A.; Mohamed, A. K. "Gaining-sharing knowledge based algorithm with adaptive parameters for engineering optimization." *IEEE Access*, 9, 65934-65946, 2021. DOI: [10.1109/ACCESS.2021.3076091](https://doi.org/10.1109/ACCESS.2021.3076091). |
| ATMALS-GSK | Alfadli, N. M.; Oun, E. M.; Mohamed, A. W. "Auto-Tuning Memory-Based Adaptive Local Search Gaining-Sharing Knowledge-Based Algorithm for Solving Optimization Problems." *Algorithms*, 18(7), 398, 2025. DOI: [10.3390/a18070398](https://doi.org/10.3390/a18070398). |
| eGSK | Jawad, M. A.; Roshdy, H. S. M.; Mohamed, A. W. "Enhanced Gaining-Sharing Knowledge-based algorithm." *Results in Control and Optimization*, 19, 100542, 2025. DOI: [10.1016/j.rico.2025.100542](https://doi.org/10.1016/j.rico.2025.100542). |
| FDB-AGSK | Bakir, H.; Duman, S.; Guvenc, U.; Kahraman, H. T. "Improved adaptive gaining-sharing knowledge algorithm with FDB-based guiding mechanism for optimization of optimal reactive power flow problem." *Electrical Engineering*, 105, 3121-3160, 2023. DOI: [10.1007/s00202-023-01803-9](https://doi.org/10.1007/s00202-023-01803-9). |
| DT-GSK | Masoud, M. E. A.; Roshdy, H. S. M.; Mohamed, A. W. "DT-GSK: Dimension-Tiered Adaptive Configuration Selection and Deterministic Refinement for Gaining-Sharing Knowledge-Based Optimization Algorithm." *Algorithms* (MDPI), 19(9), 769, 2026. Reference implementation: DT-GSK v2.46 (MIT license), <https://github.com/MostafaMassoud/DT-GSK>. |

FDB-AGSK also depends conceptually on the Fitness-Distance Balance selection
idea: Kahraman, H. T.; Aras, S.; Gedikli, E. "Fitness-distance balance (FDB): a
new selection method for meta-heuristic search algorithms."
*Knowledge-Based Systems*, 190, 105169, 2020. DOI:
[10.1016/j.knosys.2019.105169](https://doi.org/10.1016/j.knosys.2019.105169).

## Documentation

The full project documentation is a browsable HTML site (generated):

```powershell
powershell -File scripts\build_docs.ps1   # -> docs\html\index.html
```

It assembles every page below into a navigable site with a sidebar, per-page
tables of contents, a separate page per algorithm, diagrams, and the Doxygen
C++ API. The step-by-step **[Command Reference](docs/getting-started/command_reference.md)** (also rendered to HTML)
explains how to run every algorithm from **both** the MATLAB IDE and Windows
Terminal. The Markdown sources are the source of truth; the site is rebuildable
at any time.

New here? To set up and run, start with [RUNBOOK.md](../RUNBOOK.md). To
understand the project, read in this order:

1. [docs/getting-started/explainer.md](docs/getting-started/explainer.md) - plain-language
   "what is this and why," for a reader with no background in GSK, the CEC
   benchmarks, C++, or MATLAB. Includes the GSK idea, the benchmark suites,
   what this toolkit uniquely provides, and conceptual diagrams.
2. [docs/research/researcher_handbook.md](docs/research/researcher_handbook.md) - the
   researcher handbook: mathematical notation, algorithm intuition, worked
   numerical examples, design decisions, limitations, and safe extension
   guidance.
3. [docs/getting-started/tutorial.md](docs/getting-started/tutorial.md) - one end-to-end worked example:
   build, run the C++ tests, validate a suite, run a tiny experiment, read
   every output file, and interpret the CONSISTENT/DEVIATES verdict.
4. [docs/development/code_reading_guide.md](docs/development/code_reading_guide.md) - the guided
   tour of the code: where to start and how the MATLAB and C++ halves
   connect.
5. [docs/reference/glossary.md](docs/reference/glossary.md) - concise definitions of every term
   and acronym (GSK, AGSK, CEC2017, KF/KR/K, nfes, Wilcoxon, CONSISTENT, ...).
6. [docs/reference/api.md](docs/reference/api.md) - how to generate the C++ API reference with
   Doxygen (`doxygen docs/Doxyfile`); MATLAB optimizers are documented via
   their in-file help blocks plus
   [docs/reference/matlab_interface.md](docs/reference/matlab_interface.md).

Reference docs (consult as needed):
[docs/reference/architecture.md](docs/reference/architecture.md) (layers and execution model),
[docs/reference/project_structure.md](docs/reference/project_structure.md) (folder map),
[docs/reference/benchmark_protocol.md](docs/reference/benchmark_protocol.md)
(budgets/targets/statistics per suite),
[docs/reference/seed_policy.md](docs/reference/seed_policy.md) (reference/unified/native/derived
seed and RNG rules),
[docs/reference/result_schema.md](docs/reference/result_schema.md) (output file/column
definitions),
[docs/reference/matlab_interface.md](docs/reference/matlab_interface.md) (the MATLAB optimizer
contract), and
[docs/reference/porting_notes.md](docs/reference/porting_notes.md) (per-suite fidelity record
and preserved reference quirks).

For future agent-driven reviews, use
[docs/prompts/REVIEW_PROMPT.md](docs/prompts/REVIEW_PROMPT.md) for full
code/reproducibility/performance work,
[docs/prompts/DOCS_DEEP_REVIEW_PROMPT.md](docs/prompts/DOCS_DEEP_REVIEW_PROMPT.md) for
documentation expansion, or
[docs/prompts/documentation_review_prompt.md](docs/prompts/documentation_review_prompt.md) for
documentation-only cleanup. The older
[docs/prompts/llm_review_prompt.md](docs/prompts/llm_review_prompt.md) remains
available for compatibility with previous review workflows. All prompts are
aligned with the current repository layout and cleanup policy.

License and provenance are tracked in [LICENSES.md](LICENSES.md), including
the component-by-component GPL-3.0-or-later compatibility analysis. This
project intentionally keeps that single licensing record instead of a
separate root `LICENSE` file.

## Build (C++ tooling)

Requires CMake >= 3.20 and a C++20 compiler. The project is developed with
WinLibs MinGW-w64 GCC. For a copy-paste checklist that includes prerequisites,
C++ validation, the MATLAB MEX bridge, and the root `run_all_cec*.m` launchers,
see `build.txt` in this folder and `..\build.txt` beside the launchers. With
the toolchain on PATH:

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

(If `cmake`/`g++` are not on PATH, pass their full paths, e.g.
`-DCMAKE_CXX_COMPILER=<...>\mingw64\bin\g++.exe` and use
`<...>\mingw64\bin\cmake.exe`/`ctest.exe`. MATLAB also bundles a usable
CMake at `<matlabroot>\bin\win64\cmake\bin\cmake.exe`.)

The test suite validates every port against committed ground-truth data under
`benchmarks/cec_suite_cpp/cec_tools/tests/data/`.
Rebuild this C++ tree after any change to `CMakeLists.txt`, C++ headers or
sources under `benchmarks/cec_suite_cpp/cec_tools/`, suite ports under
`benchmarks/cec_suite_cpp/*/src/`, CLI/config parser code, comparison logic, or C++
tests. A stale `build\gsk_run.exe`, `build\gsk_validate.exe`, or
`build\gsk_list.exe` can keep old behavior even when the source is current, so
rerun `ctest --test-dir build --output-on-failure` after rebuilding.

## CLI

```powershell
build\gsk_list.exe --benchmarks
build\gsk_list.exe --optimizers
build\gsk_list.exe --references benchmarks\cec_reference_results

build\gsk_validate.exe --references benchmarks\cec_reference_results
build\gsk_validate.exe --suite cec2017 --smoke
build\gsk_validate.exe --suite cec2020 --smoke
build\gsk_validate.exe --suite cec2013 --smoke
build\gsk_validate.exe --suite cec2013 --against saved_vectors
build\gsk_validate.exe --suite cec2013lsgo --smoke
build\gsk_validate.exe --suite cec2011 --smoke
build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
```

## Running experiments

Experiments execute MATLAB optimizers against the ported C++ benchmarks
through the `gskcec_eval` MEX bridge. Build it before running any CEC MATLAB
experiment (needs MATLAB and the MinGW toolchain):

```powershell
powershell -File scripts\build_mex_bridge.ps1
```

This creates `build\mex\gskcec_eval.mexw64`, linked fully static (no MinGW
runtime DLL is needed on PATH when MATLAB loads it). The root `run_all_cec*.m`
launchers (and `run_experiment` for CEC suites) check that this project-local
file exists and actually loads before starting, and stop with a build hint if it
is missing (`gskcec:mexMissingPrerequisite`) or cannot be loaded (`gskcec:mexNotLoadable`),
preventing partial all-skipped result folders.
Rebuild this MEX bridge after changes to CEC suite source files or
`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/`; MATLAB CEC experiments use
`build\mex\gskcec_eval.<mexext>`, not the C++ CLI executables.

Then either through the orchestrator:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
build\gsk_run.exe --optimizer gsk --suite cec2017 --dimension 10 --function 1 --runs 3 --seed 20240620
build\gsk_run.exe --config configs\all_cec2017.yml --root .     # full CEC2017 matrix
build\gsk_run.exe --config configs\all_cec2011.yml --root .     # full CEC2011 matrix
build\gsk_run.exe --config configs\agsk_cec2020.yml --root .    # AGSK on CEC2020
build\gsk_run.exe --optimizer dt-gsk --suite cec2017 --dimension 10 --function 1 --runs 3 --seed 20240620
```

(`--dry-run` prints the MATLAB invocations; MATLAB is found via
`--matlab <exe>`, the `GSKCEC_MATLAB` environment variable, or PATH. The
orchestrator defaults to `--seed-policy reference --rand-generator threefry`;
reference mode overrides the effective generator for AGSK, APGSK, FDB-AGSK,
eGSK, and ATMALS-GSK to the legacy `seed` stream; GSK remains on `twister`.)
For new fair cross-family experiments, use `--seed-policy unified`; that mode
uses the same `(dimension,function,run)` seed for every optimizer, draws the
initial population once in the runner, restores the post-initialization RNG
state inside each optimizer, and uses `threefry` when MATLAB supports it
(otherwise `twister`) for the whole family.
DT-GSK is unified-only: under every `--seed-policy` it is scheduled with the
unified seed and `threefry` (as in its reference campaign), and it
samples its own `NP = 5*D` initial population instead of the runner's `X0`
(the documented fair-start exception).
The unified seed formula is:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

The formula intentionally excludes optimizer name, optimizer index,
population size, budget, and suite name. The default base seed is centralized
inside `run_experiment.m` as `20240620`, so the root `run_all_cec*.m` launchers
all use one shared campaign anchor. Full details, including reference-mode
exceptions and the fair-start `X0` protocol, are in
[docs/reference/seed_policy.md](docs/reference/seed_policy.md).

or directly from MATLAB:

```matlab
cd src/runners
run_experiment('optimizer','gsk','suite','cec2017','functions',[1 3], ...
               'dimensions',[10],'runs',3,'base_seed',20240620,'max_nfes',0, ...
               'project_root','<this folder>','output_dir','<this folder>/results/demo', ...
               'overwrite',true,'seed_policy','reference','rand_generator','threefry', ...
               'use_parallel',false,'write_graphs',false)
```

Outputs land under `results/<optimizer>/<suite>/` in the CEC-competition
layout - `summary/` (per-dimension `Function,Best,Median,Mean,Worst,SD`
tables + `per_run.csv` + `environment.json`), `curves/` (median-run
convergence traces; optional `curves/graphs/` PNGs when `write_graphs=true`)
and `gen_logs/` (per-run checkpoint errors); see
[docs/reference/result_schema.md](docs/reference/result_schema.md). Generated results never
overwrite the imported reference tables or curated benchmark-side convergence
assets under `benchmarks/cec_reference_results` (`run_experiment` refuses any
`output_dir` inside that tree with `run_experiment:outputUnsafe`).
Existing result directories are preserved on rerun: completed run ids are
skipped only when their stored seed, budget (`max_nfes`) and generator still
match the active run, missing or stale runs are appended, and refreshed
fixed-name summaries/metadata are archived under `_archive/<timestamp>/` before
being rewritten.
This means an old result row produced under a previous seed policy, budget, or
generator stays available for audit history, but it is not treated as complete
for the current run.
Set `overwrite=true` when you need a clean replacement run; the previous active
result tree is moved to `_overwrite_archive/<suite>_<timestamp>/` beside the
suite folder before new files are written.

Every `gsk_run` automatically compares the run against the same optimizer's
published reference table and writes a `verification.json` verdict
(`CONSISTENT`/`DEVIATES`) into the run directory - so each run carries proof
it reproduces published behavior. If `verification.json` already exists, the
next verdict is written as `verification_1.json`, `verification_2.json`, etc.
`gsk_run` exits nonzero on `DEVIATES`;
opt out with `--no-verify`, or re-check a directory with
`gsk_validate --verify <run_dir> benchmarks\cec_reference_results`.

For a run-level check, `scripts/compare_reference_runs.m` compares two
`per_run.csv` sets per (dimension, function) with Wilcoxon rank-sum tests and
Holm-adjusted p-values (needs the Statistics and Machine Learning Toolbox); see
[scripts/README.md](scripts/README.md). The DT-GSK port was verified against the
unmodified reference implementation on identical random numbers and reproduces its
golden values; the validation and the CEC2017 campaign results are recorded in
[src/optimizers/dt-gsk/README.md](src/optimizers/dt-gsk/README.md).

## MATLAB tests

```powershell
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
```

runs the 13 optimizer/common-helper/runner smoke tests (one per optimizer,
including `test_dt_gsk_smoke.m`) on pure-MATLAB problems (no MEX bridge
required).

## CEC layout

```text
benchmarks\cec_reference_results  imported reference tables + curated curves/graphs/logs (read-only)
benchmarks\cec_suite_cpp       CEC suite C++ ports and input data
benchmarks\cec_suite_cpp\cec_tools       C++ CEC helper library, CLIs, and tests
```

`CEC2013` (converted from the CEC2013 R package) and `CEC2013LSGO` are
separate suites and are never merged.

## Source boundary

Do not import external GSK or CEC implementations into the active tree.
Behavior gaps and preserved quirks are documented in `docs/reference/porting_notes.md`
rather than invented. Project-specific agent instructions: [SKILL.md](SKILL.md).
