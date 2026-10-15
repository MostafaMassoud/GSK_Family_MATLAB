# Numerical Examples

> **What this is:** small, hand-checkable walkthroughs of the mechanics shared
> across the GSK family in the MATLAB implementation. **For:** anyone who wants
> to verify the implementation by arithmetic. **Prerequisites:**
> [Seed Policy](../reference/seed_policy.md) and
> [Result Schema](../reference/result_schema.md) for the exact contracts.
> **After reading:** you will be able to reproduce the shared steps by hand and
> jump to each optimizer's *distinctive* worked example. Each optimizer's
> distinctive operator has its own example in its algorithm page (indexed at the
> [bottom](#per-optimizer-distinctive-examples)); this page covers the steps every
> optimizer shares. All examples use tiny values so each line can be checked by
> hand, and cite the code that implements them.

## Population initialization

The initial population is **one** scaled uniform draw. `gsk_init_population.m`
maps a single `rand(NP, D)` matrix into the box `[lb, ub]` using implicit
expansion (`src/common/gsk_init_population.m:19`):

```matlab
pop = lb + rand(np, dim) .* (ub - lb);
```

This consumes exactly one `rand(NP, D)` draw, matching the reference
initialization shared by every GSK release. With tiny numbers:

```text
dimension = 2,  population size = 3,  lb = [-5, -5],  ub = [5, 5]
single rand(3,2) draw U =
  [0.10, 0.70]
  [0.40, 0.50]
  [0.90, 0.20]

pop = lb + U .* (ub - lb)         % ub - lb = [10, 10]
    = [-4,  2]
      [-1,  0]
      [ 4, -3]
```

For the sphere function `f(x) = sum(x.^2)`:

```text
f([-4, 2]) = 16 + 4  = 20
f([-1, 0]) =  1 + 0  =  1      <- best
f([ 4,-3]) = 16 + 9  = 25
```

## Unified seed and fair start

The `unified` policy derives one run seed from the run coordinates only and gives
every optimizer in the same `(dim, func, run)` cell the *same* starting
population. The formula is optimizer-independent
(`src/runners/get_cec_seed.m:80-90`):

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

Worked to the exact integer, with the default `base_seed = 20240620`:

```text
base_seed = 20240620
dim       = 30
func      = 7
run       = 12

raw  = 20240620 + 1000003*30 + 1000033*7 + 1000037*12
     = 20240620 + 30000090 + 7000231 + 12000444
     = 69241385

seed = mod(69241385, 2147483646) + 1
     = 69241386
```

So GSK, AGSK, APGSK, ATMALS-GSK, eGSK, and FDB-AGSK all receive seed `69241386`
for `(D=30, F7, run=12)`. The runner then makes the start fair
(`src/runners/run_experiment.m`):

```text
1. seed = get_cec_seed(base_seed, dim, func, run)
2. rng(seed, generator)                 % threefry when supported, else twister
3. X0 = gsk_init_population(NP, lb, ub)  % drawn once, outside the optimizer
4. capture rng_state_after_initialization = rng
5. each optimizer restores that state before its first random decision
```

Differences between optimizers therefore come from the algorithms, not from
luckier initial points. `run_all_cec*.m` launchers call
`verify_unified_seed_schedule.m` to assert every optimizer used this same seed
per `(Dim, Function, Run)`. The [reference policy](../reference/seed_policy.md)
uses per-optimizer seeds instead, to reproduce published tables.

## Boundary handling (midpoint repair)

A trial coordinate that leaves the box is pulled to the midpoint between the
**parent** value and the breached bound -- never clipped to the bound and never
reflected past the parent (`src/common/gsk_bound_repair.m`):

```text
if trial_j < lb_j:  trial_j = (parent_j + lb_j) / 2
if trial_j > ub_j:  trial_j = (parent_j + ub_j) / 2
```

Example:

```text
parent = [4, 1],  trial = [7, 1],  ub = [5, 5]
dim 0: 7 > 5  ->  (parent_0 + ub_0)/2 = (4 + 5)/2 = 4.5
dim 1: 1 in bounds -> unchanged
repaired = [4.5, 1]
```

This is reference behavior and must not be replaced with clipping when
reproducing published results.

## Fitness comparison (greedy selection)

Replacement is strictly greedy -- a child must *beat* its parent to survive:

```text
parent fitness = 12,  child fitness = 8   ->  child replaces parent
parent fitness = 12,  child fitness = 14  ->  parent stays
parent fitness = 12,  child fitness = 12  ->  parent stays   (strict improvement only)
```

## Best-so-far tracking

The convergence trace records the best objective seen at each generation
(`result.convergence`). It is monotone non-increasing -- it can repeat but never
worsen:

```text
nfes:         20, 40, 60, 80
best fitness: 12,  8,  8,  5
```

The median run's trace is written to `curves/Figure_F<func>_D<dim>_Run#<run>.csv`
with columns `Eval,BestError,Log10Error`; per-run checkpoint errors go to
`gen_logs/`. See [Result Schema](../reference/result_schema.md#curvesfigure_ffunc_ddim_runruncsv).

## Summary statistics

CEC-style summaries report `Best,Median,Mean,Worst,SD` where `SD` is the
**sample** standard deviation -- MATLAB `std(x)`, which divides by `n-1`, not the
population divisor `n`. On known-optimum suites (cec2017, cec2020, cec2013) the
statistics are computed over errors `best_fitness - optimum` with a `1e-8` zero
cutoff; on no-optimum suites (cec2011, cec2013lsgo) they are computed over raw
objectives and the `error` column is `NaN`
([Benchmark Protocol](../reference/benchmark_protocol.md#statistics-conventions-all-suites)).

For three runs:

```text
errors = [1.0e-3, 5.0e-4, 2.0e-3]

Best   = min       = 5.0000000e-4
Median =             1.0000000e-3
Mean   = sum/3     = 1.1666667e-3
Worst  = max       = 2.0000000e-3
SD     = sqrt( ((1e-3-Mean)^2 + (5e-4-Mean)^2 + (2e-3-Mean)^2) / (3-1) )
       = sqrt( 1.1666667e-6 / 2 ) = 7.6376262e-4      % MATLAB std(x), divisor n-1
```

Using the population divisor `n` instead would give `6.236e-4`; the project uses
the sample divisor `n-1`, matching the imported reference summaries. Summary
tables are written in `%.10E` scientific notation
([Result Schema](../reference/result_schema.md#numeric-formatting)).

> **One CEC2017 exception.** ATMALS-GSK on cec2017 reports
> `abs(best_fitness - optimum)` (still with the `1e-8` cutoff) rather than the
> signed error; every other optimizer reports the signed `best_fitness - optimum`.

## LPSR population schedule (adaptive variants)

AGSK, APGSK, and FDB-AGSK shrink the population as the budget burns (nonlinear
LPSR, `src/common/gsk_reduction_survivors.m` removes the worst rows). With
`max = np_init`, `min = min_pop_size`, and budget ratio `t = nfes / max_nfes`:

```text
NP_target(t) = round( (min - max) * t^(1 - t) + max )      % MATLAB round, half away from zero
```

For `np_init = 100`, `min_pop_size = 12`, `max_nfes = 10000`:

| nfes | t | t^(1-t) | NP_target |
|---:|---:|---:|---:|
| 0 | 0.00 | 0.000 | 100 |
| 1000 | 0.10 | 0.126 | 89 |
| 2500 | 0.25 | 0.354 | 69 |
| 5000 | 0.50 | 0.707 | 38 |
| 7500 | 0.75 | 0.931 | 18 |
| 9000 | 0.90 | 0.990 | 13 |
| 10000 | 1.00 | 1.000 | 12 |

Spot-check `t = 0.50`: `(12 - 100) * 0.5^0.5 + 100 = -88 * 0.70711 + 100 =
37.8 -> 38`. The curve is steepest mid-run (the exponent is `1 - t`, not `1`) and
bottoms out at `min_pop_size`. Worst individuals are removed one at a time, with
ties broken by removing the highest index first. See [AGSK](../algorithms/agsk.md)
for the full reduction step.

## Parallel determinism

The `parfor` backend may finish tasks out of order, but the runner restores input
order before writing, so artifacts are byte-identical to a serial run
(`src/runners/run_experiment.m`):

```text
serial task order:   run 1, run 2, run 3
parallel completion: run 2 may finish first
writer order:        run 1, run 2, run 3     % restored before any CSV is written
```

The per-run seed is a function of `(base_seed, dim, func, run)` only, so it never
depends on the backend, the worker identity, or the worker count. Combined with
the restored post-initialization RNG state, this fixes the draw order, which is
why serial and `parfor` runs are bit-identical. See
[Reproducibility -- Serial and parallel parity](reproducibility.md#serial-and-parallel-parity).

## Per-optimizer distinctive examples

Each algorithm page carries a hand-checkable example of the operator that sets
that optimizer apart:

| Optimizer | Distinctive operator | Worked example |
|---|---|---|
| GSK | junior/senior gaining-sharing + dimension schedule | [gsk.md](../algorithms/gsk.md#worked-example) |
| AGSK | adaptive `(KF, KR)` pools + LPSR reduction | [agsk.md](../algorithms/agsk.md#worked-example) |
| APGSK | negative-`KF` pool gate + stochastic junior schedule | [apgsk.md](../algorithms/apgsk.md#worked-example) |
| FDB-AGSK | fitness-distance-balance donor selection | [fdb-agsk.md](../algorithms/fdb-agsk.md#worked-example) |
| ATMALS-GSK | memory-roulette pools + local search | [atmals-gsk.md](../algorithms/atmals-gsk.md#worked-example) |
| eGSK | KF1/KF2 fuzzy membership + late-stage `fmincon` refinement | [egsk.md](../algorithms/egsk.md#worked-example) |
