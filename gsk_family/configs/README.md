# configs

Experiment configuration files in a small, strict YAML subset (`key: value`
lines, `[a, b, c]` lists, `all` for every function/dimension, `#` comments).
Parsed by `gskcec::load_experiment_config`; unknown keys are rejected with a
line number, so a typo can never silently change an experiment.

| File | What it runs |
|---|---|
| `smoke.yml` | one optimizer, one function, tiny budget - a fast end-to-end check |
| `all_cec2017.yml` | every optimizer on the full CEC2017 matrix |
| `all_cec2011.yml` | every optimizer on the 22 CEC2011 problems |
| `agsk_cec2020.yml` | AGSK on CEC2020, its native suite |

`all_cec2017.yml` excludes F2 so the full matrix matches the published
comparison protocol.

Keys: `optimizers`, `suite`, `functions`, `dimensions`, `runs`, `seed`,
`seed_policy`, `rand_generator`, `max_evaluations` (0 = suite default budget),
`overwrite`, `parallel` (must be `false`), `data_root`, `reference_root`,
`output_root`. Run one with `gsk_run --config configs/<file>.yml --root .`.

`seed` is the runner `base_seed`. `gsk_run` defaults to
`seed_policy: reference` and `rand_generator: threefry`, and the shipped configs
write those values explicitly for protocol clarity. The reference policy is the
published-table schedule: GSK/ATMALS-GSK/eGSK use
`base_seed + 9973*func + run-1`; AGSK/APGSK/FDB-AGSK use `D*func*run`.
Under reference mode, AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK use legacy `seed`;
GSK uses `twister`.
Select `unified` only for new fair cross-family experiments. Unified mode uses:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

The formula is intentionally independent of optimizer name, optimizer index,
population size, and budget. For the same `(dim, function, run)` key, every
optimizer receives the same seed. The MATLAB runner then generates the first
population outside the optimizer, passes it through `options.initial_population`,
restores the post-initialization RNG state inside the optimizer, and forces
one resolved generator for the whole family: `threefry` when available,
otherwise `twister`. This makes unified mode useful for new cross-family
fairness studies, not for published-table reproduction.
Select `native` or `derived` only for the optimizer/suite-hashed diagnostic
schedule documented in `docs/reference/seed_policy.md`.

Existing result trees are protected in both run modes. With `overwrite: false`,
`run_experiment` resumes from `summary/per_run.csv`, skips completed run ids only
when their stored seed matches the active schedule, appends missing or
stale-seed rows, and archives fixed-name refreshed artifacts under
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
