# Configuration

> **What this is:** a reference for configuring a run - every accepted YAML
> field, its default, and the equivalent `gsk_run` command-line flag.
> **For:** anyone setting up a repeatable experiment campaign or tuning a single
> run.
> **Prerequisites:** you can already run the project (see
> [tutorial.md](tutorial.md)). Terms are defined in
> [glossary.md](../reference/glossary.md); seed behavior is detailed in
> [seed_policy.md](../reference/seed_policy.md).
> **After reading:** you will be able to write a valid config, understand each
> field's effect and default, drive the same run from CLI flags, and turn
> parallel execution off.

`build\gsk_run.exe` accepts either a YAML configuration file or direct
command-line arguments; both build the same in-memory request that is handed to
`run_experiment.m`. **Prefer YAML for campaigns** - it keeps every parameter in
versioned text, so a run is reproducible and reviewable. Use direct CLI flags for
a quick one-off cell. The config format is a small, strict flat-YAML subset
(`key: value` lines, `[a, b, c]` lists, `all` for every function/dimension, `#`
comments) parsed by the C++ loader `gskcec::load_experiment_config`. The
canonical field reference is `configs/README.md`.

## Minimal YAML

A complete, valid config needs only a suite plus the cells to run; everything
else has a default. This illustrative example runs one optimizer on a few
CEC2017 functions at the suite-default budget:

```yaml
optimizers: [gsk]
suite: cec2017
functions: [1, 3, 4]
dimensions: [10]
runs: 3
seed: 20240620
seed_policy: reference
rand_generator: threefry
max_evaluations: 0
overwrite: false
parallel: false
output_root: results
```

Run a saved config file with:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

`--root .` rewrites relative `output_root`, `reference_root`, and `data_root`
values under the current project root, so configs move between machines cleanly.
The shipped configs are `smoke.yml` (one optimizer, one function, tiny budget),
`all_cec2017.yml` (every optimizer on the full CEC2017 matrix, F2 excluded),
`all_cec2011.yml` (every optimizer on the 22 CEC2011 problems), and
`agsk_cec2020.yml` (AGSK on its native CEC2020 suite).

## Fields

The table lists each accepted key, its default, and what it does. Any key not
listed here is rejected with a line number, so a typo fails fast rather than
silently changing an experiment.

| Field | Default | Meaning |
|---|---|---|
| `optimizers` | `[gsk]` | Optimizer ids to run. Use ids from `gsk_list --optimizers`: `gsk agsk apgsk atmals-gsk egsk fdb-agsk`. |
| `suite` | *(required)* | Benchmark suite id: `cec2011`, `cec2013`, `cec2013lsgo`, `cec2017`, or `cec2020`. |
| `functions` | suite default | Function ids, or `all`. For CEC2017 the all-optimizer config excludes withdrawn F2. |
| `dimensions` | suite default | Dimension ids, or `all`. Native-dimension suites (`cec2011`, `cec2013lsgo`) require `0`. |
| `runs` | `1` | Independent runs per `(optimizer, dimension, function)` cell. |
| `seed` | `20240620` | Base integer seed (the runner `base_seed`). |
| `seed_policy` | `reference` | `reference` (default; reproduce published tables) or `unified` (fair cross-family starts). Diagnostic values `native`/`derived` also exist; see [seed_policy.md](../reference/seed_policy.md). |
| `rand_generator` | `threefry` | Requested RNG family, usually `threefry` or `twister`. Reference mode overrides the effective generator (see below). |
| `max_evaluations` | `0` (suite default) | Optional reduced budget in NFEs (`max_nfes`). `0` uses the suite's full protocol budget. |
| `output_root` | `results` | Generated result root. Must not be inside the reference tree. |
| `reference_root` | `benchmarks/cec_reference_results` | Imported reference-table root used by validation. |
| `data_root` | `benchmarks/cec_suite_cpp` | Benchmark input-data root. |
| `overwrite` | `false` | `false` resumes/appends inside the existing result tree. `true` archives the previous active result tree under `_overwrite_archive/<suite>_<timestamp>/` and starts a clean replacement run. |
| `parallel` | `false` | Must be `false`. This version runs sequentially; `parallel: true` is rejected on purpose. |

These keys and their handling are defined by the C++ loader; the canonical list
is in `configs/README.md`. You do not need to set `output_root`,
`reference_root`, or `data_root` for a normal run - the defaults plus `--root .`
cover it.

## Optimizer options

Per-optimizer parameters (population size, `kf`/`kr`/`k`/`p`, `fdb_case`,
`protocol`, `use_fmincon`, parameter pools, and similar) are **not** YAML config
keys and **not** `gsk_run` flags. The config and the CLI always use each
optimizer's interface-default population and reference defaults. To set them, use
the lower-level MATLAB path - build a problem with
`gskcec_make_problem(suite, func, dim, project_root, max_nfes)` and call
`<name>_optimize(problem, options)` directly, passing an `options` struct:

```matlab
root = '<root>';
addpath(genpath(fullfile(root,'src')));      % optimizers + helpers
addpath(fullfile(root,'build','mex'));        % the gskcec_eval bridge

problem = gskcec_make_problem('cec2017', 1, 10, root, 50000);   % budget override
options = struct('seed', 777, 'np', 100, 'kf', 0.5, 'kr', 0.9, 'k', 10, 'p', 0.1);
result  = gsk_optimize(problem, options);
gskcec_eval('free', problem.mex_handle);      % release the C++ benchmark handle
```

The interface-default populations are `np = 100` for `gsk`/`atmals-gsk`/`egsk`
and `np_init = 100` for `agsk`/`apgsk`/`fdb-agsk`. A few reference-reproduction
quirks (AGSK `40*D` for CEC2020 `D>5`; APGSK `200*D` opt-in; ATMALS-GSK
`protocol` selection; eGSK `use_fmincon`; FDB-AGSK `fdb_case` 1..5) are described
per optimizer in [runbook.md](runbook.md) section 3 and the option contract in
[matlab_interface.md](../reference/matlab_interface.md).

## Direct CLI equivalent

Direct CLI arguments build the same request as a YAML file. This is convenient
for a single cell:

```powershell
build\gsk_run.exe --optimizer agsk --suite cec2020 --dimension 10 `
    --function 1 --runs 5 --seed 20240620 --max-evaluations 1000
```

The flag-to-config mapping:

| Config key | `gsk_run` flag | Notes |
|---|---|---|
| `optimizers` | `--optimizer <name>` | one optimizer per invocation |
| `suite` | `--suite <name>` | |
| `functions` | `--function N` | repeat the flag for several functions |
| `dimensions` | `--dimension D` | repeat the flag; native-dim suites use `0` |
| `max_evaluations` | `--max-evaluations M` | `0` = suite default budget |
| `runs` | `--runs R` | |
| `seed` | `--seed S` | the `base_seed` |
| `seed_policy` | `--seed-policy <policy>` | `reference` (default) / `unified` / `native` / `derived` |
| `rand_generator` | `--rand-generator <family>` | `threefry` (default) / `twister` |
| `output_root` | `--output <dir>` | the per-(opt,suite) tree is created under it |
| `reference_root` | `--reference <dir>` | used for auto-verification |

A few extra flags have no config equivalent: `--root .` (rewrite relative roots
under the project root), `--matlab <exe>` (locate MATLAB - else the
`GSKCEC_MATLAB` environment variable, else `matlab` on `PATH`), `--dry-run`
(print the MATLAB `-batch` command without running), and `--no-verify` (skip the
automatic `verification.json` check). Run `build\gsk_run.exe --help` to see the
complete set.

### Seed policy and generator

The orchestrator and the shipped configs default to
`--seed-policy reference --rand-generator threefry`, the published-table
schedule. Under reference mode the effective generator is overridden:
AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK use the legacy `seed` stream, while GSK uses
`twister`. For new fair cross-family experiments, choose `unified`: it gives
every optimizer the same seed over `(dimension, function, run)`, draws the
initial population once in the runner, restores the post-initialization RNG state
inside each optimizer, and uses `threefry` when MATLAB supports it (otherwise
`twister`). The unified seed is:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

The formula deliberately excludes optimizer name, optimizer index, population
size, budget, and suite name, so the algorithm cannot move its own seed. Do not
mix `reference` and `unified` results in one table without labeling them - the
random streams and initial populations are intentionally different. The full
rules are in [seed_policy.md](../reference/seed_policy.md).

## Disabling parallel execution

Runs are **sequential by default** in this version. `parallel: true` in a config
is rejected; only `parallel: false` is accepted (and it is the default), so a
config that omits `parallel` already runs serially.

```yaml
parallel: false
```

The `gsk_run` orchestrator always runs MATLAB serially. The optional parfor path
exists only on the MATLAB direct route, where you can opt in with
`'use_parallel',true`:

```matlab
run_experiment('optimizer','gsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',3, ...
    'project_root','<root>', 'output_dir','<root>/results/gsk/cec2017', ...
    'use_parallel',true)
```

Use serial execution (the default) for step-through debugging or a strict
single-thread reproducibility check; enable parfor only when the throughput
matters and per-task determinism does not. Parallel and serial runs share the
same deterministic seed schedule, so matching cells should still match - see
[troubleshooting.md](troubleshooting.md#parallel-and-serial-results-differ).
