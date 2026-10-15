# configs

Experiment configuration files in a small, strict YAML subset (`key: value`
lines, `[a, b, c]` lists, `all` for every function/dimension, `#` comments; a
leading UTF-8 byte-order mark is accepted). Parsed by
`gskcec::load_experiment_config`; unknown keys are rejected with a line number,
so a typo can never silently change an experiment.

| File | What it runs |
|---|---|
| `smoke.yml` | one optimizer, one function, tiny budget - a fast end-to-end check |
| `all_cec2017.yml` | all seven optimizers (incl. `dt-gsk`) on the full CEC2017 matrix |
| `all_cec2011.yml` | all seven optimizers (incl. `dt-gsk`) on the 22 CEC2011 problems |
| `agsk_cec2020.yml` | AGSK on CEC2020, its native suite |

`all_cec2017.yml` excludes F2 so the full matrix matches the published
comparison protocol.

Keys: `optimizers` (required), `suite` (required), `functions`, `dimensions`,
`runs`, `seed` (integer in `[0, 2^53]`), `seed_policy`, `rand_generator`,
`max_evaluations` (0 = suite default budget), `overwrite`, `parallel` (must be
`false`), `reference_root`, `output_root` (relative roots resolve under
`--root`). An empty list `[]` for `functions`/`dimensions` is rejected (use
`all`), and a `data_root` key is rejected with a clear error: benchmark data
always loads from `<root>/benchmarks/cec_suite_cpp/<suite>/input_data`. Run one
with `gsk_run --config configs/<file>.yml --root .`.

`seed` is the runner `base_seed`. `gsk_run` defaults to
`seed_policy: reference` and `rand_generator: threefry`, and the shipped configs
write those values explicitly for protocol clarity. The reference policy is the
published-table schedule: GSK/ATMALS-GSK/eGSK use
`base_seed + 9973*func + run-1`; AGSK/APGSK/FDB-AGSK use `D*func*run`.
Under reference mode, AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK use legacy `seed`;
GSK uses `twister`. DT-GSK is unified-only: under every `seed_policy` it gets
the unified seed below and `threefry` (its reference campaign used that
schedule) and samples its own `NP = 5*D` initial population.
Select `unified` only for new fair cross-family experiments. Unified mode uses:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

The formula is intentionally independent of optimizer name, optimizer index,
population size, and budget. For the same `(dim, function, run)` key, every
optimizer receives the same seed. The MATLAB runner then generates the first
population outside the optimizer (for every optimizer except DT-GSK), passes it
through `options.initial_population`, restores the post-initialization RNG
state inside the optimizer, and forces
one resolved generator for the whole family: `threefry` when available,
otherwise `twister`. This makes unified mode useful for new cross-family
fairness studies, not for published-table reproduction.
Select `native` or `derived` only for the optimizer/suite-hashed diagnostic
schedule documented in `docs/reference/seed_policy.md`.

Existing result trees are protected in both run modes. With `overwrite: false`,
`run_experiment` resumes from `summary/per_run.csv`, skips completed run ids only
when their stored seed, budget (`max_nfes`) and generator match the active run,
appends missing or stale rows (another seed, budget or generator), and archives
fixed-name refreshed artifacts under
`_archive/<timestamp>/`. With `overwrite: true`, the previous active
`results/<optimizer>/<suite>` tree is moved to `_overwrite_archive/<suite>_<timestamp>/`
under the same parent before a clean replacement tree is created.

## Choosing a configuration

| Goal | Recommended file | Rationale |
|---|---|---|
| Check that the compiled CLI and reference-table comparison work | `smoke.yml` | Small budget, fast feedback, safe before long MATLAB runs. |
| Reproduce or compare full CEC2017 GSK-family behavior | `all_cec2017.yml` | Uses the standard dimensions and excludes F2 from default aggregate comparison. |
| Study real-world constrained/engineering functions | `all_cec2011.yml` | Uses native per-problem dimensions and raw objective statistics. |
| Study AGSK on its native CEC2020 setup | `agsk_cec2020.yml` | CEC2020 has suite-specific dimensions and budgets. |

Minimal custom example:

```yaml
optimizers: [gsk, egsk]
suite: cec2017
functions: [1, 3, 4]
dimensions: [10]
runs: 3
seed: 20240620
seed_policy: unified
rand_generator: threefry
max_evaluations: 0
overwrite: false
parallel: false
output_root: results
```

Use `unified` for new fair algorithm comparisons and `reference` for
published-table reproduction checks. Do not mix the two policies in one table
without labeling the results, because the random streams and initial populations
are deliberately different.
