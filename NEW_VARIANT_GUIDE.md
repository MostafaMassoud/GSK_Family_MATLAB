# New Variant Guide

How to build your own GSK variant in this project, check it, run it on the
CEC benchmark suites next to the seven GSK-family optimizers, and get the
convergence figures and statistical tables for a manuscript. Every step is
one command or one small edit.

<div class="flow">

1. **Create** One command makes a renamed copy of a family member.
2. **Edit** Change the search in one MATLAB file.
3. **Check** A 10-second test run; an untouched copy reproduces its base exactly.
4. **Run** Run your variant next to the others, with original or changed settings.
5. **Analyze** Press Run once for the figures and the tables.

</div>

> [!NOTE]
> Do the one-time setup first: [Runbook](RUNBOOK.md) sections 1 to 3
> (install, build the MEX bridge, first run). This guide assumes the first
> run works.

---

## 1. What you will create

A GSK variant here is **one MATLAB function in its own folder**. The runner,
the benchmarks, the seeds, the result files and the analysis tools are shared
with the seven built-in optimizers, so your variant gets all of them for free.

```text
GSK_Family_MATLAB\
  run_all_cec2017.m          <- launchers (one per suite)
  run_all_cec2011.m
  run_compare_algorithms.m   <- figures and statistics
  algorithms.ini             <- aliases: other settings (step 7)
  gsk_family\
    src\optimizers\
      gsk\                   <- the seven built-in optimizers
      ...
      my-gsk\                <- YOUR VARIANT (step 3)
    scripts\
      new_gsk_variant.m      <- creates the copy
      plot_convergence.m     <- convergence figures
      compare_algorithms.m   <- tables and tests
    results\_run_all\        <- every run's results
    results\analysis\        <- figures and tables
```

<div class="cards">

- **Fair comparison built in** Every algorithm gets the same seed and the same starting population in each run, so differences come from the algorithms.
- **No registration** The runner finds the new folder by itself. You never edit the runner.
- **All suites** CEC2011, CEC2013, CEC2013-LSGO, CEC2017 and CEC2020 work the same way.
- **Paper-ready output** Vector PDF figures, LaTeX tables, Wilcoxon and Friedman tests.

</div>

## 2. Choose a base algorithm

Start from the family member closest to your idea. The copy keeps all of its
behaviour, so you only write what is new.

| Base | Name to use | What it is | Starting population |
|---|---|---|---|
| GSK | `gsk` | The original: junior and senior knowledge phases, fixed parameters (KF = 0.5, KR = 0.9, K = 10, p = 0.1) | 100, fixed |
| AGSK | `agsk` | GSK with adaptive (KF, KR) pools and population reduction | 100, shrinks to 12 |
| APGSK | `apgsk` | AGSK-style adaptive parameters with a sign-switchable knowledge factor | 100, shrinks |
| FDB-AGSK | `fdb-agsk` | AGSK with fitness-distance-balance choice of the donor vectors | 100, shrinks to 12 |
| ATMALS-GSK | `atmals-gsk` | GSK with adaptive parameter tuning, a memory and adaptive local search | 100, fixed |
| eGSK | `egsk` | GSK with per-individual factors and a late `fmincon` local search (needs the Optimization Toolbox) | 100, fixed |
| DT-GSK | `dt-gsk` | GSK with dimension-tiered control: adaptive parameters, restarts, refinement | 5 × D, shrinks |

> [!TIP]
> If your idea changes the junior or senior phase of GSK, start from `gsk`:
> it is the shortest file (about 200 lines) and the easiest to read. Each
> algorithm is described in `gsk_family/docs/algorithms/<name>.md`.

## 3. Create your variant

Open MATLAB, set the current folder to `gsk_family`, and type:

```matlab
addpath('scripts');
new_gsk_variant('my-gsk', 'base','gsk', 'description','GSK with my new step');
```

This creates `src\optimizers\my-gsk\my_gsk_optimize.m`: an exact copy of
`gsk_optimize.m` with only the names changed (the function name, its help
text, its error names and `result.optimizer = 'my-gsk'`). It prints the next
steps, including a ready-made test command.

