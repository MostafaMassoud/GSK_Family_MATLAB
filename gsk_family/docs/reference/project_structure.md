# Project Structure

> **What this is:** A map of the `gsk_family` repository -- which folder owns
> what, and where a new file belongs. The tree is split by language: MATLAB
> GSK-family optimizers in `src/`, standalone C++20 CEC ports and tooling in
> `benchmarks/`, joined only by the optional `gskcec_eval` MEX bridge.
> **For:** anyone navigating the source tree or
> deciding where to add a file. **Prerequisites:** none.
> **After reading:** you can predict the location of any file from its purpose
> and know which folders are generated (and gitignored).

This repository is intentionally split by language and responsibility.

```text
GSK_Family_MATLAB/        repository root
  README.md               short overview and where to start
  RUNBOOK.md, RUNBOOK.html  beginner runbook: prerequisites, first run, parallel runs
  run_all_cec*.m          launchers, one per CEC suite (open in MATLAB, press Run)
  build.txt               build commands, run from the repository root
gsk_family/
  CMakeLists.txt          C++ build entry point for CEC tooling
  README.md               project overview and quick commands
  LICENSES.md             provenance and license notes
  benchmarks/             all CEC benchmark assets, C++ CEC tools, and CEC tests
  configs/                experiment configurations (strict flat YAML subset)
  docs/                   project documentation
  scripts/                PowerShell and MATLAB helper scripts
  SKILL.md                project-local agent skill instructions
  src/                    MATLAB GSK-family optimizer implementations
  build/                  CMake build tree + build/mex/gskcec_eval.mexw64 (generated)
  results/                generated experiment outputs (created on first run);
                          CEC-competition layout results/<optimizer>/<suite>/{summary,curves,gen_logs}
```

The structure is intentionally shallow: the tree above is the *ceiling* of
complexity, reviewed for simplicity so a newcomer can predict where any file
lives from its purpose. Generated trees (`build/`, `results/`) are gitignored.

## CEC Benchmark Folders

| Folder | One-line distinction |
|---|---|
| `benchmarks/cec_reference_results` | **Imported, read-only reference evidence** we compare against: aggregate result tables plus curated convergence `curves/`, `curves/graphs/`, and `gen_logs/` assets. Data only, never code, never written by a normal run. |
| `benchmarks/cec_suite_cpp` | **The benchmark problems themselves** - the C++ function ports and their `input_data`. |
| `benchmarks/cec_suite_cpp/cec_tools` | **The C++ library, CLIs, MEX bridge and tests** that drive and validate the suites. |

## Where does a new file go?

- A GSK-family optimizer or MATLAB helper/runner/test -> `src/...`
- A CEC benchmark function port or its input data -> `benchmarks/cec_suite_cpp/<suite>/...`
- C++ support code, a CLI, the MEX bridge, or a C++ test -> `benchmarks/cec_suite_cpp/cec_tools/...`
- An imported published reference table or curated reference convergence asset -> `benchmarks/cec_reference_results/...` (never edit during a run)
- A generated experiment result -> `results/...` (never under `benchmarks/`)
- A PowerShell or MATLAB helper script -> `scripts/...`
- An experiment configuration -> `configs/...`
- Documentation -> `docs/...`

If a file could plausibly fit two places, the receiving folder's `README.md`
states which wins and why.

## Language Contract

| Area | Language | Rule |
|---|---|---|
| CEC benchmark implementation | C++ | Keep source and input data under `benchmarks/cec_suite_cpp`. |
| CEC reference result tables and curated convergence assets | CSV/TXT/PNG | Keep imported tables plus curated benchmark-side `curves/`, `curves/graphs/`, and `gen_logs/` under `benchmarks/cec_reference_results`. |
| CEC tooling, CLIs, and tests | C++ | Keep all CEC support code under `benchmarks/cec_suite_cpp/cec_tools`. |
| GSK-family optimizers | MATLAB | Keep implementations under `src`. |
| Tooling scripts | PowerShell, MATLAB, or C++ | Do not add other languages. |

Files, wrappers, generated bindings, and package dependencies in any other
language are not allowed in this project.

## Benchmarks

```text
benchmarks/
  README.md
  cec_reference_results/         imported reference tables and curated convergence assets
  cec_suite_cpp/                    CEC C++ ports, input data, and support tools
    cec_tools/                  C++ CEC helper library, CLIs, and tests
```

`cec_reference_results` is read-only reference material. Its suite/optimizer
subfolders may contain aggregate reference tables plus curated `curves/`,
`curves/graphs/`, and `gen_logs/` assets kept for future convergence-graph
generation. Generated experiment results go under `results/` and must not
overwrite imported reference tables or curated reference trajectories.

`cec_suite_cpp` is the only place for CEC benchmark source, input data, and CEC
support tools. Do not place CEC code under `src/`, `src/benchmark/cec*`, or
root-level `data/cec*`.

