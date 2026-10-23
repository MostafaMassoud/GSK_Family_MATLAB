# MATLAB Optimizer Interface

> **What this is:** the struct-level contract (problem, options, result) that
> every GSK-family optimizer under `src/optimizers` must honor. **For:**
> contributors editing or adding an optimizer, and anyone calling one directly.
> **Prerequisites:** the language split in [architecture.md](architecture.md) and
> the seed contract in [seed_policy.md](seed_policy.md). **After reading** you
> will know the exact fields an optimizer reads and returns, the entry points,
> and the shared helpers.

This contract binds every GSK-family optimizer under `src/optimizers`, the
shared helpers under `src/common`, and the runners under `src/runners`.
GSK-family algorithm code is MATLAB-only and lives under `src/`; CEC
benchmark evaluation is C++ under `benchmarks/` and reaches MATLAB through
the `gskcec_eval` MEX bridge (see `docs/reference/architecture.md`).

## Problem struct

Runners construct a `problem` struct and pass it to optimizers. Optimizers
must use only these fields:

| Field | Type | Meaning |
|---|---|---|
| `suite` | char | e.g. `'cec2017'`, `'sphere'` (tests) |
| `func_id` | double | function id within the suite |
| `dim` | double | problem dimension `D` |
| `lb` | 1xD double | lower bounds |
| `ub` | 1xD double | upper bounds |
| `optimum` | double | known optimum value, `NaN` when unknown |
| `evaluate` | function handle | `fitness = problem.evaluate(pop)` with `pop` NPxD (row = candidate), returns NPx1 |
| `max_nfes` | double | evaluation budget |
| `target_error` | double | reference target threshold (e.g. `1e-8`), `NaN` to disable |

The row-wise population convention follows the reference MATLAB optimizers.
Any transposition needed by an evaluation backend happens inside
`problem.evaluate`, never inside optimizer code.

CEC experiments require the project-local `build/mex/gskcec_eval.<mexext>`
bridge. `run_all_cec*.m` and `run_experiment` check this prerequisite before
starting, so a missing bridge fails before partial result folders are written.
The check also forces a real load of the bridge (a bare `gskcec_eval()` call that
creates no handle), so a bridge that exists but cannot be loaded (for example a
missing dependent DLL) raises `gskcec:mexNotLoadable` at that point too.
Build commands are kept in `build.txt`.

## Options struct

| Field | Type | Meaning |
|---|---|---|
| `seed` | double | required; optimizer must seed through `gsk_set_rng(options)` first (DT-GSK instead derives its own Threefry substreams from it; see below) |
| `rand_generator` | char | optional; `threefry`, `twister`, `seed`, or `state` (DT-GSK requires `threefry` or empty/`auto`/`default`; anything else raises `dt_gsk_optimize:options`) |
| `initial_population` | NPxD double | internal runner field for unified fair-start mode; optimizer uses this as `X0` instead of drawing its own first population |
| `rng_state_after_initialization` | struct | internal runner field for unified fair-start mode; optimizer restores this RNG state after accepting `initial_population` |
| variant fields | - | optional variant parameters; defaults must equal the reference values |

`initial_population` and `rng_state_after_initialization` are runner-owned
fields, not ordinary user-tuning knobs. `run_experiment` sets them only under
`seed_policy='unified'`: it computes `get_cec_seed(base_seed, dim, func, run)`,
sets `rng(seed,rng_generator)`, draws the first population outside the optimizer,
captures `rng` immediately after that draw, and passes both fields into the
optimizer. Each optimizer then uses the supplied `X0` and restores the captured
post-`X0` stream state so that every algorithm starts the same `(dim,func,run)`
cell from the same seed, first population, and next random-number position.
Reference, native, and derived runs omit these fields, so optimizers draw their
initial population in their normal reference location.

