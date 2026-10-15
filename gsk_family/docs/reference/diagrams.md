# Flowcharts And Diagrams

> **What this is:** A visual gallery of the project -- the MATLAB optimizer side,
> the C++ benchmark side, and the `gskcec_eval` MEX bridge between them -- drawn
> as Mermaid flowcharts. **For:** anyone who wants the shape of the system at a
> glance before reading the prose. **Prerequisites:** none; the same flows are
> described in [architecture.md](architecture.md), [benchmark_mapping.md](benchmark_mapping.md),
> and [seed_policy.md](seed_policy.md). **After reading:** you can place any file
> or stage on these diagrams and follow it to its neighbours.

Every diagram depicts the MATLAB + C++ reality: GSK-family algorithms in MATLAB
(`src/`), CEC benchmarks as standalone C++20 ports (`benchmarks/`), and the
optional MEX bridge that joins them. There is no Python in the project. Each node
uses an `id["label"]` declaration, with special-character labels quoted, so the
charts parse cleanly under Mermaid.

## Full Project Architecture

```mermaid
flowchart LR
  user["User / researcher"] --> launch["run_all_cec*.m or gsk_run CLI"]
  launch --> runner["run_experiment.m"]
  runner --> seed["Seed policy + X0 fair-start"]
  runner --> prob["gskcec_make_problem.m"]
  prob --> mex["gskcec_eval MEX bridge"]
  mex --> cpp["gskcec::make_problem (C++)"]
  cpp --> inst["BenchmarkProblem instance"]
  seed --> opt["MATLAB optimizer (src/optimizers)"]
  prob --> opt
  inst --> opt
  opt --> res["summary / per_run / curves / gen_logs"]
  res --> ver["reference comparison"]
  ref["cec_reference_results (read-only)"] --> ver
  ver --> vj["verification.json verdict"]
```

## Algorithm Execution Flow

```mermaid
flowchart TD
  s["Enter <opt>_optimize(problem, options)"] --> rng["gsk_set_rng(options): seed + generator"]
  rng --> x0{"options.initial_population set?"}
  x0 -- "yes (unified)" --> use["Use runner X0, restore post-X0 RNG state"]
  x0 -- "no (reference/native)" --> draw["Draw own initial population in bounds"]
  use --> ev["problem.evaluate(pop): NP x D -> NP x 1"]
  draw --> ev
  ev --> best["Record best-so-far"]
  best --> gen["Build junior/senior donor candidates"]
  gen --> rep["gsk_bound_repair (midpoint rule)"]
  rep --> evt["problem.evaluate(trial population)"]
  evt --> sel["Greedy or variant-specific selection"]
  sel --> upd["Update adaptive state + linear pop reduction"]
  upd --> budget{"nfes >= max_nfes?"}
  budget -- "no" --> gen
  budget -- "yes" --> ret["Return result struct"]
```

## Benchmark Evaluation Pipeline

```mermaid
flowchart LR
  pop["Optimizer population NP x D"] --> tin["evaluate handle: transpose to D x NP"]
  tin --> mex["gskcec_eval('eval', handle, X)"]
  mex --> chk{"rows == problem.dimension()?"}
  chk -- "no" --> err["gskcec:badInput error"]
  chk -- "yes" --> loop["For each column k: BenchmarkProblem.evaluate(span)"]
  loop --> row["1 x NP fitness row"]
  row --> tout["transpose back to NP x 1"]
  tout --> fit["Fitness column to optimizer"]
```

## Experiment Lifecycle

```mermaid
flowchart TD
  args["run_experiment args (optimizer, suite, funcs, dims, runs)"] --> paths["setup_paths(project_root)"]
  paths --> gate["gskcec_require_mex (CEC suites only)"]
  gate --> ow{"overwrite?"}
  ow -- "true" --> clean["Move old output tree to _overwrite_archive"]
  ow -- "false" --> resume["Load existing per_run.csv (resume/add)"]
  clean --> fresh["Create clean summary/curves/gen_logs"]
  fresh --> cell
  resume --> cell["For each (function, dimension, run) cell"]
  cell --> mk["gskcec_make_problem -> problem struct"]
  mk --> sd["get_cec_seed + draw X0 (unified)"]
  sd --> run["optimizer(problem, options)"]
  run --> pr["Append per_run.csv + seed_schedule.csv"]
  pr --> agg["Refresh summary D<dim>.csv (best..sd)"]
  agg --> cu["Write median-run curves + checkpoint gen_logs"]
  cu --> env["Write environment.json (statistics_basis, skips)"]
  env --> vj["Write verification.json verdict"]
```

## Configuration Loading

```mermaid
flowchart LR
  yml["config .yml (strict flat subset)"] --> cli["gsk_run CLI (C++)"]
  flags["gsk_run command-line flags"] --> cli
  cli --> parse["Single strict C++ parser"]
  parse --> unk{"Unknown key?"}
  unk -- "yes" --> rej["Reject with line number"]
  unk -- "no" --> fac["Validate vs benchmark factory"]
  fac --> bad{"Suite / function / dim valid?"}
  bad -- "no" --> stop["Fail before any MATLAB launch"]
  bad -- "yes" --> drive["Drive MATLAB -batch run_experiment"]
```

## Seed Generation And RNG Flow

