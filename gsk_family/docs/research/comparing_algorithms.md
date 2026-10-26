# Comparing Algorithms

> **Orientation.** This page shows how to compare two or more optimizers on
> any CEC suite: for example GSK against your own GSK variant on CEC2017 and
> CEC2011. It covers adding your variant, running it, drawing the convergence
> curves of all the algorithms in one figure per function, and producing the
> tables and statistical tests that papers on the GSK family usually report.
> Everything here works for all five suites (CEC2011, CEC2013, CEC2013-LSGO,
> CEC2017, CEC2020) and all seven optimizers (GSK, AGSK, APGSK, FDB-AGSK,
> ATMALS-GSK, eGSK, DT-GSK), and for any optimizer you add. It assumes the
> one-time setup in the [Runbook](../../../RUNBOOK.md) is done (MEX bridge
> built, first run works).

## The steps at a glance

| Step | What you do | Result |
|---|---|---|
| 1 | Add your variant as a new folder (skip if you only compare the seven) | `src/optimizers/<name>/` |
| 2 | Run every algorithm on the same suite, functions, dimensions and runs | `results/_run_all/<name>/<suite>/` |
| 3 | `plot_convergence` | one figure per function with every algorithm's curve |
| 4 | `compare_algorithms` | Mean/SD tables (CSV and LaTeX), Wilcoxon, Friedman, post-hoc tests, effect sizes, runtime table |
| 5 | `plot_statistics` | CD diagram, box plots, rank and runtime charts |
| 6 | `plot_performance` | success rates, ERT tables, ECDF data profiles |
| (7) | `make_study_aliases`, then `plot_sensitivity` / `plot_ablation` | parameter sensitivity and ablation studies (extra runs) |
| (8) | `cec_complexity` | the CEC algorithm complexity table (runs the algorithms) |
| (9) | `plot_dynamics` | diversity, exploration/exploitation, population size and parameter trajectories (runs made with `log_trace`) |

Steps 3 to 6 together are one click: open `run_compare_algorithms.m` in the
repository root, set its CONFIG block (suites, algorithms, proposed
algorithm) and press Run; its `sensitivity`, `ablation` and `complexity`
entries add steps 7 and 8. The
sections below show the commands it calls, for use in your own scripts. The [New Variant Guide](../../../NEW_VARIANT_GUIDE.md)
walks through the whole path for a new variant.

All commands below are typed in MATLAB, with the current folder set to
`gsk_family` (the folder that holds `src`, `scripts` and `results`).

## Step 1: Add your variant

Your variant is one MATLAB function in its own folder. The easiest start is
a copy of the algorithm it modifies. One command makes it; for a variant of
GSK called `my-gsk`:

```matlab
addpath('scripts');
new_gsk_variant('my-gsk', 'base','gsk');   % base: any of the seven
```

It creates `src/optimizers/my-gsk/my_gsk_optimize.m`, a copy of
`gsk_optimize.m` with only the names changed (function name, help text, error
ids and `result.optimizer = 'my-gsk'`). Then make your changes to the
algorithm. Helper files of the base stay in the base's folder and are shared;
to change one, copy it into your folder under a new name.

By hand: create `src/optimizers/my-gsk`, copy only `gsk_optimize.m` into it
as `my_gsk_optimize.m`, and rename the function on its first line and the
`result.optimizer` value.

Name rules: use lower-case letters, digits and hyphens for the name
(`my-gsk`). The file and function names use the same name with underscores
(`my_gsk_optimize`). That is all; the MATLAB runner finds the new folder by
itself. (The C++ command-line tool `gsk_run` knows only the seven built-in
optimizers; use the MATLAB launchers or `run_experiment` for your variant.)

The rules your function must follow (seed first, use the runner's starting
population, evaluate only through `problem.evaluate`, stop at
`problem.max_nfes`, return the documented `result` fields) are listed in the
[Extension Guide](../development/extension_guide.md). A copy of GSK already
follows all of them.

**Check it quickly** with two short runs (a few seconds):

```matlab
addpath('src/runners');
run_experiment('optimizer','my-gsk', 'suite','cec2017', 'functions',1, ...
    'dimensions',10, 'runs',2, 'max_nfes',3000, 'project_root',pwd, ...
    'output_dir',fullfile(tempdir,'my_gsk_check'), 'use_parallel',false);
```

