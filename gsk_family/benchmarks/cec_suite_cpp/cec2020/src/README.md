# CEC2020 C++ Source

`cec2020_problem.cpp` is the standalone C++20 port of the CEC2020
single-objective bound-constrained suite. Historical provenance:

```text
CEC2020 competition cec20_func.cpp
```

(`cec20_func.cpp` in this folder is an identical staged copy of that MEX
evaluator; it is never compiled.)

## API

Implemented against `gskcec/benchmark/cec2020.hpp`
(`gskcec::cec2020::make_problem(function_id, dimension, data_root)` plus
`supported_functions()` = 1..10, `supported_dimensions()` = {5, 10, 15, 20},
`budget_for_dimension()` = 50k / 1M / 3M / 10M per the AGSK CEC2020 protocol).
Bounds are `[-100, 100]^D` for all functions. `optimum()` returns the AGSK
reference vector `{100, 1100, 700, 1900, 1700, 1600, 2100, 2200, 2400, 2500}`,
which equals the per-case bias the MEX adds.

Public ids map to internal data-file ids via
`Func_num[] = {1, 2, 3, 7, 4, 16, 6, 22, 24, 25}`; data files
(`M_<id>_D<D>.txt`, `shift_data_<id>.txt`, `shuffle_data_<id>_D<D>.txt`) are
named by the internal id. Only code reachable through those ten ids is ported
(basic functions, `hf01`/`hf05`/`hf06`, `cf02`/`cf04`/`cf05`, `cf_cal`,
shift/rotate helpers); the remaining MEX switch cases are dead code for this
suite.

## Data loading and availability

All file reads go through `gskcec::load_values_file` /
`gskcec::require_file`, rooted at the constructor's `data_root`:

* rotation: `nx*nx` values, or `10*nx*nx` for compositions (ids >= 20);
* shift: first `nx` values; compositions read the first `nx` values of each
  of the 10 rows (the MEX `fscanf` loop skips the remainder of every row;
  rows are uniform 100-wide in the shipped data, so the port derives the row
  stride as `total / 10`);
* shuffle: consumed only by internal ids 4, 6, 16 (`hf01`/`hf05`/`hf06`), but
  the file must EXIST for every (function, dimension): the CEC2020/AGSK data
  distribution defines per-dimension availability through these files.
  Internal ids 1 and 22 ship no `D5`/`D15` shuffle files, so public F1 and F8
  at D=5/D=15 have no reference ground truth and the constructor throws
  `std::runtime_error` naming the missing file. Availability is data-driven;
  nothing beyond functions 1..10 and dimensions {5, 10, 15, 20} is hard-coded.

`std::invalid_argument` signals bad ids/dimensions; `std::runtime_error`
(naming the file) signals missing or malformed data.

## Preserved reference quirks

* Public F4 (internal 7) calls `grie_rosen_func` with `s_flag = 0`,
  `r_flag = 0`: the loaded shift/rotation data is intentionally NOT applied.
* `hf01`/`hf05` assign the partition remainder to the FIRST group,
  `hf06` to the last. At D=5 `hf05` (public F7) yields
  `G_nx = {0, 1, 1, 1, 2}`: the zero-width `escaffer6` slice skips its loop
  and evaluates the wrap-around term on `z[nx-1] == z[-1]`, an out-of-bounds
  heap read in the MEX. The port reproduces the recorded MEX behavior with a
  guard slot holding `0.0` immediately before the `z` scratch buffer
  (validated bit-exactly against the MEX ground truth, see below).
* Composition lambda scalings (e.g. `1000*fit/100`, `10000*fit/1e+10`),
  sigma/delta and bias tables, and the Schwefel constants
  (`4.209687462275036e+002`, `4.189828872724338e+002`, added once after the
  loop) are transcribed verbatim.

## Threading

State is per-instance RAII, loaded once in the constructor. `evaluate()` is
`const` but reuses mutable scratch buffers (the MEX globals `y`/`z`), so a
single instance is NOT thread-safe; use one instance per thread.

## Validation

`benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2020_tests.cpp` checks all 180 rows of
the committed `benchmarks/cec_suite_cpp/cec_tools/tests/data/cec2020_expected.csv`
at the probe points in `points_D<D>.txt`, with relative tolerance 1e-10. Last observed
max relative deviation: 2.8e-16. Build and run from the project root:

```bash
g++ -std=c++20 -O2 -Wall -Wextra -I benchmarks/cec_suite_cpp/cec_tools/include \
    benchmarks/cec_suite_cpp/cec_tools/src/benchmark/data_loading.cpp \
    benchmarks/cec_suite_cpp/cec2020/src/cec2020_problem.cpp \
    benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2020_tests.cpp -o cec2020_tests
./cec2020_tests [project_root]
```
