# CEC2013 C++ Port

`cec2013_problem.cpp` is the standalone C++20 port of the **standard CEC2013
single-objective suite** (28 functions). It is completely distinct from
CEC2013LSGO; the two must never be merged.

## Provenance

Historical source notes:

- `historical source: CEC2013 R package src/test_func.c`
  ("CEC13 Test Function Suite", Jane Jing Liang, last modified 27 Jan 2013)
- `historical source: CEC2013 R package src/cec2013.c`
  (R bridge: calling convention, data directory, global buffers)
- `historical source: CEC2013 R package R/cec2013.R`
  (validation: function ids 1..28, dimensions {2,5,10,20,30,40,50,60,70,80,90,100})

R-isms (`R.h`, `error()`, `R_CheckUserInterrupt()`, lazily re-initialised
globals, per-call `malloc`) were replaced by C++ exceptions, `std::vector`
storage and per-instance RAII state. Numerics, constants, biases and
transformation order are preserved verbatim.

## API

Implements `benchmarks/cec_suite_cpp/cec_tools/include/gskcec/benchmark/cec2013.hpp`
(`gskcec::cec2013::make_problem`, `supported_functions`,
`supported_dimensions`). Search domain `[-100,100]^D`; `optimum()` returns
the reference bias (`-1400..-100` for f1..f14, `100..1400` for f15..f28).
`std::invalid_argument` for bad function/dimension; `std::runtime_error`
(naming the path) for missing/bad data files.

**Not thread-safe per instance**: `evaluate()` reuses mutable scratch
buffers (the `y`/`z` globals of the reference). Use one instance per thread.

## Data files (`../input_data/`, loaded once in the constructor)

- `M_D<dim>.txt` — 10 rotation matrices (`dim x dim`, row-major), read flat
  (`cf_num*nx*nx` values, `cf_num == 10`).
- `shift_data.txt` — read as a **flat prefix of `10*dim` values**. The file
  stores a 10 x 100 table, so for `D < 100` the composition shift rows are
  consecutive `D`-value slices of the flattened table, *not* per-line
  prefixes. This mirrors the reference `fscanf` loop exactly.

## Reference quirks preserved deliberately

1. `asyfunc(src, dst)` writes `dst[i]` only when `src[i] > 0`; non-positive
   components keep the value an earlier pipeline stage left in `dst`
   (typically the pre-rotation/pre-osz vector). Affects f3, f7, f8, f9,
   f12, f13, f20 and rotated composition members.
2. `grie_rosen_func` (f19; component 0 of f28) computes the rotation and
   then overwrites it with the unrotated `y + 1` (`z[i]=y[i]+1` in the
   reference), so f19 is effectively unrotated despite `r_flag == 1`.
   (Official 2013 releases use `z[i]=z[i]+1` here — not "fixed", reported.)
3. `dif_powers_func` exponent `2 + 4*i/(nx-1)` uses integer division.
4. `schwefel_func` scale `1000/100` is integer division (== 10), and its
   truncated optimum constants (`4.209687462275036e2`,
   `4.189828872724338e2`) leave a ~`1e-12*D` residual at the shifted
   optimum (observed: 1.1e-10 at D=100 for f14/f15/f22/f23; 2.7e-11 for
   f24/f25/f26 where the Schwefel fit is scaled by 0.25).
5. `oszfunc` initialises `xx = 0` once outside the loop; the stale value is
   only ever multiplied by `sx == 0`, so it has no observable effect.
6. The reference's `x_bound` buffer and `EPS` macro are never used by the
   computation and were dropped.

## Validation

`benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2013_tests.cpp` (no R available, so no
external ground truth): analytic f1 (and f5 cross-checked externally);
optimum-at-shift `|f(o) - bias| <= 1e-6` for all 28 functions at all 12
dimensions (holds by construction for every function; exact 0 except the
Schwefel residuals above); self-generated regression baseline
`benchmarks/cec_suite_cpp/cec_tools/tests/data/cec2013_regression.csv` (28 functions x
D in {10,30,50} x 5 probe points, `%.17g`, relative tolerance 1e-12 —
a refactor guard, **not** external ground truth; delete the CSV and re-run
the test to regenerate); invalid-argument and missing-data-root checks.

Build and run from the project root:

```
g++ -std=c++20 -O2 -Wall -Wextra -I benchmarks/cec_suite_cpp/cec_tools/include \
    benchmarks/cec_suite_cpp/cec_tools/src/benchmark/data_loading.cpp \
    benchmarks/cec_suite_cpp/cec2013/src/cec2013_problem.cpp \
    benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2013_tests.cpp \
    -o cec2013_tests && ./cec2013_tests .
```
