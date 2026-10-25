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

## The four steps at a glance

| Step | What you do | Result |
|---|---|---|
| 1 | Add your variant as a new folder (skip if you only compare the seven) | `src/optimizers/<name>/` |
| 2 | Run every algorithm on the same suite, functions, dimensions and runs | `results/_run_all/<name>/<suite>/` |
| 3 | `plot_convergence` | one figure per function with every algorithm's curve |
| 4 | `compare_algorithms` | Mean/SD tables (CSV and LaTeX), Wilcoxon and Friedman tests |

Steps 3 and 4 together are one click: open `run_compare_algorithms.m` in the
repository root, set its CONFIG block (suites, algorithms, proposed
algorithm) and press Run. The sections below show the two commands it calls,
for use in your own scripts. The [New Variant Guide](../../../NEW_VARIANT_GUIDE.md)
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
| `'curve'` | `'median_run'` (default): the full trace of each algorithm's median run. `'mean'`: the mean over all runs at the 14 CEC checkpoints |
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
| `ranksum_<suite>.csv` | per function: two-sided Wilcoxon rank-sum test over the 51 runs, proposed algorithm vs each competitor, p-value and sign |
| `wilcoxon_<suite>.csv` | per dimension: Wilcoxon signed-rank test over the function means: R+, R−, p-value, decision, and the +/=/− counts |
| `friedman_<suite>.csv` | per dimension and overall: Friedman mean rank of every algorithm (1 = best), its position, chi-square and p-value |

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
  the algorithms are not all equal.

The tests need no toolbox. Their p-values equal those of MATLAB's Statistics
and Machine Learning Toolbox (`ranksum`, `signrank`, `friedman`), including the
exact small-sample p-values. Check which tests and which layout your target
paper uses (for example, whether "+" is written from the proposed
algorithm's side); the CSV files hold everything needed to rearrange the
tables.

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