**Name rules:** lower-case letters, digits and hyphens, starting with a letter
(`my-gsk`, `ogsk`, `gsk-ls2`). The file and the function use the same name
with underscores (`my_gsk_optimize`). The seven built-in names are refused,
and an existing folder is never overwritten.

For another base, change `'base'`, for example
`new_gsk_variant('my-agsk', 'base','agsk')`.

> [!IMPORTANT]
> Some bases call small helper files that stay in the base's folder (for
> example `atmals_roulette_select.m` or `dt_gsk_config.m`). Your copy keeps
> calling them. To change a helper, copy it into your folder **under a new
> name** and call that new name from your copy; never edit the original.

<details>
<summary>Doing it by hand instead</summary>

1. Create the folder `src\optimizers\my-gsk`.
2. Copy `src\optimizers\gsk\gsk_optimize.m` into it as `my_gsk_optimize.m`.
3. Change its first line to `function result = my_gsk_optimize(problem, options)`.
4. Change `result.optimizer = 'gsk';` to `result.optimizer = 'my-gsk';`.

</details>

## 4. Make your change

Open `my_gsk_optimize.m` and change the search. In a copy of GSK the main
parts are easy to find by their comment lines:

| Look for this comment | What happens there |
|---|---|
| `% ----- population initialization` | the starting population (from the runner) is evaluated |
| `% ----- main loop -----` | one generation per pass, until the budget is used |
| `% ----- junior gaining-sharing` | the junior phase builds `Gained_Shared_Junior` |
| `% ----- senior gaining-sharing` | the senior phase builds `Gained_Shared_Senior` |
| `% ----- bound constraints` | out-of-range values are repaired |
| `% ----- trial vector generation` | the two phases are mixed into the trial vectors `ui` |
| `% ----- offspring evaluation` | the trial vectors are evaluated |
| `% ----- pairwise greedy selection` | each parent is replaced when its child is better |

**Keep these rules** so that the comparison stays fair and the runner can read
your results (a copy already follows all of them):

1. Seed first: `gsk_set_rng(options)` stays before any random number.
2. Start from the runner's population: keep the base's initialization code
   (in GSK it is the line with `gsk_initial_population_from_options`).
3. Evaluate only through `problem.evaluate(X)` (rows are candidates).
4. Keep every candidate inside `problem.lb` and `problem.ub`.
5. Count every evaluation in `nfes` and stop at `problem.max_nfes`.
6. Keep the `result` fields at the end of the file, including
   `result.convergence` (the curves are drawn from it).

**New parameters:** read them with a default, in the style of the file, so
runs without the option keep working:

```matlab
alpha = local_option(options, 'alpha', 0.2);   % my new parameter, default 0.2
```

A parameter read this way can then be changed without editing the file, from
an alias in `algorithms.ini` (step 7), for example `alpha = 0.5`.

The full contract of `problem`, `options` and `result` is in the
[MATLAB interface](gsk_family/docs/reference/matlab_interface.md), and the
[Extension Guide](gsk_family/docs/development/extension_guide.md) explains it
step by step.

## 5. Check it

Run two short runs (about 10 seconds) in the `gsk_family` folder:

```matlab
addpath('src/runners');
run_experiment('optimizer','my-gsk', 'suite','cec2017', 'functions',1, ...
    'dimensions',10, 'runs',2, 'max_nfes',3000, 'project_root',pwd, ...
    'output_dir',fullfile(tempdir,'my_gsk_check'), 'use_parallel',false);
```

It prints a results table for F1. An error message names the line to fix.

> [!TIP]
> **The best first test:** create the copy, change nothing, and run it next to
> its base with the same settings. With the default unified seeds the two give
> **exactly** the same numbers. This proves your setup is right before you
> change anything. Every one of the seven bases passes this test.

