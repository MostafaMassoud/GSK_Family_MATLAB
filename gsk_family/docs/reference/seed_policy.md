# Seed Policy

> **What this is:** the authoritative seed and RNG contract for the MATLAB
> GSK-family runners - the `reference`, `unified`, `native`, and `derived`
> policies, their formulas, and the generator selection. **For:** anyone
> reproducing published tables, running fair cross-family experiments, or
> auditing a seed schedule. **Prerequisites:** none. **After reading** you will
> know which policy each entry point defaults to and exactly how every per-run
> seed is computed.

This page is the authoritative seed and RNG contract for the MATLAB
GSK-family runners.

## Defaults by Entry Point

High-level reproduction entry points default to the reference-compatible policy:

- `gsk_run` default: `seed_policy = 'reference'`, `rand_generator = 'threefry'`
  requested
- `configs/*.yml`: the shipped configs write `seed_policy: reference` and
  `rand_generator: threefry` explicitly. Reference mode overrides the effective
  generator per optimizer, so the requested generator is relevant only when you
  switch those configs to `unified`, `native`, or `derived`.

Root `run_all_cec*.m` launchers default to the fair cross-family policy:

- `seed_policy = 'unified'`
- `rand_generator = 'threefry'` requested; the runner uses `threefry` when the
  installed MATLAB supports it and falls back to `twister` otherwise
- base seed is not exposed in the launcher config; it comes from
  `run_experiment.m` (`default_base_seed = 20240620`)

The lower-level MATLAB function `run_experiment(...)` also defaults to
`seed_policy='unified'` if you call it directly and omit the argument. Pass
`'seed_policy','reference'` for published-table reproduction, or
`'seed_policy','native'` / `'derived'` for diagnostic hashed schedules.

For every `(function, dimension, run)` cell, `run_experiment` records the seed
in `summary/seed_schedule.csv`, `summary/per_run.csv`,
`summary/run_config.json`, `summary/phase0_protocol.json`, and
`summary/environment.json`; the effective generator is recorded in
`environment.json`. Reference mode is deterministic for all optimizers.

## `reference` - Published-Table Reproduction

Set `seed_policy = 'reference'` to reproduce the project reference protocol. Each
optimizer has its own explicit seed case, and the effective generator is selected
to match the historical driver family:

| Optimizer | Reference seed rule |
|---|---|
| `gsk`, `atmals-gsk`, `egsk` | `base_seed + 9973*func + (run-1)` |
| `agsk`, `apgsk`, `fdb-agsk` | `D*func*run` |

| Optimizer | Effective reference RNG |
|---|---|
| `agsk`, `apgsk`, `fdb-agsk`, `egsk`, `atmals-gsk` | legacy `seed` stream, equivalent to deterministic `rand('seed', seed)` |
| `gsk` and fallback optimizers | `twister` |

An unknown optimizer falls back to `get_cec_seed(base_seed, dim, func, run)`.
The eGSK and ATMALS-GSK source releases were originally wall-clock seeded. This
project keeps reference runs deterministic by using the scheduled seed with the
effective reference RNG above.

## `unified` - Fair Cross-Family Experiments

Set `seed_policy = 'unified'` for new fair cross-family experiments. This mode
does **not** try to reproduce published tables. Instead, every optimizer gets
the same seed for the same `(dimension, function, run)` cell, and the runner
uses one scheduling-independent MATLAB generator for the whole cell:
`threefry` when available, otherwise `twister`.

The rule is deliberately optimizer-free. The seed must depend only on:

- the campaign-level `base_seed`,
- the problem dimension `dim`,
- the benchmark function number `func`, and
- the repeated-trial index `run`.

It must not depend on optimizer name, optimizer index, `alg_code`, population
size, evaluation budget, suite name, local-search availability, or any other
algorithm-specific value. This is the key fairness rule: if two algorithms are
run on the same `(dim, func, run)`, they must receive exactly the same seed.

Implemented in `src/runners/get_cec_seed.m`:

```matlab
function seed = get_cec_seed(base_seed, dim, func, run)
    MAX_SAFE_SEED = uint64(2147483646);  % 2^31 - 2

    seed = mod(uint64(base_seed) ...
        + uint64(1000003) * uint64(dim) ...
        + uint64(1000033) * uint64(func) ...
        + uint64(1000037) * uint64(run), ...
        MAX_SAFE_SEED) + 1;

    seed = double(seed);
end
```

Formula anatomy:

- `base_seed` is the experiment campaign anchor. The default is `20240620`, a
  fixed date-like value chosen for reproducibility, not generated from the
  clock.
- `1000003*dim`, `1000033*func`, and `1000037*run` separate the three CEC
  coordinates with large nearby primes. Using separate additions avoids
  collisions that simple products such as `dim*func*run` can create.
- `uint64(...)` is used before every multiplication and addition, so the
  intermediate integer arithmetic is exact and cannot be rounded by MATLAB
  double precision before the modulo is applied.
- `2147483646` is the positive 31-bit seed range used here for MATLAB RNG
  compatibility. The final `+ 1` shifts the modulo output from `[0,2147483645]`
  to `[1,2147483646]`, avoiding seed 0.
- The returned `double` is only the final MATLAB seed value. The arithmetic
  that decides the seed has already happened exactly in `uint64`.

For example, with the default base seed:

```matlab
get_cec_seed(20240620, 30, 7, 12)  % returns 69241386
```

Therefore GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, and any future
optimizer all receive seed `69241386` for `(D=30, F=7, run=12)` in unified
mode.

Execution flow:

