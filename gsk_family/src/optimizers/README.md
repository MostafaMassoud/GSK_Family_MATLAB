# GSK Optimizers

Each GSK-family optimizer has its own MATLAB folder:

```text
gsk/
agsk/
apgsk/
atmals-gsk/
egsk/
fdb-agsk/
dt-gsk/
```

`dt-gsk/` (DT-GSK, the seventh optimizer) holds three code files:
`dt_gsk_optimize.m` (the whole optimizer), `dt_gsk_config.m` (the published
`pub` profile by dimension tier) and `dt_gsk_graph.m` (the interaction graph
used from D = 50). Its `README.md` is the authoritative record of behavior,
source (DT-GSK reference implementation v2.46, Python, MIT license) and
validation.

Keep variant-specific behavior visible. Do not collapse materially different
algorithms into flags on one shared implementation.

The six original optimizer entry points seed through
`src/common/gsk_set_rng.m`. Under `seed_policy='unified'`, `run_experiment.m`
may also pass `options.initial_population` and
`options.rng_state_after_initialization`; use the shared helpers so the runner
controls the fair-start `X0` and post-`X0` RNG state without rewriting
variant-specific search logic.

DT-GSK is the exception: it derives named Threefry substreams from
`options.seed`, never touches the global RNG, samples its own `NP = 5*D`
initial population and ignores a runner `X0` (documented fair-start
exception). `run_experiment` treats it as unified-only: it is scheduled with
`get_cec_seed(base_seed, dim, func, run)` and `threefry` under every
`seed_policy`, and the runner draws no `X0` for it.

Direct optimizer calls keep the conservative `twister` default (DT-GSK requires
`threefry`; empty/`auto`/`default` are accepted), while
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
