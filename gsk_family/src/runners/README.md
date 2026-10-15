# MATLAB Runners

MATLAB runner entry points belong here.

Runners should call optimizer implementations from `src/optimizers` and should
write generated results under a future `results/` folder, never under
`benchmarks/cec_reference_results`.

`gskcec_require_mex.m` is the shared preflight used by the root
`run_all_cec*.m` launchers. It requires `build/mex/gskcec_eval.<mexext>` before
CEC experiments start, so missing C++/MEX prerequisites fail early with the
commands in `build.txt` instead of generating partial skipped runs.

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

The console reference-comparison table is reporting-only. It displays
`Delta(New-Old)` as zero and counts the row as `=` when the absolute difference
between the generated mean and the reference mean is below `1e-8`; this prevents
floating-point noise from being reported as a real improvement or regression.

## Runner lifecycle

| Stage | Activated when | Effect on reproducibility/performance |
|---|---|---|
| Preflight | Any non-`sphere` suite | Fails early if the MEX bridge is missing, avoiding all-skipped result trees. |
| Resume scan | Output directory already exists | Reuses only per-run rows whose stored seed matches the active schedule. |
| Seed schedule | Every run cell | Writes `seed_schedule.csv` and passes deterministic seeds into optimizers. |
| Fair-start `X0` | `seed_policy='unified'` | Gives every optimizer the same initial population and post-initialization RNG state. |
| Problem construction | Each `(function, dimension)` cell | Creates a row-wise MATLAB objective wrapper around the C++ benchmark handle. |
| Optimizer call | Each missing run | Runs one optimizer with the prepared `problem` and `options`. |
| Summary refresh | End of each dimension/group | Archives fixed-name artifacts, writes summaries, curves, logs, and environment metadata. |
| Reference comparison | Matching imported table exists | Prints publication-facing comparison rows without changing result data. |

Small example: with `base_seed = 20240620`, `D = 10`, `func = 1`, and `run = 1`,
`get_cec_seed` returns `32240721`. In unified mode every optimizer in that cell
receives that same seed and the same `X0`. If the existing `per_run.csv` already
contains run 1 with seed `32240721`, the runner skips the expensive optimizer
call and reports the cell as resumed.