1. `run_experiment` computes `seed = get_cec_seed(base_seed, dim, func, run)`.
2. The runner resolves the unified RNG with `choose_cec_rng_generator()`:
   `threefry` if supported, otherwise `twister`.
3. The runner sets `rng(seed, rng_generator)`.
4. The runner draws `X0 = initialization(NP, dim, lb, ub)` once for that
   optimizer's population size.
5. The runner captures `rng_state_after_initialization = rng`.
6. The optimizer receives `options.initial_population = X0`,
   `options.rng_state_after_initialization`, `options.seed = seed`, and
   `options.rand_generator = rng_generator`.
7. Inside the optimizer, `gsk_initial_population_from_options(...)` uses `X0`
   instead of drawing a new first population.
8. `gsk_restore_rng_after_initialization(...)` restores the captured stream
   state, so the first random draw after initialization starts from the same
   post-`X0` position.

Properties and guarantees:

- Optimizer-independent: GSK, AGSK, APGSK, ATMALS-GSK, eGSK, and FDB-AGSK get
  the same seed at the same `(D, function, run)`.
- Dimension-aware: different dimensions do not reuse the same seed.
- Coordinate-separated: `1000003`, `1000033`, and `1000037` separate
  dimension/function/run coordinates without using ambiguous products such as
  `dim*func`.
- Generator-fixed: `effective_rand_generator` returns `threefry` under
  `unified` when MATLAB supports it, otherwise `twister`. Legacy `seed`/`state`
  requests are ignored in unified mode because they are compatibility
  diagnostics rather than fair CEC experiment generators.
- Generator-safe: uint64 arithmetic avoids overflow/rounding before the final
  double seed, and the modulo keeps the seed in `[1, 2147483646]`.
- Fair-start: the runner draws one `X0` with that seed before calling the
  optimizer, captures the RNG state immediately after `X0`, and passes both
  `options.initial_population` and `options.rng_state_after_initialization`.
  The optimizer then starts from the same seed, initial population, and
  post-initialization random state for the same `(D, function, run)`.
- Verification: root `run_all_cec*.m` launchers compare
  `summary/seed_schedule.csv` across completed optimizers with
  `verify_unified_seed_schedule(...)`.
- Resume-safe: existing `per_run.csv` rows are reused only when their stored
  seed matches the active schedule for that `(D, function, run)`. Stale rows
  remain on disk for audit history, and fresh rows are appended.

Use this mode for future controlled comparisons across the full GSK family.
Do not use it when you are trying to reproduce the published reference tables.

Important nuance: `X0` has the same seed and the same distribution, but its row
count follows the optimizer's population size. If two optimizers use different
population sizes, each receives the fair first `NP` rows for its own `NP`, drawn
from the same seed and followed by the matching post-initialization RNG state.
Population size is algorithm behavior and is not folded into the seed.

## `native` and `derived`

`native` and `derived` keep the older hashed diagnostic rule. They include the
optimizer and suite names in the seed, so they are reproducible and
well-decorrelated but **not** a same-seed cross-optimizer comparison schedule.
Implemented in `src/runners/derive_run_seed.m`:

```matlab
opt_code   = sum(double(optimizer));   % ASCII-sum hash of the optimizer name
suite_code = sum(double(suite));       % ASCII-sum hash of the suite name
seed = mod(base_seed + 1000003*opt_code + 1000033*suite_code + ...
           10000019*dim + 10000169*func + 10000379*run, 2^31 - 2) + 1;
```

These policies honour the passed `rand_generator` and are mainly useful for
diagnostics or backwards-compatible direct `run_experiment(...)` calls.

## RNG Generator Family

Every optimizer calls `src/common/gsk_set_rng.m` at entry. The runner passes
`options.seed` plus `options.rand_generator`:

| `rand_generator` | MATLAB stream |
|---|---|
| `threefry` | `rng(seed,'threefry')` when supported; unified-mode preference |
| `twister` | `rng(seed,'twister')` / `mt19937ar` |
| `seed` | legacy v4 stream, equivalent to classic `rand('seed', seed)` |
| `state` | legacy v5 stream, equivalent to classic `rand('state', seed)` |

`threefry` is the preferred unified-mode generator because it is
scheduling-independent and suitable for serial/parfor-safe task execution.
`twister` is the automatic fallback and remains the direct optimizer default.
Use `seed` or `state` only when testing legacy MATLAB RNG hypotheses. The
shared helper controls `rand`, `randi`, and `randperm`, so the whole optimizer
trajectory is deterministic for the selected seed and generator family.
Historical source releases that used `rand('seed', sum(100 * clock))` are
represented by deterministic scheduled seeds; wall-clock seeding is not a
supported current mode.

Under `seed_policy='reference'`, `effective_rand_generator` overrides the
requested generator: `agsk`, `apgsk`, `fdb-agsk`, `egsk`, and `atmals-gsk`
use legacy `seed`; `gsk` and fallback optimizers use `twister`.
Under `seed_policy='unified'`, every optimizer uses the same resolved generator:
`threefry` when supported, otherwise `twister`.
`native` and `derived` honour the passed deterministic `rand_generator`.

## Parallel Execution

`use_parallel` defaults to `false` in `run_experiment`; `gsk_run` and
`scripts/run_all.ps1` pass serial execution explicitly. Serial execution is the
reproducibility baseline and avoids MATLAB process-pool source-path failures.
Set `use_parallel = true` only after a local smoke test confirms that all worker
processes can see `src/runners/run_experiment.m`, `src/common`, optimizer
folders, and the MEX bridge.
Unified seeds do not use worker identity, task IDs, parfor scheduling order,
current time, or shuffle-based seeding; serial and parfor runs call the same
seed helper for each `(dimension, function, run)` task.