**DT-GSK fair-start exception.** `dt_gsk_optimize` samples its own `NP = 5*D`
(or `options.np_init`) initial population from its `init` Threefry substream and ignores
`initial_population` and `rng_state_after_initialization` if they are
supplied. Every random draw comes from named `RandStream('threefry')`
substreams derived from `options.seed`; the global RNG is never touched and
`gsk_set_rng` is not called. `run_experiment` does not draw a runner `X0` for
it under any policy, and always passes the unified seed with `threefry` (see
[seed_policy.md](seed_policy.md#unified-only-optimizers-dt-gsk)). Two DT-GSK
runs with the same seed are identical; DT-GSK and a runner-`X0` optimizer share
the seed of a `(dim, func, run)` cell but not its first population.

Variant parameter fields (all optional, reference defaults apply):

- `gsk`: `np` (100), `kf` (0.5), `kr` (0.9), `k` (10), `p` (0.1)
- `agsk`: `np_init` (100), `min_pop_size` (12; must be >= 11, and `np_init >=
  min_pop_size`, otherwise `agsk_optimize:options`)
- `apgsk`: `np_init` (100; `200*D`/`250` reference policy opt-in), `min_pop_size`
  (12; same `>= 11` / `np_init >= min_pop_size` rule, `apgsk_optimize:options`);
  the KF/KR pools, negative KF pool, senior `p`, and the gate/junior-schedule
  constants are fixed reference values (not options)
- `atmals-gsk`: reference value ranges, `protocol` (`'cec2017'` default or `'cec2011'`)
- `egsk`: reference `KF1/KF2/KR/K`, `use_fmincon` (`true` reference default;
  `false` only for explicit non-reference diagnostics)
- `fdb-agsk`: `fdb_case` (1..5, default 1), `np_init` (100; `40*D` reference harness opt-in)
- `dt-gsk`: `np_init` (`5*D`) and `min_pop_size` (the final NLPSR size
  `n_min`: 12, or 25 for `D >= 50`), each an integer `>= 5` and a non-`pub`
  variant when set; every other setting comes from the published `pub`
  profile, `dt_gsk_config(D)`, by dimension tier (`D < 20`, `20 <= D < 50`,
  `D >= 50`, `D >= 100`)

The runner's `'np_init'` and `'min_pop_size'` arguments set these for the
whole family; see the command reference, "Population size".

## Result struct

Every optimizer returns a struct with exactly these fields:

| Field | Type | Meaning |
|---|---|---|
| `optimizer` | char | e.g. `'gsk'` |
| `suite`, `func_id`, `dim` | - | copied from problem |
| `seed` | double | the deterministic seed used |
| `best_x` | 1xD double | best solution found |
| `best_fitness` | double | best raw objective value |
| `error` | double | `best_fitness - problem.optimum`, `NaN` when optimum is `NaN`; target-threshold zeroing applied. Exception: ATMALS-GSK on CEC2017 reports `abs(best_fitness - optimum)` with the standard `1e-8` zero cutoff. |
| `nfes` | double | function evaluations consumed. GSK, AGSK, APGSK, ATMALS-GSK, FDB-AGSK, and DT-GSK never report more than `max_nfes` (ATMALS-GSK and FDB-AGSK clip the reported value; their internal per-child counter can read `max_nfes + 1` on a budget-crossing generation; DT-GSK evaluates only the rows that still fit, so it ends at exactly `max_nfes`). eGSK can exceed `max_nfes` by its counted IP (`fmincon`) evaluations. |
| `termination` | char | `'max_evaluations'` or `'target_error_reached'` (DT-GSK: always `'max_evaluations'`) |
| `convergence` | struct | `.nfes` (Gx1) and `.best_fitness` (Gx1), recorded once per generation (DT-GSK: the best-so-far value after each generation) |
| `runtime_seconds` | double | wall time of the optimization loop |
| `params` | struct | the variant parameters actually used. DT-GSK: `profile` (`'pub'`), `np_init_mult` (5), `np_init` (initial NP used), `n_min` (final NLPSR size used: tier value or `min_pop_size`), the base `KF`/`KR`/`Kexp` (reported only; ACE picks the per-individual values), `restarts_done` (partial BSE restarts), `max_nfes` |
| `notes` | char | optional free text (e.g. eGSK non-reference `use_fmincon=false` diagnostics; DT-GSK always `'self-init (fair-start exception)'`), `''` otherwise |

## Entry points

External optimizer identifiers are hyphenated (`atmals-gsk`, `fdb-agsk`,
`dt-gsk`) in configs, CLI commands, result folders, and reference folders. The
MATLAB function names below keep underscores because MATLAB function
identifiers cannot contain hyphens.

```text
src/optimizers/gsk/gsk_optimize.m
src/optimizers/agsk/agsk_optimize.m
src/optimizers/apgsk/apgsk_optimize.m
src/optimizers/atmals-gsk/atmals_gsk_optimize.m
src/optimizers/egsk/egsk_optimize.m
src/optimizers/fdb-agsk/fdb_agsk_optimize.m
src/optimizers/dt-gsk/dt_gsk_optimize.m
```

each with signature `result = <name>_optimize(problem, options)`.

## Shared helpers (`src/common`)

Faithful ports of genuinely shared reference behavior. Variant-specific
behavior stays inside the variant folder - do not over-factor.

- `Gained_Shared_Junior_R1R2R3.m`, `Gained_Shared_Senior_R1R2R3.m`:
  reference donor-index helpers, names preserved for traceability.
- `gsk_init_population.m`: uniform initialization within bounds.
- `gsk_bound_repair.m`: midpoint repair (reference rule).
- `gsk_reduction_survivors.m`: indices kept by linear population reduction
  (remove worst by current fitness).

DT-GSK uses none of these helpers: its donors, bound repair, population
reduction, and RNG streams are local to `src/optimizers/dt-gsk/`
(`dt_gsk_optimize.m`, `dt_gsk_config.m`, `dt_gsk_graph.m`), following its
reference implementation rather than the MATLAB GSK sources.

## Reproducibility

- Deterministic modes derive per-run seeds using the policy in
  `docs/reference/seed_policy.md` and record them in every output artifact.
- Under runner reference mode, AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK use
  deterministic legacy `seed`; GSK uses `twister`.
- Under runner unified mode, all optimizers use
  `get_cec_seed(base_seed, dim, func, run)`:
  `mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1`.
  The formula intentionally excludes optimizer name, algorithm index,
  population size, suite name, budget, and every other algorithm-specific
  value. The effective unified generator is `threefry` when supported by the
  installed MATLAB, otherwise `twister`.
- DT-GSK is unified-only: under every runner policy (`reference`, `unified`,
  `native`, `derived`) it gets `get_cec_seed(base_seed, dim, func, run)` and
  `threefry`, as in its reference campaign.
- An optimizer run is fully determined by `(problem, options.seed,
  options.rand_generator, variant options)`. Wall-clock seeding is not a
  supported run mode.

## Toolbox policy

- eGSK reference mode requires `fmincon` (SQP) for the IP local refinement.
  Without Optimization Toolbox/fmincon, the default call raises
  `egsk:fminconUnavailable`. Passing `options.use_fmincon=false` is an explicit
  non-reference diagnostic mode and records that in `result.notes`.
- ATMALS-GSK replaces the Fuzzy Logic Toolbox `gaussmf` with a local
  mathematically identical helper (no toolbox requirement).
- DT-GSK needs no toolbox (its `RandStream('threefry')` substreams are core
  MATLAB).

## MATLAB tests

`src/tests/` holds 13 `test_*.m` smoke tests (pure-MATLAB sphere problems, tiny
budgets; `test_mex_bridge.m` is the bridge cross-check and skips when the
bridge is not built) and `run_matlab_smoke_tests.m`, which discovers and runs
every `test_*.m` and fails with a nonzero exit under `matlab -batch` on any
failure. `test_dt_gsk_smoke.m` checks the DT-GSK contract, determinism, the
ignored runner `X0`, every dimension tier, and the reference implementation's
golden values.