```matlab
for opt = {'gsk', 'my-gsk'}
    run_experiment('optimizer',opt{1}, 'suite','cec2017', 'functions',1, ...
        'dimensions',10, 'runs',3, 'max_nfes',5000, 'project_root',pwd, ...
        'output_dir',fullfile(tempdir,'same_check',opt{1}), 'use_parallel',false, 'verbose',false);
end
A = readtable(fullfile(tempdir,'same_check','gsk','summary','per_run.csv'));
B = readtable(fullfile(tempdir,'same_check','my-gsk','summary','per_run.csv'));
isequal(A.best_fitness, B.best_fitness)   % 1 = identical
```

## 6. Run the experiments

Use the launchers next to the `gsk_family` folder. For CEC2017, open
`run_all_cec2017.m`, set the CONFIG block, and press **Run**:

```matlab
optimizers = {'gsk', 'my-gsk'};      % your variant and the algorithms to compare with
functions  = 1:30;                   % F2 is dropped automatically
dimensions = [10 30 50 100];
runs       = 51;
```

For CEC2011, open `run_all_cec2011.m` and set the same `optimizers`,
`functions = 1:22` and `dimensions = 0` (each problem at its own dimension).

| Suite | Functions | Dimensions | Budget per run | Runs per algorithm |
|---|---|---|---|---|
| CEC2017 | `1:30` | `[10 30 50 100]` | 10,000 × D | 5,916 |
| CEC2011 | `1:22` | `0` (native) | 150,000 | 1,122 |
| CEC2013 | `1:28` | `[10 30 50]` | 10,000 × D | 4,284 |
| CEC2020 | `1:10` | `[5 10 15 20]` | 50,000 to 10,000,000 | 1,836 (F1 and F8 have no data at D5 and D15) |
| CEC2013-LSGO | `1:15` | `0` (1000; 905 for F13, F14) | 3,000,000 | 765 |

> [!WARNING]
> A full CEC2017 campaign takes many hours per algorithm, mostly at D = 100.
> Start with `dimensions = 10` to check everything. The launchers start with
> `overwrite = true`, which moves the earlier results of every listed
> algorithm to an archive folder. To add dimensions or algorithms later
> without losing finished runs, set `overwrite = false`: finished runs are
> reused.

For long campaigns, run several runs at once with `use_parallel = true` and
choose the number of workers yourself; see [Runbook](RUNBOOK.md) section 5.

## 7. Original and standardized settings

By default every algorithm, yours included, runs with its **original
settings**: its own population size and parameters. To also run an algorithm
under other settings, and keep both sets of results, give it an **alias** in
`algorithms.ini` (repository root, next to the launchers):

```ini
[gsk-np50]
base    = gsk
np_init = 50

[my-gsk-np50]
base    = my-gsk
np_init = 50
```

Then list the names in the launcher like any algorithm:

```matlab
optimizers = {'gsk', 'my-gsk', 'gsk-np50', 'my-gsk-np50'};
```

`gsk` and `my-gsk` run with their original settings, the two aliases with
NP = 50, and every name gets its own results folder. Step 8 compares all four
in one go.

<div class="cards">

- **Every setting listed** `algorithms.ini` shows each algorithm's settings with their original values, and a commented example for each: remove the `;` to use it.
- **Your own parameters too** Settings your file reads, e.g. `alpha = local_option(options, 'alpha', 0.3)`, work in an alias: `alpha = 0.5`.
- **Same seeds** Aliases get the same seeds as all the other algorithms, so the comparison stays fair.
- **Mistakes caught** A misspelled setting stops the run and lists the accepted ones.

</div>

> [!IMPORTANT]
> A population size or parameter other than an algorithm's original must be
> reported as a changed setting in a paper. The settings table of step 8 lists
> exactly what each name changed. After editing an alias that already has
> results, give it a new name: the runner refuses to mix two settings in one
> results folder.

## 8. Convergence figures and statistics

Open `run_compare_algorithms.m` (next to the launchers), set its CONFIG block,
and press **Run**:

