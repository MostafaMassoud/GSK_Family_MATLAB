# GSK MATLAB Source

All GSK-family algorithm code belongs here as MATLAB source. This `src` folder
is not used for C++ CEC code.

Expected layout:

```text
common/
optimizers/gsk/
optimizers/agsk/
optimizers/apgsk/
optimizers/atmals-gsk/
optimizers/egsk/
optimizers/fdb-agsk/
optimizers/dt-gsk/
experiments/
runners/
tests/
```

Rules:

- Keep GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, and DT-GSK in MATLAB.
- Keep provenance notes in local README/help text and `docs/reference/porting_notes.md`.
- Do not translate GSK-family optimizers into C++.
- Do not put CEC suite code, CEC input data, or CEC C++ tooling here.
- Do not add Python scripts or Python wrappers.
- Keep experiment seed scheduling in `src/runners`. Optimizers receive
  `options.seed` and `options.rand_generator`; under unified mode they may also
  receive runner-owned `options.initial_population` and
  `options.rng_state_after_initialization` so fair-start experiments share the
  same seed, `X0`, and post-`X0` random stream position. DT-GSK is the
  exception: it is unified-only (unified seed and `threefry` under every
  `seed_policy`), samples its own `NP = 5*D` population from its own Threefry
  substreams, and ignores a runner `X0` (see `optimizers/dt-gsk/README.md`).

## How the MATLAB layer is activated

The MATLAB layer is entered in two common ways:

| Entry path | Intended use | What happens next |
|---|---|---|
| Root `run_all_cec*.m` | Reproducible CEC campaigns from MATLAB | Adds paths, checks the MEX bridge, calls `run_experiment`, verifies the unified seed schedule. |
| Direct `run_experiment(...)` | Focused experiments, tests, or diagnostics | Builds `problem` structs, schedules seeds, runs one optimizer, writes result artifacts. |
| Direct `<optimizer>_optimize(problem, options)` | Unit tests and algorithm-level research | Runs one optimizer without file I/O; the caller owns the problem, options, seed, and result handling. |

The separation is intentional. Runners can evolve result-management behavior
without touching the algorithm equations, while optimizers can be compared under
the same problem and seed contract.

## Minimal direct-call example

```matlab
addpath(genpath('src'));   % run from the gsk_family project root

problem.suite = 'sphere';
problem.func_id = 1;
problem.dim = 2;
problem.lb = [-5 -5];
problem.ub = [5 5];
problem.optimum = 0;
problem.evaluate = @(pop) sum(pop.^2, 2);
problem.max_nfes = 1000;
problem.target_error = 1e-8;

options.seed = 20240620;
options.rand_generator = 'twister';

result = gsk_optimize(problem, options);
```

`dt_gsk_optimize(problem, options)` takes the same arguments but requires
`options.rand_generator = 'threefry'` (empty/`'auto'`/`'default'` accepted).

This direct pattern is useful for teaching and debugging. For publication
experiments, prefer `run_experiment` or the root launchers so seed schedules,
output schemas, resume behavior, and verification are recorded automatically.
