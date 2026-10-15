# C++ API documentation (Doxygen)

> **What this is:** how to generate the Doxygen reference site for the project's
> C++ benchmark and tooling headers, and what it does (and does not) cover.
> **For:** anyone who wants the symbol-level C++ API or needs to regenerate it.
> **Prerequisites:** Doxygen on PATH (Graphviz optional); a rough sense of the
> language split in [architecture.md](architecture.md).
> **After reading** you will know how to build the API site, where it lands, and
> why the MATLAB optimizers are documented elsewhere.

This page explains how to generate the reference documentation for the project's
**C++** code, and what it does (and does not) cover. For the plain-language
overview start at [../getting-started/explainer.md](../getting-started/explainer.md);
to build and run the toolkit, see
[../getting-started/tutorial.md](../getting-started/tutorial.md).

## What this documents

The generated site documents the **C++ benchmark and tooling API** - the public
headers under `benchmarks/cec_suite_cpp/cec_tools/include/gskcec`. These are the small,
stable interfaces the rest of the project is built on:

- `gskcec/core/` - numeric types, `Bounds`, the deterministic random engine and
  run-seed derivation, summary statistics, a stopwatch, and run-result records.
- `gskcec/benchmark/` - the one-line problem interface
  (`BenchmarkProblem`: `evaluate`, `bounds`, `optimum`, `dimension`), the
  per-suite headers (`cec2011.hpp` ... `cec2020.hpp`), the generic
  `make_problem(suite, function, dimension, data_root)` factory, data loading,
  and the imported-reference loader.
- `gskcec/experiment/` - the strict config parser (`config.hpp`), the
  results-vs-reference comparison and the CONSISTENT/DEVIATES verification
  (`comparison.hpp`), and the run-result schema (`result.hpp`).

The headers already carry Doxygen comments (`///`, `@param`, `@throws`), so the
output is meaningful; `EXTRACT_ALL` additionally guarantees that every declared
type and function appears even where a comment is absent.

## What this does NOT document

The **GSK-family optimizers are MATLAB**, not C++, and Doxygen does not read them
here. They are documented two ways instead:

- each optimizer's **in-file help block** at the top of its `.m` file (open
  `src/optimizers/gsk/gsk_optimize.m` and read the leading comment), and
- the contract document [matlab_interface.md](matlab_interface.md) (the problem
  struct, options, result struct, and entry points).

This split mirrors the project's language boundary: algorithms in MATLAB under
`src/`, benchmarks and tooling in C++ under `benchmarks/` (see
[architecture.md](architecture.md)).

## Prerequisites

- **Doxygen** (the generator). Check it is available:
  ```powershell
  (Get-Command doxygen).Source
  ```
- **Graphviz** (optional) - only needed for the richer call/dependency graphs.
  Check whether its `dot` tool is on PATH:
  ```powershell
  (Get-Command dot -ErrorAction SilentlyContinue).Source
  ```
  If this prints nothing, `dot` is not installed - that is fine; see "Graphviz"
  below.

## Generate the docs

From the **project root** (the folder with `CMakeLists.txt`):

```powershell
doxygen docs/Doxyfile
```

Open the result:

```text
build/doxygen/html/index.html
```

The output goes under `build/`, which is gitignored, so generated docs are never
committed. The landing page of the site is this file (`docs/reference/api.md`).
If you change C++ API comments or public headers, rebuild the documentation
site with `scripts\build_docs.ps1 -Clean`. If executable C++ behavior changes,
also rebuild the C++ tree and run `ctest --test-dir build --output-on-failure`;
Doxygen alone does not refresh the CLI executables.

## Graphviz (call graphs) - optional, degrades gracefully

`docs/Doxyfile` sets `HAVE_DOT = YES`, so when Graphviz's `dot` tool is
installed Doxygen draws call graphs, caller graphs, and include/collaboration
diagrams. **If `dot` is not installed**, Doxygen still generates the full HTML
(class inheritance/collaboration diagrams render without `dot`), but it prints
warnings about the missing tool. To silence those warnings, edit `docs/Doxyfile`
and set:

```text
HAVE_DOT = NO
```

If `dot` is installed but not on your PATH, instead point Doxygen at it by
setting `DOT_PATH` to the Graphviz `bin` folder in `docs/Doxyfile`, for example:

```text
DOT_PATH = C:/Graphviz/bin
```

## Quick reference: key entry points

Once generated, these are good starting points in the API site:

| Header | Start here for |
|---|---|
| `gskcec/benchmark/benchmark.hpp` | the `BenchmarkProblem` interface every port implements |
| `gskcec/benchmark/factory.hpp` | `list_suites`, `suite_info`, `make_problem`, `default_data_root` |
| `gskcec/experiment/config.hpp` | the `ExperimentConfig` fields parsed from `configs/*.yml` |
| `gskcec/experiment/comparison.hpp` | comparison + `classify_run` (the CONSISTENT/DEVIATES verdict) |
| `gskcec/core/random.hpp` | deterministic seeding (`make_run_seed`) |

All live under `benchmarks/cec_suite_cpp/cec_tools/include/`.