**Fair comparisons.** With the default `seed_policy = 'unified'`, every
optimizer gets the same seed for each (dimension, function, run), and the
runner gives all of them the same starting population. A variant that differs
from GSK only in one step therefore differs from GSK only because of that
step. (DT-GSK draws its own starting population from the same seed.) An
unchanged copy of GSK gives exactly the same results as GSK, which is a good
first test of your setup.

## Step 2: Run the experiments

Run every algorithm with the same settings. The standard protocols are:

| Suite | Functions | Dimensions | Budget per run (`max_nfes = 0`) | Runs per algorithm (51 each) |
|---|---|---|---|---|
| CEC2017 | `1:30` (F2 is dropped automatically) | `[10 30 50 100]` | 10000 × D | 29 × 4 × 51 = 5,916 |
| CEC2011 | `1:22` | `0` (each problem's own dimension) | 150,000 | 22 × 51 = 1,122 |
| CEC2013 | `1:28` | `[10 30 50]` | 10000 × D | 28 × 3 × 51 = 4,284 |
| CEC2020 | `1:10` | `[5 10 15 20]` | 50,000 to 10,000,000 | 1,836 (F1 and F8 have no data at D5 and D15) |
| CEC2013-LSGO | `1:15` | `0` (1000; 905 for F13, F14) | 3,000,000 | 15 × 51 = 765 |

**Option A: a launcher.** Open `run_all_cec2017.m` (next to the `gsk_family`
folder), edit the CONFIG block, and press Run:

```matlab
optimizers = {'gsk', 'my-gsk'};       % any of the seven, plus your own
functions  = 1:30;
dimensions = [10 30 50 100];
runs       = 51;
```

For CEC2011 use `run_all_cec2011.m` with `functions = 1:22` and
`dimensions = 0`. The other launchers work the same way.

The launchers start with `overwrite = true`: each listed algorithm's
previous results for that suite are moved to an archive folder and the runs
start clean. To continue an interrupted campaign, or to add dimensions or
algorithms later without losing finished runs, set `overwrite = false`;
finished runs are then reused.

**Option B: `run_experiment` directly**, one call per algorithm. This is what
the launchers do:

```matlab
addpath('src/runners');
for opt = {'gsk', 'my-gsk'}
    run_experiment('optimizer',opt{1}, 'suite','cec2017', 'functions',1:30, ...
        'dimensions',[10 30 50 100], 'runs',51, 'max_nfes',0, ...
        'project_root',pwd, 'output_dir',fullfile(pwd,'results','_run_all',opt{1},'cec2017'), ...
        'overwrite',false, 'verbose',false, 'use_parallel',true);
end
```

**Time and memory.** A full CEC2017 campaign takes many hours per algorithm,
mostly at D = 100. Start with D10 to check everything, then add the larger
dimensions with `overwrite = false`. With `use_parallel = true` MATLAB runs
several runs at once; on a PC with limited memory open a smaller pool first
(for example `parpool(8)`), as the [Runbook](../../../RUNBOOK.md) explains in
"Running in parallel in MATLAB".

**What each run saves** (under `results/_run_all/<algorithm>/<suite>/`):
`summary/per_run.csv` (the final value of every run), `curves/` (the full
convergence trace of each function's median run) and `gen_logs/` (the
best-so-far value of every run at the 14 CEC checkpoints). Steps 3 and 4 read
only these files, so you can run them at any time, also on a partial
campaign.

## Step 3: Convergence curves in one figure per function

```matlab
addpath('scripts');
plot_convergence('suite','cec2017', 'optimizers',{'my-gsk','gsk'}, ...
                 'labels',{'My GSK','GSK'});
plot_convergence('suite','cec2011', 'optimizers',{'my-gsk','gsk'}, ...
                 'labels',{'My GSK','GSK'});
```

The figures go to `results/analysis/convergence/<suite>/`:

| File | Contents |
|---|---|
| `<suite>_F<f>_D<d>.png` and `.pdf` | one function at one dimension, every algorithm in one figure |
| `<suite>_D<d>_overview.png` and `.pdf` | all functions of one dimension as small panels with one legend (`<suite>_all_overview` for CEC2011 and CEC2013-LSGO) |

The PDF files are vector graphics, best for a manuscript; the PNG files are
300 dpi.

Useful options (all optional; see `help plot_convergence`):

| Option | Meaning |
|---|---|
| `'optimizers'` | which algorithms, in legend order; default: every algorithm with results for the suite |
| `'labels'` | legend names; default GSK, AGSK, APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK, or the name in capitals |
| `'functions'`, `'dimensions'` | plot only some, e.g. `'functions',[1 5 10]`, `'dimensions',50` |
| `'curve'` | `'median_run'` (default): the full trace of each algorithm's median run. `'mean'` or `'median'`: the mean or median over all runs at the 14 CEC checkpoints |
| `'band'` | `'iqr'`: a shaded band from the 25th to the 75th percentile of all runs at the checkpoints, under each curve (default `'none'`) |
| `'yscale'` | `'auto'` (default), `'log'` or `'linear'` |
| `'formats'` | default `{'png','pdf'}`; also `'eps'` and `'fig'` (editable MATLAB figure) |
| `'overview'` | `false` to skip the panel figures |
| `'output_dir'` | where to save; default `results/analysis/convergence/<suite>` |

What the y-axis shows:

- **CEC2013, CEC2017, CEC2020** have known optima, so the y-axis is the error
  f(x) − f(x\*) on a log scale. Errors below 1e-8 (the CEC zero threshold) are
  drawn at 1e-8.
- **CEC2011 and CEC2013-LSGO** are plotted as raw objective values, as their
  result tables report them. Many CEC2011 problems have negative values, so
  `'auto'` uses a linear axis whenever a value is zero or negative.

The median run of each algorithm is chosen separately: it is the run whose
final value is closest to the median of that algorithm's runs. Say which
curve you plot in the figure caption: "median run" or "mean of 51 runs".

## Step 4: Tables and statistical tests

```matlab
addpath('scripts');
compare_algorithms('suite','cec2017', 'optimizers',{'my-gsk','gsk'}, 'proposed','my-gsk');
compare_algorithms('suite','cec2011', 'optimizers',{'my-gsk','gsk'}, 'proposed','my-gsk');
```

`proposed` is the algorithm that every other one is tested against (default:
the first in `optimizers`). Add more competitors to the list, for example
`{'my-gsk','gsk','agsk','apgsk'}`. The tables go to
`results/analysis/compare/<suite>/`, and a short summary is printed:

| File | Contents |
|---|---|
| `table_<suite>_D<d>.tex` | LaTeX table: Mean (SD) of every algorithm per function, best mean in bold, each competitor marked +, = or −, and a +/=/− count row. Use it with `\input{table_cec2017_D10.tex}` |
| `table_<suite>_D<d>.csv` | the same numbers for Excel, with every p-value |
| `statistics_<suite>.csv` | Best, Median, Mean, Worst, SD and the run count of every algorithm on every function |
| `ranksum_<suite>.csv` | per function: two-sided Wilcoxon rank-sum test over the 51 runs, proposed algorithm vs each competitor: p-value, Holm-adjusted p-value, both signs, and the effect size (Vargha–Delaney A12, Cliff's delta, and negligible/small/medium/large) |
| `wilcoxon_<suite>.csv` | per dimension: Wilcoxon signed-rank test over the function means: R+, R−, p-value, decision, and the +/=/− counts |
| `friedman_<suite>.csv` | per dimension and overall: Friedman mean rank of every algorithm (1 = best), its position, chi-square and p-value, and the Iman–Davenport F test |
| `posthoc_<suite>.csv` | per dimension and overall: Friedman post-hoc test of every competitor against the proposed algorithm: z, unadjusted p, and Bonferroni–Dunn, Holm, Hochberg and Finner adjusted p-values |
| `nemenyi_<suite>.csv` | per dimension and overall: the Nemenyi critical difference (CD) used by the CD diagram |
| `settings_<suite>.csv` and `.tex` | per algorithm: the code it ran, its starting and final population size and any changed setting ("original" = published value); a ready parameter-settings table |

For CEC2011 and CEC2013-LSGO the tag is `all` instead of `D<d>`: all problems
form one group, each at its own dimension.

How to read the results (significance level `alpha = 0.05` by default):

- **+** the proposed algorithm is significantly better on that function
  (rank-sum p < 0.05 and its runs have the lower values); **−** it is
  significantly worse; **=** no significant difference.
- **R+** adds up the ranks of the functions on which the proposed algorithm
  has the lower mean, **R−** the others. A small p-value with R+ > R− means
  the proposed algorithm is better over the whole suite.
- **Friedman**: the lower the mean rank, the better. A small p-value means
  the algorithms are not all equal. **Iman–Davenport** is a less
  conservative version of the same test.
- **Post-hoc** (after a significant Friedman test): an adjusted p-value below
  0.05 means the proposed algorithm's mean rank differs significantly from
  that competitor's. Holm is the usual choice; Finner and Hochberg are a little
  more powerful, Bonferroni–Dunn the most conservative.
- **Effect size**: A12 is the probability that a run of the proposed
  algorithm beats a run of the competitor (0.5 = equal; above 0.5 favours the
  proposed one). Cliff's delta = 2·A12 − 1. "Large" means |delta| ≥ 0.474.
- **Multiple testing**: with 29 functions, a few raw "+" or "−" signs can
  appear by chance. `ranksum_<suite>.csv` always holds the Holm-adjusted
  p-values too; pass `'correction','holm'` to use them for the table signs.

The tests need no toolbox. Their p-values equal those of MATLAB's Statistics
and Machine Learning Toolbox (`ranksum`, `signrank`, `friedman`), including the
exact small-sample p-values. Check which tests and which layout your target
paper uses (for example, whether "+" is written from the proposed
algorithm's side); the CSV files hold everything needed to rearrange the
tables. The post-hoc and adjusted p-values follow Derrac et al. (2011,
Swarm Evol. Comput.) and García et al. (2010, Inf. Sci.); the Nemenyi critical
values are computed from the studentized range distribution and match
Demšar's (2006, JMLR) table.

## Statistics figures: CD diagram, box plots, rank charts

```matlab
plot_statistics('suite','cec2017', 'optimizers',{'my-gsk','gsk','agsk'}, 'proposed','my-gsk');
```

The figures go to `results/analysis/statistics/<suite>/` (PNG and vector PDF):

| File | Contents |
|---|---|
| `cd_<suite>_D<d>` and `cd_<suite>_overall` | critical difference diagram: every algorithm on its Friedman mean rank; a thick bar joins algorithms that are **not** significantly different (Nemenyi test) |
| `box_<suite>_F<f>_D<d>` | box plot of the final values of all runs, one figure per function, every run shown as a dot; whiskers to the furthest runs within 1.5 IQR |
| `box_<suite>_D<d>_overview` | the same for all functions of one dimension |
| `ranks_<suite>_bars` | Friedman mean ranks per dimension and overall, with the values printed |
| `ranks_<suite>_radar` | the same as a radar chart, when there are three or more dimensions |

Violin plots are available with `'figures',{'violin'}`; with fewer than 20
runs per algorithm they are drawn as box plots, because a density from so few
runs is misleading. The y-axis is logarithmic only when the values span at
least a decade. `plot_statistics` calls `compare_algorithms` with the same
options, so the figures always match the tables.

## Runtime

`compare_algorithms` also writes `runtime_<suite>.tex` and `.csv`: the
seconds per run (as timed by each algorithm, from its start to its result),
mean (SD) per dimension and algorithm, and per function in the CSV.
`plot_statistics` draws them as `runtime_<suite>` (bars with SD error bars).
Compare runtimes only between runs made on the same computer with the same
settings: parallel runs share the processor.

## Success rates, ERT and ECDF data profiles

```matlab
plot_performance('suite','cec2017', 'optimizers',{'my-gsk','gsk','agsk'});
```

For a target error t, a run succeeds at the first recorded budget at which
its error is ≤ t. For every function, algorithm and target (following COCO,
Hansen et al.):

- **success rate** = successful runs / runs;
- **ERT** (expected running time) = the evaluations used by all runs until
  success, counting the full budget for each unsuccessful run, divided by the
  number of successful runs (∞ when none succeeds);
- **ECDF data profile** = the fraction of (function, target, run) triples
  reached within each number of evaluations, one curve per algorithm. The
  higher and further left a curve, the faster and more reliable the
  algorithm.

The default targets are 10², 10, 1, 10⁻¹, 10⁻², 10⁻⁴, 10⁻⁶ and 10⁻⁸
(`'targets'` changes them). CEC2011 and CEC2013-LSGO have no known optimum,
so there the targets apply to the distance to the best value any compared
algorithm found, divided by max(|that value|, 1).

Outputs in `results/analysis/performance/<suite>/`: `performance_<suite>.csv`
(every function, algorithm and target), `ert_<suite>_D<d>.tex` (ERT and
success rate per function at `'ert_target'`, default the smallest target, the
smallest ERT in bold), `ecdf_<suite>_D<d>` and `ecdf_<suite>_overall` (all
dimensions pooled, x = fraction of the budget).

**Smooth curves need a denser log.** By default the runs record their best
value only at the 14 CEC checkpoints (1%, 2%, ... 100% of the budget), so
ERT and the ECDF step at those budgets. Add `trace_points = 50;` to a
launcher's CONFIG block (or pass `'trace_points',50` to `run_experiment`)
before running: each run then also writes its best value at 50 log-spaced
budgets to `gen_logs/BestTrace_*.csv`, and `plot_performance` uses them. This
does not change the runs or any other file.

## Parameter sensitivity

How much does a parameter matter? Run a grid of settings and compare the
grid points with each other.

1. Write the grid as aliases (they are appended to `algorithms.ini`):

   ```matlab
   make_study_aliases('sensitivity', 'gsk', {'kf', [0.3 0.5 0.7]});
   make_study_aliases('sensitivity', 'gsk', {'kf', [0.3 0.5 0.7], 'kr', [0.8 0.9 1]});   % two parameters
   ```

   It prints the launcher line, e.g.
   `optimizers = {'gsk', 'gsk-kf-0p3', 'gsk-kf-0p5', 'gsk-kf-0p7'}`.
2. Run them with a launcher. A grid costs one campaign per point, so a few
   functions or D10 are often enough.
3. Plot:

   ```matlab
   plot_sensitivity('suite','cec2017', 'base','gsk', 'spec',{'kf',[0.3 0.5 0.7]});
   ```

One parameter gives a line chart of the Friedman mean rank against the
value, one line per dimension and a thick line for all dimensions; two
parameters give a heatmap with the best cell framed. The numbers go to
`sensitivity_<suite>_<base>.csv`, and the full comparison tables of the grid
to its `compare` folder (`results/analysis/sensitivity/<suite>/<base>/`).

## Ablation study

Which new parts of your variant actually help? Switch each one off and
compare.

1. Give each new part of your variant an on/off switch, read like any
   parameter:

   ```matlab
   use_step_a = local_option(options, 'use_step_a', true);
   ...
   if use_step_a
       % the new step
   end
   ```

2. Write one alias per switch, run them with the full variant, and plot:

   ```matlab
   make_study_aliases('ablation', 'my-gsk', {'use_step_a', 'use_step_b'});
   % run: optimizers = {'my-gsk', 'my-gsk-no-use-step-a', 'my-gsk-no-use-step-b'}
   plot_ablation('suite','cec2017', 'base','my-gsk', 'switches',{'use_step_a','use_step_b'});
   ```

`ablation_<suite>_<base>.tex` lists every version: the part switched off, the
Friedman mean rank, the +/=/− counts of the full variant against it, and the
signed-rank p-value per dimension; the chart shows the mean ranks. A part
helps when switching it off makes the rank worse and the full variant wins
more functions than it loses.

## Population dynamics: diversity, exploration and exploitation

How does each algorithm search? These figures need one extra setting when
the algorithms run.

1. Add `log_trace = true;` to a launcher's CONFIG block (a commented line is
   already there), or pass `'log_trace',true` to `run_experiment`. Every
   optimizer then records, per generation, its evaluations, its population
   size, the population diversity and its own adaptive parameters, in
   `trace/Dynamics_<name>_F<f>_D<d>.csv` (at most 200 generations per run).
   Tracing draws no random numbers and changes no value, so the runs are
   exactly the same as without it (checked on all seven algorithms).
2. Draw the figures:

   ```matlab
   plot_dynamics('suite','cec2017', 'optimizers',{'my-gsk','gsk','agsk'});
   ```

   or set `dynamics = true` in `run_compare_algorithms.m`.

| File (in `results/analysis/dynamics/<suite>/`) | Contents |
|---|---|
| `diversity_<suite>_F<f>_D<d>` | population diversity against evaluations: median over all runs with a 25–75% band, one line per algorithm |
| `xplxpt_<suite>_F<f>_D<d>` | exploration and exploitation percentages of each algorithm's median run, as stacked areas |
| `xplxpt_<suite>.csv` | the mean exploration and exploitation percentages per function and algorithm |
| `population_<suite>_D<d>` | population size against evaluations (shows the reduction schedules) |
| `parameters_<suite>_<name>_D<d>` | each adaptive parameter of an algorithm over the run: one light line per function, the median over functions thick |

**Diversity** (Hussain et al. 2019): for each dimension, the mean distance of
the population from the dimension's median, divided by the dimension's
range, averaged over the dimensions. **Exploration** of a run:
XPL% = 100 · Div / max(Div); **exploitation**: XPT% = 100 − XPL%.

The parameters recorded by each algorithm:

| Algorithm | Parameters |
|---|---|
| GSK | none (fixed parameters) |
| AGSK, FDB-AGSK | `kw1`..`kw4`: the probabilities of the four (KF, KR) pool settings |
| APGSK | `kw1`..`kw4`, `kf_mean` (negative when the negative KF pool is used), `kr_mean`, `d_junior` |
| ATMALS-GSK | `kf`, `kr`, `k`, `p`, `pls`: the values its adaptive tuning selected |
| eGSK | `kf1_mean`, `kf2_mean`, `ip_refine` (1 when the `fmincon` refinement ran) |
| DT-GSK | `kf_mean`, `kr_mean` (ACE draws), `acceptance` (share of accepted children), `restarts`, `polish_done`, `deep_restart` |
| your variant | whatever it records (see the [New Variant Guide](../../../NEW_VARIANT_GUIDE.md)) |

## Algorithm complexity (CEC protocol)

The CEC2017 technical report asks for an algorithm complexity table, measured
on function 18 with 200,000 evaluations:

```matlab
cec_complexity('suite','cec2017', 'optimizers',{'my-gsk','gsk'});
```

It measures T0 (a fixed test loop), T1 (200,000 evaluations of F18), and T̂2
(the mean time of 5 complete runs of each algorithm with 200,000
evaluations), for D = 10, 30, 50 and 100, and writes
`results/analysis/complexity/cec2017/complexity_cec2017.tex` and `.csv` with
T0, T1, T̂2 and (T̂2 − T1)/T0. It **runs** the algorithms (serially, in a
temporary folder), so it takes from minutes to hours; keep the computer
otherwise idle, because these are wall-clock times. For another suite, pass
`'function'` with the function its technical report names.

## Original and changed settings (aliases)

Every algorithm runs with its original settings by default. To compare an
algorithm under other settings as well, define an alias in `algorithms.ini`
in the repository root, for example:

```ini
[gsk-np50]
base    = gsk
np_init = 50
```

Run it like any algorithm (`optimizers = {'gsk', 'gsk-np50'}` in a launcher),
and compare it like any algorithm:

```matlab
compare_algorithms('suite','cec2017', 'optimizers',{'my-gsk','gsk','gsk-np50'}, 'proposed','my-gsk');
```

Each alias has its own results folder and shares the seeds of the others. The
settings table (`settings_<suite>.tex`) shows what each name changed. Every
setting each algorithm accepts, with its original value, is listed in
`algorithms.ini` and in the
[Command Reference](../getting-started/command_reference.md), "Algorithm aliases".

## Other suites and the seven built-in optimizers

Nothing changes for other suites or other algorithms: use the suite name
(`cec2011`, `cec2013`, `cec2013lsgo`, `cec2017`, `cec2020`) and any optimizer
names. For example, all seven against each other on CEC2020:

```matlab
names = {'gsk','agsk','apgsk','fdb-agsk','atmals-gsk','egsk','dt-gsk'};
plot_convergence('suite','cec2020', 'optimizers',names);
compare_algorithms('suite','cec2020', 'optimizers',names, 'proposed','dt-gsk');
```

Results written by the `gsk_run` command-line tool are under `results/`
instead of `results/_run_all/`; add `'results_root','results'` to both
commands to use them.

## Common problems

| Message or symptom | What to do |
|---|---|
| `no results for my-gsk on cec2017` | The runs are not where the command looks. Check the name, and that `results/_run_all/my-gsk/cec2017/` exists; pass `'results_root'` if the results are elsewhere. |
| `Unrecognized function or variable 'my_gsk_optimize'` | The folder, file or function name does not match step 1 (folder `my-gsk`, file and function `my_gsk_optimize`). |
| A figure lacks one algorithm | That algorithm has no curve for this function yet (run not finished). The command lists such functions as `incomplete`. |
| A function is missing from the tables | Only functions that every listed algorithm has finished are compared; the command lists the others as `skipped`. |
| Curves of a whole cell are missing after results were copied from a backup | Only `per_run.csv` was restored; tables work, curves need the runs again. |
| `egsk:fminconUnavailable` | eGSK needs the Optimization Toolbox. |

## See also

- [Runbook](../../../RUNBOOK.md): setup, first run, parallel runs.
- [Result Schema](../reference/result_schema.md): every output file and column.
- [Seed Policy](../reference/seed_policy.md): how seeds and starting populations are shared.
- [Extension Guide](../development/extension_guide.md): the full optimizer contract.
- `scripts/analyze_results.m`: compares each optimizer with its published reference tables (a different question from this page).
