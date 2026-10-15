# MATLAB Runners

MATLAB runner entry points belong here.

Runners should call optimizer implementations from `src/optimizers` and should
write generated results under a future `results/` folder, never under
`benchmarks/cec_reference_results`.

`gskcec_require_mex.m` is the shared preflight used by the root
`run_all_cec*.m` launchers (and by `run_experiment` for CEC suites). It requires
`build/mex/gskcec_eval.<mexext>` before CEC experiments start, and it forces a
real load (a bare `gskcec_eval()` call that creates no handle), so missing
C++/MEX prerequisites fail early with the commands in `build.txt` instead of
generating partial skipped runs. A bridge that exists but cannot be loaded, for
example because a dependent DLL is missing, fails early with
`gskcec:mexNotLoadable`.

`run_experiment.m` validates its arguments before touching anything: an
`output_dir` inside (or equal to) `benchmarks/cec_reference_results` is refused
on every run (`run_experiment:outputUnsafe`), `seed_policy` must be
`reference`/`unified`/`native`/`derived` (case-insensitive), and
`rand_generator` `auto`/`default` is rejected with `native`/`derived`
(`run_experiment:args`).

Seed policy lives at the runner boundary. `run_experiment.m` selects the
per-run seed, records it in the result artifacts, and passes it to the optimizer
through `options.seed`. Under `seed_policy='unified'`, the runner uses
`get_cec_seed(base_seed, dim, func, run)`:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

Only base seed, dimension, function, and run are allowed in that formula. The
runner also owns the fair-start population draw in unified mode: it resolves the
generator through `choose_cec_rng_generator` (`threefry` when supported,
otherwise `twister`), draws `X0`, captures the RNG state immediately after
`X0`, and passes both into the optimizer. Reference/native/derived modes omit
those internal fields so the optimizer draws its initial population in the
reference location.

DT-GSK is the exception (`is_unified_only`): under every `seed_policy` the
runner gives it `get_cec_seed(base_seed, dim, func, run)` and `threefry`, as its
reference campaign did, and draws no `X0` for it. DT-GSK samples its own
`NP = 5*D` population from Threefry substreams of that seed; the metadata
records this as `initial_population_policy`.

The console reference-comparison table is reporting-only. It displays
`Delta(New-Old)` as zero and counts the row as `=` when the absolute difference
between the generated mean and the reference mean is below `1e-8`; this prevents
floating-point noise from being reported as a real improvement or regression.

## Runner lifecycle

| Stage | Activated when | Effect on reproducibility/performance |
|---|---|---|
| Preflight | Any non-`sphere` suite | Fails early if the MEX bridge is missing or cannot be loaded, avoiding all-skipped result trees. |
| Resume scan | Output directory already exists | Reuses only per-run rows whose stored seed, budget (`max_nfes`) and generator match the active run; upgrades a pre-`max_nfes` `per_run.csv` once (archived first). |
| Seed schedule | Every run cell | Writes `seed_schedule.csv` (re-appending the active seed for a reused run whose latest row came from another configuration) and passes deterministic seeds into optimizers. |
| Fair-start `X0` | `seed_policy='unified'`, any optimizer except DT-GSK | Gives those optimizers the same initial population and post-initialization RNG state. |
| Problem construction | Each `(function, dimension)` cell | Creates a row-wise MATLAB objective wrapper around the C++ benchmark handle. |
| Optimizer call | Each missing run | Runs one optimizer with the prepared `problem` and `options`. |
| Summary refresh | End of each dimension/group | Archives fixed-name artifacts, writes summaries, curves, logs, and environment metadata. |
| Reference comparison | Matching imported table exists | Prints publication-facing comparison rows without changing result data. |

Small example: with `base_seed = 20240620`, `D = 10`, `func = 1`, and `run = 1`,
`get_cec_seed` returns `32240721`. In unified mode every optimizer in that cell
receives that same seed (DT-GSK receives it under every policy), and every
optimizer except DT-GSK the same `X0`. If the existing `per_run.csv` already
contains run 1 with seed `32240721` and the same `max_nfes` and
`rand_generator`, the runner skips the expensive optimizer call and reports the
cell as resumed.

`verify_unified_seed_schedule.m` (called by the launchers after a
multi-optimizer unified run) compares seeds on every `(Dim,Function,Run)` key
present in two or more optimizers' schedules. Keys missing from an optimizer
(failed/skipped cells, a different functions/runs configuration) produce a
`verify_unified_seed_schedule:missingKeys` warning; only a seed mismatch
(`verify_unified_seed_schedule:seedMismatch`) fails.
