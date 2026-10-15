# Developer Guide

> **Orientation.** This is the day-to-day reference for working *inside*
> `gsk_family`: the hybrid MATLAB optimizers under `src/`, the C++20 CEC ports
> and tooling under `benchmarks/`, and the `gskcec_eval` MEX bridge that joins
> them. After reading it you can set up a local toolchain, build the C++ tree,
> find your way around both language halves, run the right tests for a change,
> and rebuild the docs. New to the project? Skim the
> [Code Reading Guide](code_reading_guide.md) first, and keep
> [architecture](../reference/architecture.md) and
> [project structure](../reference/project_structure.md) open for the layer map.
> When you are ready to submit work, follow the
> [Contributor Guide](contributor_guide.md).

## Local Setup

There is nothing to "install" in a package-manager sense - this project is not a
library. Instead you need three host tools on `PATH`, then a one-time build of
the C++ tree and the MEX bridge. (If you do want to consume the C++ benchmark
library from another CMake project, `cmake --install build --prefix <P>`
installs it with a package config, after which downstream
`find_package(gskcec 1.0 REQUIRED)` plus
`target_link_libraries(<target> gskcec::gskcec)` works.)

Required toolchain (the versions this project is developed with):

- **MATLAB R2025b** - runs the optimizers, runners, smoke tests, and validation.
- **MinGW-w64 g++ with C++20 support** - WinLibs GCC builds the CEC tooling and
  the MEX bridge. The MATLAB-bundled MinGW (GCC 8.1) is too old for C++20 and is
  not used.
- **CMake >= 3.20** - WinLibs CMake or the MATLAB-bundled CMake both work.

Build the C++ tooling and run its tests once to confirm the checkout is healthy:

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

A green `ctest` (13 suites) is the baseline: the port suites compare against
committed ground-truth data and `gskcec_cli_exit_codes` checks the CLI exit
codes, so if it fails on a fresh checkout, fix the toolchain before making
changes. If `cmake`/`g++` are not on `PATH`, pass their
full paths (see `build.txt`).

CEC MATLAB experiments evaluate the ported benchmarks through a project-local
MEX bridge. Build it once (needs MATLAB plus the WinLibs toolchain):

```powershell
powershell -File scripts\build_mex_bridge.ps1
```

This produces `build/mex/gskcec_eval.mexw64`, linked fully static (no MinGW
runtime DLL is needed at load time). The root `run_all_cec*.m` launchers and
`run_experiment` check that this file exists and actually loads (a forced load
probe; `gskcec:mexNotLoadable` otherwise) before starting, so a missing or
unloadable bridge fails fast instead of writing an all-skipped result folder.

Finally, confirm the MATLAB side runs without the bridge (pure-MATLAB sphere
problems, tiny budgets):

```powershell
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
```

## Development Principles

These are the standing rules - the project contract - that keep the ports
faithful and reproducible. Follow them by default; document any deliberate
exception in [`docs/reference/porting_notes.md`](../reference/porting_notes.md).

- **Preserve reference behavior, including documented quirks.** Many ports keep
  things that look like bugs because they match the reference implementation
  (for example the CEC2017 F6 buffer aliasing). Read
  [`porting_notes.md`](../reference/porting_notes.md) before "fixing" anything
  that looks wrong; if behavior is unclear, document the gap there rather than
  inventing it.
- **Never weaken a test tolerance to make a change pass.** Every `ctest` suite
  asserts against committed ground truth; if a port no longer matches, the port
  is wrong, not the threshold.
- **No Python, anywhere.** Code, tooling, bindings, and package metadata are all
  excluded by contract. Tooling languages are C++, MATLAB, PowerShell, and
  CMake.
- **No external GSK or CEC imports** into the active tree. The committed ports,
  imported reference tables, and provenance notes are the self-contained source
  of truth.
- **Keep the language boundary.** GSK algorithm code is MATLAB under `src/`; CEC
  benchmark code is C++ under `benchmarks/`. Optimizers depend only on the
  `problem` struct, never on suite internals.
- **Mind the slug-vs-identifier split.** Public optimizer slugs are hyphenated
  (`atmals-gsk`, `fdb-agsk`) in configs, CLI commands, result folders, and
  reference folders; MATLAB function and file names use underscores
  (`atmals_gsk_optimize.m`) because identifiers cannot contain hyphens.
- **Keep the two CEC2013 suites separate.** `cec2013` (converted from the
  CEC2013 R package) and `cec2013lsgo` are distinct suites and are never merged.
- **Wall-clock seeding is forbidden.** A run is fully determined by its seed and
  options; historical clock seeds survive only as provenance notes.
- **Rebuild after changes.** Rebuild the C++ tree after any C++/CMake/CLI change;
  rebuild the MEX bridge after any CEC-suite-source or `mex_bridge/` change;
  rebuild `docs/html` after any doc edit (never hand-edit the generated HTML).