```matlab
suites     = {'cec2017', 'cec2011'};
optimizers = {'my-gsk', 'gsk'};       % first = first in legends and tables
labels     = {'Proposed', 'GSK'};     % names shown in the figures and tables
proposed   = 'my-gsk';                % tested against every other algorithm
band       = 'iqr';                   % optional: shaded 25-75% band of all runs under each curve
complexity = false;                   % true = also time the CEC complexity table (extra runs)
```

It reads the finished runs and writes, for each suite:

| Output | Where | Contents |
|---|---|---|
| Convergence figures | `results\analysis\convergence\<suite>\` | one figure per function and dimension with every algorithm's curve (`<suite>_F<f>_D<d>.png` and `.pdf`), plus one overview with all functions per dimension |
| LaTeX tables | `results\analysis\compare\<suite>\table_<suite>_D<d>.tex` | Mean (SD) per function, best mean in bold, +/=/− per competitor, a +/=/− count row |
| Spreadsheet tables | same folder, `.csv` | the same numbers with every p-value; `statistics_<suite>.csv` adds Best, Median, Worst |
| Wilcoxon signed-rank | `wilcoxon_<suite>.csv` | R+, R−, p-value and decision per dimension |
| Friedman ranks | `friedman_<suite>.csv` | mean rank of every algorithm (1 = best) per dimension and overall |
| Settings table | `settings_<suite>.tex` and `.csv` | each name's code, starting and final population size and changed settings ("original" = published value) |
| Post-hoc and effect sizes | `posthoc_<suite>.csv`, `ranksum_<suite>.csv` | Holm/Hochberg/Finner-corrected Friedman post-hoc tests; A12 and Cliff's delta per function |
| CD diagram, box plots, rank and runtime charts | `results\analysis\statistics\<suite>\` | `cd_*`, `box_*` (every run as a dot), `ranks_*`, `runtime_*` |
| ERT and ECDF data profiles | `results\analysis\performance\<suite>\` | success rate and ERT per function and target, `ecdf_*` curves (smooth with `trace_points = 50` in the launcher) |
| Complexity table (optional) | `results\analysis\complexity\cec2017\` | T0, T1, T̂2, (T̂2 − T1)/T0; set `complexity = true` (it times extra runs) |

**Reading the results** (two-sided tests, alpha = 0.05):

- **+** your algorithm is significantly better than that competitor on that
  function, **−** significantly worse, **=** no significant difference
  (Wilcoxon rank-sum over the 51 runs).
- **R+** sums the ranks of the functions where your algorithm has the lower
  mean, **R−** the others. A small p-value with R+ > R− means it is better
  over the whole suite.
- **Friedman:** the lower the mean rank, the better.

The curves show the error f(x) − f(x\*) on a log axis for CEC2013, CEC2017
and CEC2020, and the objective value for CEC2011 and CEC2013-LSGO (which have
no known optimum; linear axis when values are negative). By default each
algorithm's **median run** is drawn; set `curve = 'mean'` for the mean of all
runs at the 14 CEC checkpoints.

> [!TIP]
> The p-values need no toolbox and equal those of MATLAB's `ranksum`,
> `signrank` and `friedman`. Run `run_compare_algorithms.m` again at any time,
> also on a partial campaign: it only reads results and overwrites its own
> output.

**Sensitivity and ablation.** Two studies reviewers often ask about a new
variant:

- *Is it sensitive to its parameters?* Write a grid of settings as aliases,
  run them, then plot the Friedman ranks over the grid:

  ```matlab
  make_study_aliases('sensitivity', 'my-gsk', {'alpha', [0.1 0.3 0.5]});
  % run them with a launcher, then in run_compare_algorithms.m:
  sensitivity = {'my-gsk', {'alpha', [0.1 0.3 0.5]}};
  ```

- *Does each new part help?* Give each part an on/off switch in your file
  (`use_step_a = local_option(options, 'use_step_a', true);`), then:

  ```matlab
  make_study_aliases('ablation', 'my-gsk', {'use_step_a', 'use_step_b'});
  % run them with my-gsk, then in run_compare_algorithms.m:
  ablation = {'my-gsk', {'use_step_a', 'use_step_b'}};
  ```

Both need extra runs (one campaign per grid point or per switched-off part);
a few functions or D10 are often enough. Details:
[Comparing Algorithms](gsk_family/docs/research/comparing_algorithms.md).

## 9. Put it in the manuscript

- **Figures:** use the PDF files (vector graphics). Say in the caption which
  curve is shown: "median run" or "mean of 51 runs".
- **Tables:** `\input{table_cec2017_D10.tex}` inside a `table` environment.
  The comment lines at the top of each file state the +/=/− convention; check
  that it matches the paper you follow.
- **Protocol to report:** 51 independent runs, the budget of the suite (table
  in step 6), the same seed and starting population for every algorithm in
  each run (unified seed policy), and your variant's parameter values.
- **Parameter settings:** `\input{settings_cec2017.tex}` gives a ready table
  of every compared name, the code it ran, its population sizes and any
  changed setting.
- **Statistical evidence reviewers ask for:** the Friedman ranks with the
  Iman–Davenport test, the post-hoc table with Holm-adjusted p-values
  (`posthoc_<suite>.csv`), the CD diagram (`cd_<suite>_overall.pdf`), and
  effect sizes next to the rank-sum signs (`ranksum_<suite>.csv`). With 29
  functions, consider Holm-adjusted signs (`correction = 'holm'`).
- **Complexity:** `complexity_cec2017.tex` is the CEC complexity table
  (T0, T1, T̂2, (T̂2 − T1)/T0); measure it on an otherwise idle computer.
- **Speed and reliability:** `runtime_<suite>.tex` (seconds per run),
  `ert_<suite>_D<d>.tex` and the ECDF figures (how often and how fast each
  algorithm reaches each target error).
- **Robustness:** the sensitivity chart or heatmap and the ablation table,
  when the paper claims a parameter is robust or a component helps.
- **Environment:** `summary\environment.json` in each result folder records
  the MATLAB version, seeds and settings of the run.
- **Keep** `results\_run_all\` until the paper is accepted: every number in
  the tables can be traced to a single run in `summary\per_run.csv`.

## 10. Common problems

| Message or symptom | What to do |
|---|---|
| `Unrecognized function or variable 'my_gsk_optimize'` | The folder, file and function names do not match step 3 (folder `my-gsk`, file and function `my_gsk_optimize`). |
| `new_gsk_variant:exists` | The folder exists already; nothing was changed. Choose another name or delete that folder yourself. |
| `unknown optimizer 'x'` or a message naming `algorithms.ini` and a line | The name is not an algorithm or an alias, or the alias has a mistake; the message names the line and lists the accepted settings (step 7). |
| `... was written with alias settings ...` | You edited an alias that already has results. Give the edited alias a new name, or delete its results folder. |
| `no results for my-gsk on cec2017` | The runs are not finished or not in `results\_run_all\my-gsk\cec2017\`. |
| A figure lacks one algorithm | That algorithm has no curve for this function yet; it is listed as `incomplete`. |
| A function is missing from the tables | Only functions that every listed algorithm has finished are compared; the others are listed as `skipped`. |
| `gskcec:mexMissingPrerequisite` | Build the MEX bridge ([Runbook](RUNBOOK.md) section 3). |
| Out of memory during a parallel run | Use fewer workers and continue with `overwrite = false` ([Runbook](RUNBOOK.md) section 5). |

## 11. Where to go next

- [Runbook](RUNBOOK.md): setup, all launchers, parallel runs.
- [Comparing Algorithms](gsk_family/docs/research/comparing_algorithms.md): every option of the figure and table tools.
- [Extension Guide](gsk_family/docs/development/extension_guide.md): the full optimizer contract and how to add a suite.
- [Seed Policy](gsk_family/docs/reference/seed_policy.md): how seeds and starting populations are shared.
- Algorithm guides in `gsk_family/docs/algorithms/`: how each family member works.