`cec_tools` owns all C++ utility code that supports CEC work:

```text
benchmarks/cec_suite_cpp/cec_tools/
  include/gskcec/         public C++ headers (core/, benchmark/, experiment/)
  src/benchmark/          data loading, factory, reference-result loader
  src/experiment/         config parser, results-vs-reference comparison
  src/cli/                gsk_list, gsk_validate, gsk_run, gsk_bench
  src/mex_bridge/         optional gskcec_eval MEX bridge source
  tests/unit/             C++ unit tests for ports and tooling
  tests/cli/              CLI exit-code test (stub MATLAB + gsk_run_exit_codes.cmake)
  tests/data/             ground-truth probe points and expected values
```

## GSK MATLAB Source

```text
src/
  README.md
  common/                 shared MATLAB GSK helper functions
  optimizers/             GSK-family MATLAB implementations
    gsk/
    agsk/
    apgsk/
    atmals-gsk/
    egsk/
    fdb-agsk/
    dt-gsk/               dt_gsk_optimize.m, dt_gsk_config.m,
                          dt_gsk_graph.m, README.md
  experiments/            MATLAB experiment definitions (default matrix)
  runners/                MATLAB runner entry points (run_experiment,
                          gskcec_make_problem, get_cec_seed,
                          derive_run_seed, unified_run_seed wrapper)
  tests/                  MATLAB smoke tests + run_matlab_smoke_tests driver
```

`src` is MATLAB-only in this project. MATLAB provenance notes belong in local
README/help text and `docs/reference/porting_notes.md`. Do not put CEC suite code, CEC
input data, or C++ CEC tooling under `src`. `src/optimizers/dt-gsk/README.md` is
the authoritative summary of DT-GSK's behavior and validation.

## Documentation

Documentation is organized into topic folders; `scripts/build_docs.ps1` renders
the Markdown into `docs/html`.

```text
docs/
  index.md                documentation landing page
  getting-started/        explainer, tutorial, command_reference, configuration,
                          user guide, troubleshooting
  reference/              this map (project_structure.md), architecture,
                          benchmark_protocol, porting_notes, cec2011_port_plan,
                          reference_inventory, seed_policy, result_schema,
                          matlab_interface, api, glossary, diagrams,
                          benchmark_mapping, module_dependencies, workflows
  development/            code_reading_guide, contributor/developer/extension/
                          maintenance guides
  research/               researcher_handbook, performance, reproducibility,
                          numerical_examples, validation_report
  algorithms/             one page per optimizer (gsk, agsk, apgsk,
                          atmals-gsk, egsk, fdb-agsk, dt-gsk)
  prompts/                maintained prompts for agent and documentation reviews
```

## Skills

```text
SKILL.md
```

This is a project-local instruction file for agents working on this repository.
It reinforces the same language and folder boundaries as this document.

## File-level responsibilities

| File or pattern | Responsibility | Research impact |
|---|---|---|
| `run_all_cec*.m` | MATLAB campaign launchers for suite-level experiments | Defines the practical experiment matrix used from the MATLAB desktop. |
| `src/runners/run_experiment.m` | Seed scheduling, resume behavior, optimizer calls, summaries, curves, comparison tables | Most reproducibility evidence is produced here. |
| `src/runners/get_cec_seed.m` | Unified seed formula | Guarantees same `(D,F,run)` seed across optimizers in unified mode. |
| `src/common/gsk_*.m` | Shared MATLAB mechanisms | Changes can affect multiple optimizers; edit only after checking reference behavior. |
| `src/optimizers/<slug>/*_optimize.m` | Algorithm-specific search logic | This is where paper/reference behavior lives. |
| `benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/gskcec_eval_mex.cpp` | MATLAB-to-C++ CEC bridge | Required for MATLAB CEC experiments. |
| `benchmarks/cec_suite_cpp/cec_tools/src/cli/gsk_run.cpp` | C++ CLI experiment entry point | Drives MATLAB from config files for CLI workflows. |
| `scripts/build_docs.ps1` | HTML documentation generator | `docs/html` is generated from Markdown, not hand-edited. |
| `scripts/analyze_results.m` | Post-run statistical analysis | Creates comparison/statistical figures without changing raw results. |
| `scripts/compare_reference_runs.m` | Per-(dimension, function) comparison of two `per_run.csv` sets | Judges a campaign against an imported per-run reference (e.g. DT-GSK vs `cec2017/dt-gsk/evidence/per_run.csv`); needs the Statistics and Machine Learning Toolbox. |
| `benchmarks/cec_reference_results/<suite>/dt-gsk/` | Imported DT-GSK reference tables (produced by its reference implementation) | Cross-implementation baseline; `cec2017/dt-gsk/` adds `PROVENANCE.md` and per-run `evidence/`. |

When adding new documentation, prefer a focused page under `docs/` and then add
it to `scripts/build_docs.ps1` so the HTML site stays complete.