## Code Organization

The tree is split by language and responsibility: MATLAB optimizers and runners
on one side, C++ CEC ports and tooling on the other, joined at the MEX bridge.
The full layer model is in [architecture](../reference/architecture.md); the
folder map is in [project structure](../reference/project_structure.md).

```text
gsk_family/
  src/                       MATLAB GSK-family code
    common/                  shared helpers (gsk_set_rng.m, gsk_init_population.m,
                             donor selection, bound repair, reduction survivors)
    optimizers/<slug>/       the seven optimizers (gsk, agsk, apgsk,
                             atmals-gsk, egsk, fdb-agsk, dt-gsk)
    runners/                 run_experiment.m, get_cec_seed.m,
                             gskcec_make_problem.m, seed helpers
    experiments/             default experiment matrix definitions
    tests/                   test_*.m smoke tests + run_matlab_smoke_tests.m
  benchmarks/
    cec_reference_results/   imported, read-only reference tables + curated assets
    cec_suite_cpp/<suite>/       C++ port (src/) + input_data/ per suite
    cec_suite_cpp/cec_tools/     C++ library, CLIs, MEX bridge, tests
      include/gskcec/        public headers (core/, benchmark/, experiment/)
      src/{cli,experiment,mex_bridge,benchmark}/
      tests/{unit,data}/     unit tests + ground-truth vectors
  configs/                   strict flat-YAML experiment configs
  scripts/                   PowerShell + MATLAB helper scripts
  docs/                      Markdown source of truth (docs/html is generated)
```

Generated trees (`build/`, `results/`, `docs/html/`) are not source of truth -
they are rebuildable and gitignored. The two halves meet only at
`src/runners/gskcec_make_problem.m` (MATLAB side) and the
`gskcec_eval` MEX bridge (C++ side); the
[Code Reading Guide](code_reading_guide.md) walks both in reading order.

## Documentation Requirements

Every MATLAB optimizer, runner, and shared helper carries an in-file help block
that cites its reference source and links the contract in
[`matlab_interface.md`](../reference/matlab_interface.md); every C++ port header
cites its reference file (with a SHA256) and lists the preserved quirks. Keep
these current when you change behavior.

Public behavior also needs Markdown coverage when it affects users, experiments,
output artifacts, reproducibility, or parity decisions. The Markdown under
`docs/` is the source of truth. After editing any help block, header, or
Markdown page, rebuild the HTML site so it stays in sync (never hand-edit
`docs/html`):

```powershell
powershell -File scripts\build_docs.ps1 -Clean
```

The C++ API reference is generated separately with Doxygen
(`doxygen docs/Doxyfile`); MATLAB optimizers are documented through their help
blocks plus [`matlab_interface.md`](../reference/matlab_interface.md).

## Testing

There are two test surfaces, one per language. Pick the cheapest that covers
your change, then run both before you push.

**C++ ports and tooling (`ctest`).** The 13 suites under
`benchmarks/cec_suite_cpp/cec_tools/tests/` compare each port against fixed-vector
ground truth in `tests/data/` and exercise the experiment/comparison logic. The
13th, `gskcec_cli_exit_codes` (`tests/cli/`), is a `cmake -P` script
(`gsk_run_exit_codes.cmake`) that drives `gsk_run`, `gsk_validate`, and
`gsk_bench` against stub MATLAB executables built from `fake_matlab.cpp` and
checks their exit codes and argument parsing; the cases that launch MATLAB run
on Windows only:

```powershell
cmake --build build -j
ctest --test-dir build --output-on-failure
```

Rebuild the C++ tree first - a stale `build\gsk_run.exe` (or `gsk_validate.exe`,
`gsk_list.exe`) can keep old behavior even when the source is current. To
iterate on one area, build and run a single target, e.g.
`ctest --test-dir build -R gskcec_experiment_tests --output-on-failure`.

**MATLAB optimizers and runners (smoke tests).**
`src/tests/run_matlab_smoke_tests.m` discovers every `test_*.m` (13 today: one
per optimizer, including `test_dt_gsk_smoke.m`, plus the common helpers, seed
policy, runner, resume, fair-start and MEX-bridge tests), runs them on
pure-MATLAB sphere problems at tiny budgets (no MEX bridge required), and exits
nonzero under `matlab -batch` on any failure:

```powershell
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
```

**End-to-end check.** A tiny CLI run exercises the full path - C++ orchestrator,
MATLAB runner, MEX bridge, result writers, and auto-verification:

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
build\gsk_run.exe --config configs\smoke.yml --root .
```

A quick rule of thumb: changing a C++ port or tooling logic -> rebuild and run
`ctest`; touching an optimizer, helper, or runner -> run the MATLAB smoke tests;
changing anything that crosses the bridge or writes results -> add the
`gsk_run --config configs/smoke.yml` end-to-end run. Never weaken a tolerance to
make a suite pass.
