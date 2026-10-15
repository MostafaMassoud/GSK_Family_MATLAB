# GSK Optimizers

Each GSK-family optimizer has its own MATLAB folder:

```text
gsk/
agsk/
apgsk/
atmals-gsk/
egsk/
fdb-agsk/
```

Keep variant-specific behavior visible. Do not collapse materially different
algorithms into flags on one shared implementation.

All optimizer entry points seed through `src/common/gsk_set_rng.m`. Under
`seed_policy='unified'`, `run_experiment.m` may also pass
`options.initial_population` and `options.rng_state_after_initialization`; use
the shared helpers so the runner controls the fair-start `X0` and post-`X0`
RNG state without rewriting variant-specific search logic.

Direct optimizer calls keep the conservative `twister` default, while
`run_experiment` resolves unified CEC benchmark runs to `threefry` when the
installed MATLAB release supports it and falls back to `twister` otherwise.
Seed values remain optimizer-independent in unified mode; algorithm names,
worker IDs, population sizes, and evaluation budgets must not enter the seed.

## Optimizer implementation contract

Every optimizer folder should document and preserve:

| Requirement | Why it matters |
|---|---|
| Historical source file names | Lets researchers trace code back to the paper/reference release. |
| Default parameters | A changed default changes benchmark results even when the algorithm equations look unchanged. |
| RNG draw order | Reproducibility depends on both seed value and number/order of random draws. |
| Boundary handling | Repair rules change feasible search dynamics. |
| Budget crossing and target handling | Evaluation accounting is part of the published protocol. |
| Known quirks | Some reference behaviors look wrong but are required for faithful reproduction. |

When adding a new variant, start by copying the smallest existing pattern:

1. create `src/optimizers/<slug>/<slug>_optimize.m` or an equivalent MATLAB-valid
   function name;
2. require `options.seed` and call `gsk_set_rng(options)` first;
3. initialize through `gsk_initial_population_from_options` if the variant uses
   ordinary uniform initialization;
4. return the exact result fields listed in `docs/reference/matlab_interface.md`;
5. add a local README and an algorithm page under `docs/algorithms/`;
6. add a smoke test under `src/tests/`.

Avoid moving variant-specific code into shared helpers only because two formulas
look similar. A shared helper is justified only when the reference behavior is
actually the same, including rounding, indexing, random draws, and tie handling.