```mermaid
flowchart TD
  base["base_seed = 20240620"] --> pol{"seed_policy?"}
  pol -- "unified" --> uni["get_cec_seed(base, dim, func, run)"]
  pol -- "reference" --> refp["per-optimizer reference seed rule"]
  pol -- "native / derived" --> der["derive_run_seed (opt+suite hashed)"]
  uni --> chooser["choose_cec_rng_generator: threefry else twister"]
  refp --> effg["effective_rand_generator per optimizer"]
  der --> passg["honour passed rand_generator"]
  chooser --> setrng["rng(seed, generator) via gsk_set_rng"]
  effg --> setrng
  passg --> setrng
  setrng --> x0["Runner draws X0 once (unified)"]
  x0 --> cap["Capture rng_state_after_initialization"]
  cap --> restore["Optimizer restores post-X0 state"]
  restore --> draws["Algorithm rand / randi / randperm draws"]
```

## Parallel parfor Execution Flow

```mermaid
flowchart LR
  cells["Resolved (function, dimension, run) cells"] --> sched["Seeds via get_cec_seed (schedule-independent)"]
  sched --> par{"use_parallel?"}
  par -- "false (default)" --> serial["Serial run loop (reproducibility baseline)"]
  par -- "true" --> pool["ensure_process_pool() + parfor"]
  pool --> workers["Workers: each rebuilds problem via MEX bridge"]
  serial --> rows["Per-run rows (same seed helper)"]
  workers --> rows
  rows --> det["Deterministic outputs: serial == parfor"]
  det --> verify["verify_unified_seed_schedule across optimizers"]
```

## Logging And Reporting Pipeline

```mermaid
flowchart TD
  res["Optimizer result struct"] --> pr["per_run.csv (seed, error, nfes, termination)"]
  res --> conv["convergence struct"]
  conv --> cu["curves/Figure_F<f>_D<d>_Run#<r>.csv (median run)"]
  conv --> ck["gen_logs/CheckpointErrors_<opt>_F<f>_D<d>.csv"]
  res --> sm["summary/<opt>_<suite>_D<dim>.csv (best..sd)"]
  cu -- "write_graphs=true" --> png["curves/graphs/Figure_F<f>_D<d>.png"]
  meta["run metadata + git_commit"] --> env["summary/environment.json"]
  sm --> cmp["reference comparison (comparison.hpp)"]
  cmp --> vj["summary/verification.json"]
```

## Optimizer Update Cycle

```mermaid
flowchart TD
  pop["Population NP x D"] --> rank["Rank by current fitness"]
  rank --> jr["Junior R1/R2/R3 indices (Gained_Shared_Junior)"]
  rank --> sr["Senior R1/R2/R3 indices (Gained_Shared_Senior)"]
  jr --> jg["Junior gained-shared vector (KF, KR)"]
  sr --> sg["Senior gained-shared vector (KF, KR)"]
  jg --> tv["Trial population (junior/senior split by knowledge ratio)"]
  sg --> tv
  tv --> rep["gsk_bound_repair (midpoint to bounds)"]
  rep --> evt["problem.evaluate(trial) via MEX bridge"]
  evt --> cmp["Greedy fitness comparison vs parent"]
  cmp --> updt["Replace improved rows; update best-so-far"]
  updt --> red["gsk_reduction_survivors (linear pop reduction)"]
```

## Validation Workflow

```mermaid
flowchart LR
  gen["Generated summary/*.csv"] --> load["Load generated table (comparison.hpp)"]
  rroot["cec_reference_results root"] --> find["Find matching optimizer/suite table"]
  find --> lref["load_reference_file (-, nan, N/A -> missing)"]
  load --> cmp["Compare stats (case-insensitive F-labels)"]
  lref --> cmp
  cmp --> hard{"Hard-failure check fires?"}
  hard -- "yes (non-finite / below floor / gross)" --> dev["DEVIATES (gsk_run exits nonzero)"]
  hard -- "no" --> con["CONSISTENT"]
  dev --> vj["verification.json"]
  con --> vj
```

## Validation Workflow -- Port Ground Truth

```mermaid
flowchart LR
  port["C++ CEC port (cec_suite_cpp/<suite>/src)"] --> probe["Evaluate fixed probe vectors"]
  data["tests/data/<suite>_expected.csv ground truth"] --> chk["Compare at suite tolerance"]
  probe --> chk
  chk --> tol{"Within tol? (1e-10 cec2017, 1e-12 cec2013 saved)"}
  tol -- "yes" --> pass["ctest CONSISTENT"]
  tol -- "no" --> fail["ctest failure"]
  bridge["gskcec_eval bridge"] -. "evaluates same port" .-> port
```

## Testing Workflow

```mermaid
flowchart TD
  build["CMake build (WinLibs GCC, -std=c++20 -static)"] --> ctest["12 ctest suites"]
  ctest --> cc["core + experiment + reference-results"]
  ctest --> cb["cec2017 / cec2013 / cec2013lsgo / cec2020"]
  ctest --> c11["cec2011 wpa / wpb / wpc + integration"]
  ctest --> bench["gsk_bench smoke CLI"]
  bench --> mexbuild["scripts/build_mex_bridge.ps1 -> build/mex/gskcec_eval.mexw64"]
  mexbuild --> smoke["MATLAB: run_matlab_smoke_tests (src/tests/test_*.m)"]
  smoke --> bridgechk["test_mex_bridge.m: bridge == original-MEX ground truth"]
  bridgechk --> green["All green: ports + optimizers + bridge verified"]
```
