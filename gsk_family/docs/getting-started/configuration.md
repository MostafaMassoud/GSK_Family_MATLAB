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
comments; a leading UTF-8 byte-order mark is accepted) parsed by the C++ loader
`gskcec::load_experiment_config`. The canonical field reference is
`configs/README.md`.

## Minimal YAML

A complete, valid config needs only `optimizers` and `suite` (plus the cells to
run); everything else has a default. This illustrative example runs one
optimizer on a few CEC2017 functions at the suite-default budget:

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

`--root` rebases relative `output_root` and `reference_root` values from the
config under the given project root, so a config behaves the same from any
working directory. Explicit `--output` / `--reference` CLI flags resolve against
the working directory instead.
The shipped configs are `smoke.yml` (one optimizer, one function, tiny budget),
`all_cec2017.yml` (all seven optimizers, `dt-gsk` included, on the full
CEC2017 matrix, F2 excluded), `all_cec2011.yml` (all seven on the 22 CEC2011
problems), and `agsk_cec2020.yml` (AGSK on its native CEC2020 suite). For
DT-GSK on the other suites, list `dt-gsk` in `optimizers` of your own config,
or use `--optimizer dt-gsk`.

## Fields

The table lists each accepted key, its default, and what it does. Any key not
listed here is rejected with a line number, so a typo fails fast rather than
silently changing an experiment.

| Field | Default | Meaning |
|---|---|---|
| `optimizers` | *(required)* | Optimizer ids to run (at least one; `optimizer` is accepted as an alias). Use ids from `gsk_list --optimizers`: `gsk agsk apgsk atmals-gsk egsk fdb-agsk dt-gsk`. A config without it is rejected (`no optimizers given`). |
| `suite` | *(required)* | Benchmark suite id: `cec2011`, `cec2013`, `cec2013lsgo`, `cec2017`, or `cec2020`. |
| `functions` | suite default | Function ids, or `all`. For CEC2017 the all-optimizer config excludes withdrawn F2. An empty list `[]` is rejected (use `all`). |
| `dimensions` | suite default | Dimension ids, or `all`. Native-dimension suites (`cec2011`, `cec2013lsgo`) require `0`. An empty list `[]` is rejected (use `all`). |
| `runs` | `1` | Independent runs per `(optimizer, dimension, function)` cell. |
| `seed` | `20240620` | Base seed (the runner `base_seed`): a non-negative integer in `[0, 2^53]`; negative or non-integer values are rejected. |
| `seed_policy` | `reference` | `reference` (default; reproduce published tables) or `unified` (fair cross-family starts). Diagnostic values `native`/`derived` also exist; see [seed_policy.md](../reference/seed_policy.md). It does not change `dt-gsk`'s seeds, which are always the unified ones (see below). |
| `rand_generator` | `threefry` | Requested RNG family, usually `threefry` or `twister`. Reference mode overrides the effective generator (see below); `dt-gsk` always uses `threefry`. |
| `max_evaluations` | `0` (suite default) | Optional reduced budget in NFEs (`max_nfes`). `0` uses the suite's full protocol budget. |
| `output_root` | `results` | Generated result root; a relative value resolves under `--root`. Must not be inside the reference tree (`run_experiment:outputUnsafe`). |
| `reference_root` | `benchmarks/cec_reference_results` | Imported reference-table root used by validation; a relative value resolves under `--root`. |
| `overwrite` | `false` | `false` resumes/appends inside the existing result tree. `true` archives the previous active result tree under `_overwrite_archive/<suite>_<timestamp>/` and starts a clean replacement run. |
| `parallel` | `false` | Must be `false`. This version runs sequentially; `parallel: true` is rejected on purpose. |

These keys and their handling are defined by the C++ loader; the canonical list
is in `configs/README.md`. There is no `data_root` key: benchmark data always
loads from `<root>/benchmarks/cec_suite_cpp/<suite>/input_data`, and a
`data_root` line is rejected by the parser. You do not need to set
`output_root` or `reference_root` for a normal run - the defaults plus
`--root .` cover it.

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
and `np_init = 100` for `agsk`/`apgsk`/`fdb-agsk`. `dt-gsk` reads only
`seed`, `rand_generator` (which must be `threefry`) and the optional `np_init`
(replaces its `NP = 5*D` start; a variant, not the published setting). Every
other setting comes from the `pub` profile in
`src/optimizers/dt-gsk/dt_gsk_config.m`. To give every optimizer the same
initial population (for example 100, so DT-GSK matches the others), set
`np_init` in a launcher's CONFIG block or pass `'np_init', 100` to
`run_experiment`; `min_pop_size` likewise sets the final population size of
AGSK, APGSK, FDB-AGSK and DT-GSK. See the command reference, "Population size". A few
reference-reproduction quirks (AGSK `40*D` for CEC2020 `D>5`; APGSK `200*D`
opt-in; ATMALS-GSK `protocol` selection; eGSK `use_fmincon`; FDB-AGSK
`fdb_case` 1..5) are described per optimizer in
[command_reference.md](command_reference.md) section 3 and the option contract in
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
| `functions` | `--function N` | one integer per flag; repeat the flag for several functions (`--function 1 --function 3`; `1,3` is rejected) |
| `dimensions` | `--dimension D` | one integer per flag; repeat the flag; native-dim suites use `0` |
| `max_evaluations` | `--max-evaluations M` | one integer `>= 0`; `0` = suite default budget |
| `runs` | `--runs R` | one whole integer `>= 1` (`2.9` is rejected) |
| `seed` | `--seed S` | the `base_seed`; an integer in `[0, 2^53]` |
| `seed_policy` | `--seed-policy <policy>` | `reference` (default) / `unified` / `native` / `derived` |
| `rand_generator` | `--rand-generator <family>` | `threefry` (default) / `twister` |
| `output_root` | `--output <dir>` | the per-(opt,suite) tree is created under it; the flag resolves against the working directory |
| `reference_root` | `--reference <dir>` | used for auto-verification; the flag resolves against the working directory |

Each numeric flag takes exactly one whole integer; anything else (comma lists,
fractions, trailing text) fails with a clear message and exit code 2 instead of
being silently truncated.

A few extra flags have no config equivalent: `--root .` (the project root;
relative `output_root` / `reference_root` from a config resolve under it),
`--matlab <exe>` (locate MATLAB - else the
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
random streams and initial populations are intentionally different.

`dt-gsk` is the exception: it is *unified-only*. Whatever `seed_policy` and
`rand_generator` say, the runner gives it this unified seed and `threefry` (the
protocol its imported reference campaigns used), and DT-GSK samples its own
`NP = 5*D` initial population rather than the runner's shared one (a documented
fair-start exception; see
[Unified-only optimizers](../reference/seed_policy.md#unified-only-optimizers-dt-gsk)).
The full rules are in [seed_policy.md](../reference/seed_policy.md).

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
