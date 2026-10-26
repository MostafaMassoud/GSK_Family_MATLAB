# Runbook

How to set up the project, run experiments and analyze the results, step by
step. No prior knowledge of the code is needed. For every option of every
algorithm, see the
[Command Reference](gsk_family/docs/getting-started/command_reference.md).

**What the project does:** it runs seven optimization algorithms (GSK, AGSK,
APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK) on the standard CEC benchmark suites
(CEC2011, CEC2013, CEC2013-LSGO, CEC2017, CEC2020), saves the results of every
run, and turns them into convergence figures and statistical tables. The
algorithms are written in MATLAB. The benchmark functions are written in C++
and are called from MATLAB through a small compiled bridge (a "MEX file").

<div class="flow">

1. **Install** MATLAB, a C++ compiler and CMake (section 1).
2. **Build** The C++ tools and the MEX bridge, once (section 3).
3. **Run** Open a launcher, choose the algorithms, press Run (sections 4 and 5).
4. **Analyze** Convergence figures and statistics with one click (section 6).

</div>

> [!TIP]
> Building your **own GSK variant** and comparing it with the family? Follow
> the [New Variant Guide](NEW_VARIANT_GUIDE.md) after the setup in sections 1
> to 3.

---

## 1. Prerequisites

| You need | Why | Version used by the project |
|---|---|---|
| Windows 10 or 11 with PowerShell | build and helper scripts | PowerShell 5.1 or newer |
| MATLAB | runs the algorithms | R2025b |
| A C++20 compiler | builds the benchmark functions and the MEX bridge | MinGW-w64 g++ (WinLibs) |
| CMake | builds the C++ tools and tests | 3.20 or newer |

MATLAB toolboxes:

| Toolbox | Needed for | Without it |
|---|---|---|
| Parallel Computing Toolbox | running many runs at the same time (section 5) | runs go one at a time; results are the same |
| Optimization Toolbox | eGSK (it calls `fmincon`) | eGSK stops with `egsk:fminconUnavailable`; the other six algorithms work |
| Statistics and Machine Learning Toolbox | only `gsk_family/scripts/compare_reference_runs.m` | that one script stops; everything else works, including the figures and statistics of section 6 |

Optional, only for the HTML documentation: Pandoc 3.8 or newer and Doxygen.

**Getting the compiler and CMake.** Install WinLibs MinGW-w64, for example with
`winget install BrechtSanders.WinLibs.POSIX.UCRT`. It includes `g++` and
`cmake`. Check that Windows can find the tools:

```powershell
Get-Command g++, cmake, matlab
```

If a command is not found, add its `bin` folder to your `PATH`, or see section
2.1 of the [Command Reference](gsk_family/docs/getting-started/command_reference.md) for
using full paths.

## 2. Get the code and look around

Copy or clone the repository to any folder, for example
`C:\path\to\GSK_Family_MATLAB` (the commands below use that placeholder;
replace it with your own folder). The full copy is about 0.5 GB, mostly
reference results.

```text
GSK_Family_MATLAB\              <- repository root
  README.md                     <- short overview
  RUNBOOK.md, RUNBOOK.html      <- this runbook (Markdown and web page)
  NEW_VARIANT_GUIDE.md, .html   <- how to build and compare your own GSK variant
  run_all_cec2011.m             <- launchers: open one in MATLAB and press Run
  run_all_cec2013.m
  run_all_cec2013lsgo.m
  run_all_cec2017.m
  run_all_cec2020.m
  run_compare_algorithms.m      <- figures and statistics of finished runs (section 6)
  algorithms.ini                <- aliases: algorithms with changed settings (section 4.4)
  gsk_family\                   <- the project
    src\                        <- MATLAB code (algorithms, runner, tests)
    benchmarks\                 <- C++ benchmark suites, their data, reference results
    scripts\                    <- build and analysis scripts
    docs\                       <- documentation (HTML is built into docs\html)
    build\                      <- created by the build (C++ tools and MEX bridge)
    results\                    <- created by your runs
```

## 3. One-time setup

Open PowerShell in the `gsk_family` folder (next to this file) and run these
steps in order:

```powershell
cd C:\path\to\GSK_Family_MATLAB\gsk_family    # your copy of the repository
```

**Step 1 - build the C++ tools and run their tests.**

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

The last line must end with `100% tests passed`. If a test fails, fix the build
before going on.

**Step 2 - build the MEX bridge** (lets MATLAB call the C++ benchmarks).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_mex_bridge.ps1
```

This creates `build\mex\gskcec_eval.mexw64`. If the script cannot find MATLAB
or g++, pass them: `-MatlabRoot "C:\Program Files\MATLAB\R2025b"` and
`-Gxx "C:\path\to\mingw64\bin\g++.exe"`.

**Step 3 - check MATLAB.**

```powershell
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
```

Every test should print `PASS`, and the last line reads
`All 16 test(s) passed.`

> [!NOTE]
> You only repeat steps 1 to 3 after changing C++ code (steps 1 and 2) or to
> re-check the setup. Changing MATLAB code, including your own algorithm,
> needs no rebuild.

## 4. Your first run

Every run starts from a launcher in the repository root: `run_all_cec2017.m`
for CEC2017, and one file per other suite. You choose what to run in the
launcher's CONFIG block, then start it either from the MATLAB desktop (4.1) or
from a terminal (4.2). Both ways give the same results.

**Choose a small first test.** Open `run_all_cec2017.m` (in the MATLAB Editor
or any text editor), set its CONFIG block as below, and save the file:

```matlab
% optimizers: any of 'gsk' 'agsk' 'apgsk' 'atmals-gsk' 'egsk' 'fdb-agsk' 'dt-gsk'
optimizers   = {'gsk'};
functions    = [1 3];      % CEC2017 functions to run (F2 is always skipped)
dimensions   = [10];       % problem size D
runs         = 3;          % independent runs per function
use_parallel = false;      % one run at a time; section 5 explains parallel runs
```

### 4.1 From the MATLAB desktop

1. Start MATLAB.
2. Go to the repository root: in the **Current Folder** panel, browse to
   `C:\path\to\GSK_Family_MATLAB`, or type in the **Command Window**:

   ```matlab
   cd C:\path\to\GSK_Family_MATLAB
   ```

3. Double-click `run_all_cec2017.m` in the **Current Folder** panel. It opens
   in the **Editor**. Check the CONFIG block and save (**Ctrl+S**).
4. On the **Editor** tab, click **Run** (or press **F5**). If MATLAB asks to
   change the current folder, click **Change Folder**.
5. Watch the **Command Window**. Each function prints one row of results.
   After each dimension, a table compares your mean errors with the published
   reference results, and the last lines say where the results were saved.

Instead of clicking **Run**, you can also type the launcher's name in the
**Command Window**:

```matlab
run_all_cec2017
```

To stop a run, click in the **Command Window** and press **Ctrl+C**.

### 4.2 From a terminal (PowerShell)

MATLAB then runs without its desktop, prints the same output in the terminal,
and closes when the run is finished.

1. Open **PowerShell** (or Windows Terminal).
2. Go to the repository root:

   ```powershell
   cd C:\path\to\GSK_Family_MATLAB
   ```

3. Make sure the CONFIG block is set (for example `notepad run_all_cec2017.m`).
4. Start the run:

   ```powershell
   matlab -batch "run_all_cec2017"
   ```

   To also keep a copy of the output in a file:

   ```powershell
   matlab -batch "run_all_cec2017" | Tee-Object -FilePath first_run.log
   ```

If PowerShell says `matlab` is not recognized, use its full path, for example
`& "C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -batch "run_all_cec2017"`.
The command ends with exit code 0 when the run succeeds and a non-zero code on
an error, so it also works in scripts. To stop a run, press **Ctrl+C**.

### 4.3 Run everything: the full protocols

When the small test works, raise the settings. Each suite has its own
launcher, and they all work the same way. List several algorithms to run them
one after the other, for example
`optimizers = {'gsk', 'agsk', 'apgsk', 'fdb-agsk', 'atmals-gsk', 'egsk', 'dt-gsk'}`.
The standard settings are:

| Launcher | `functions` | `dimensions` | Budget per run (`max_nfes = 0`) | Runs per algorithm (`runs = 51`) |
|---|---|---|---|---|
| `run_all_cec2017.m` | `1:30` (F2 is dropped automatically) | `[10 30 50 100]` | 10,000 × D | 5,916 |
| `run_all_cec2011.m` | `1:22` | `0` (each problem's own dimension) | 150,000 | 1,122 |
| `run_all_cec2013.m` | `1:28` | `[10 30 50]` | 10,000 × D | 4,284 |
| `run_all_cec2020.m` | `1:10` | `[5 10 15 20]` | 50,000 to 10,000,000 | 1,836 (F1 and F8 have no data at D5 and D15) |
| `run_all_cec2013lsgo.m` | `1:15` | `0` (1000; 905 for F13, F14) | 3,000,000 | 765 |

> [!WARNING]
> A full campaign for one algorithm can take many hours (CEC2017 D = 100
> and CEC2013-LSGO are the slowest), so read section 5 first. The launchers
> start with `overwrite = true`, which moves the earlier results of every
> listed algorithm to an archive folder. To continue an interrupted campaign,
> or to add dimensions or algorithms without losing finished runs, set
> `overwrite = false`.

There is also a C++ command-line tool, `gsk_run`, that runs an experiment from
a config file; see the
[Command Reference](gsk_family/docs/getting-started/command_reference.md).

### 4.4 Original or changed settings: aliases

Every algorithm runs with its **original settings** (its published population
size and parameters) unless you say otherwise. Two ways to change them:

- **The same change for all algorithms:** the launcher's `np_init` (starting
  population size) and `min_pop_size` (final size of the algorithms that
  shrink their population). `[]` keeps each algorithm's original value.
- **A change for one algorithm, kept next to the original:** an **alias** in
  `algorithms.ini` (repository root). An alias is a name you choose for an
  algorithm plus its settings:

  ```ini
  [gsk-np50]
  base    = gsk
  np_init = 50
  ```

  Then use the name in the launcher like any algorithm:
  `optimizers = {'gsk', 'gsk-np50'}`. `gsk` runs with its original settings,
  `gsk-np50` with NP = 50, and each gets its own results folder.

`algorithms.ini` lists every setting of every algorithm with its original
value, and has a commented example for each one: remove the `;` to use it.

> [!NOTE]
> All aliases get the same seeds as the other algorithms, so comparisons stay
> fair. A misspelled setting stops the run and lists the accepted ones. After
> editing an alias that already has results, give it a new name: the runner
> refuses to mix two settings in one results folder. Aliases work in the
> MATLAB launchers and `run_experiment`, not in the `gsk_run` tool.

**Where the results go:** `gsk_family\results\_run_all\<algorithm>\<suite>\`

| File | Contents |
|---|---|
| `summary\<algorithm>_<suite>_D<D>.csv` | one row per function: Best, Median, Mean, Worst, SD of the error |
| `summary\per_run.csv` | every single run, with its seed |
| `summary\<algorithm>_D<D>_log_*.txt` | the printed report |
| `curves\`, `gen_logs\` | convergence data for plots (section 6) |

The meaning of every column is in [Result Schema](gsk_family/docs/reference/result_schema.md).

## 5. Running in parallel in MATLAB

Each run is independent, so MATLAB can do several runs at the same time on
different CPU cores. This needs the Parallel Computing Toolbox.

**Turn it on.** In the launcher's CONFIG block set:

```matlab
use_parallel = true;
```

(When calling the runner directly, pass `'use_parallel', true` to
`run_experiment`.) Parallel and serial runs use the same seeds, so the results
normally match; only the speed changes. For a strict bit-for-bit check, run
serially (`use_parallel = false`).

**Choose the number of workers yourself.** If no pool is open, the runner
starts one worker per physical CPU core. On a large machine that can use more
memory than you have. It is safer to open the pool yourself first; the runner
then uses your pool.

From the MATLAB desktop, type this in the **Command Window**, then press
**Run** in the launcher (or type `run_all_cec2017`):

```matlab
c = parcluster('Processes');   % process workers (needed by the MEX bridge)
c.NumWorkers = 8;              % allow up to 8 workers (this session only)
parpool(c, 8);                 % start 8 workers
```

When you are done, close the pool: `delete(gcp('nocreate'))`.

From a terminal, put the same steps in one command (the pool closes when
MATLAB exits):

```powershell
matlab -batch "c = parcluster('Processes'); c.NumWorkers = 8; parpool(c, 8); run_all_cec2017"
```

Use process workers (`'Processes'`), not thread workers (`'Threads'`): the MEX
bridge is not thread-safe, so the runner replaces a thread pool with a process
pool.

**How many workers?** Each worker is a separate copy of MATLAB.

| Rule of thumb | |
|---|---|
| Memory per worker | about 2 GB for D = 10 to 30, up to 3 GB or more for D = 50 and 100, and it grows slowly during long runs |
| Number of workers | at most the number of physical cores, and at most about (installed RAM in GB - 8) / 3 |
| Examples | 16 GB RAM: 2 to 3 workers; 32 GB: about 8; 64 GB: about 16 |

Leave memory for Windows and other programs. If memory runs out, a worker or
MATLAB itself crashes. You may see "Out of memory" or "remote execution
failure", or MATLAB may exit with an error. Watch "Memory" and "Committed" in
Task Manager (Performance tab) during the first hour.

**Long campaigns.** Workers slowly use more memory over many hours. For big
jobs:

1. Set `overwrite = false` in the launcher, so runs that already finished are
   kept and skipped.
2. Run one dimension at a time (for example `dimensions = [50]`, then
   `dimensions = [100]`), restarting MATLAB in between to free memory.
3. If a session crashes, start MATLAB again and run the launcher with the
   same settings and `overwrite = false` (Run button or terminal command).
   The run continues where it stopped.

## 6. Convergence figures and statistical analysis

When the runs are finished, one more file turns them into figures and tables
for a report or a paper. First run every algorithm you want to compare with
the **same** functions, dimensions and runs (section 4.3).

**Step 1.** Open `run_compare_algorithms.m` (in the repository root, next to
the launchers) and set its CONFIG block, for example:

```matlab
suites     = {'cec2017', 'cec2011'};   % which suites to analyze
optimizers = {'agsk', 'gsk'};          % {} = every algorithm with results
labels     = {};                       % {} = GSK, AGSK, ...; or your own names
proposed   = 'agsk';                   % tested against every other algorithm
```

**Step 2.** Press **Run** (or type `run_compare_algorithms` in the
**Command Window**). It only reads finished results, so you can run it again at
any time, also during a campaign.

**Step 3.** Open the results in `gsk_family\results\analysis\`:

| Output | File | What it shows |
|---|---|---|
| Convergence figures | `convergence\<suite>\<suite>_F<f>_D<d>.png` and `.pdf` | every algorithm's curve in one figure, for each function and dimension |
| Overview figures | `convergence\<suite>\<suite>_D<d>_overview.png` | all functions of one dimension at a glance |
| Result tables | `compare\<suite>\table_<suite>_D<d>.tex` and `.csv` | Mean (SD) of every algorithm per function, best in bold, +/=/− signs |
| Wilcoxon rank-sum | `compare\<suite>\ranksum_<suite>.csv` | per function: is the difference between two algorithms significant? With the Holm-corrected p-value and the effect size (A12, Cliff's delta) |
| Post-hoc tests | `compare\<suite>\posthoc_<suite>.csv` | after Friedman: proposed algorithm vs each competitor, with Holm, Hochberg, Finner and Bonferroni–Dunn corrections |
| CD diagram | `statistics\<suite>\cd_<suite>_D<d>.png` and `.pdf` | the algorithms on their mean rank; a bar joins those not significantly different |
| Box plots | `statistics\<suite>\box_<suite>_F<f>_D<d>.png` and `.pdf` | the final values of all runs of every algorithm, one figure per function |
| Rank charts | `statistics\<suite>\ranks_<suite>_bars.png` | Friedman mean ranks per dimension and overall |
| Runtime | `compare\<suite>\runtime_<suite>.tex`, `statistics\<suite>\runtime_<suite>.png` | seconds per run of every algorithm |
| ERT and ECDF | `performance\<suite>\ert_<suite>_D<d>.tex`, `ecdf_<suite>_D<d>.png` | how often and how fast each algorithm reaches target errors |
| Population dynamics | `dynamics\<suite>\diversity_*`, `xplxpt_*`, `population_*`, `parameters_*` | diversity, exploration/exploitation, population size and adaptive parameters over the run (needs `log_trace = true` when running) |
| Wilcoxon signed-rank | `compare\<suite>\wilcoxon_<suite>.csv` | over the whole suite: R+, R−, p-value |
| Friedman ranks | `compare\<suite>\friedman_<suite>.csv` | the mean rank of every algorithm (1 = best) |
| Settings table | `compare\<suite>\settings_<suite>.tex` and `.csv` | each algorithm's code, population sizes and changed settings ("original" = published value) |

**How to read it.** In the tables, **+** means the proposed algorithm is
significantly better than that competitor on that function, **−** that it is
significantly worse, and **=** that the difference is not significant
(two-sided test at the 5% level). In the Friedman table, a lower mean rank is
better.

> [!NOTE]
> The curves show the error f(x) − f(x\*) on a log scale for CEC2013, CEC2017
> and CEC2020. CEC2011 and CEC2013-LSGO have no known optimum, so their
> curves show the objective value. By default each algorithm's median run is
> drawn; set `curve = 'mean'` for the mean of all runs, and `band = 'iqr'` for
> a shaded 25–75% band of all runs under each curve. No toolbox is needed.

**Smoother ERT and ECDF curves.** By default each run records its best value
only at the 14 CEC checkpoints. Add `trace_points = 50;` to a launcher's
CONFIG block before running (a commented line is already there) to also log
it at 50 budgets; the runs themselves do not change.

**Population dynamics.** Add `log_trace = true;` to a launcher's CONFIG block
(a commented line is there) before running, and set `dynamics = true` in
`run_compare_algorithms.m`. You get diversity, exploration/exploitation,
population-size and parameter figures. The runs do not change.

**Sensitivity and ablation studies.** `make_study_aliases` writes the aliases
for a parameter grid (`make_study_aliases('sensitivity','gsk',{'kf',[0.3 0.5 0.7]})`)
or for your variant with one component switched off at a time
(`make_study_aliases('ablation','my-gsk',{'use_step_a'})`). Run them with a
launcher, then set `sensitivity` or `ablation` in `run_compare_algorithms.m`.
Step-by-step: [Comparing Algorithms](gsk_family/docs/research/comparing_algorithms.md).

**Algorithm complexity.** CEC2017 papers usually include the complexity table
of the CEC technical report (T0, T1, T̂2, (T̂2 − T1)/T0). Set
`complexity = true` in `run_compare_algorithms.m` (with `optimizers` listed),
or run `cec_complexity('suite','cec2017','optimizers',{'my-gsk','gsk'})`. It
times 5 runs of 200,000 evaluations per algorithm and dimension, so it takes a
while; keep the computer otherwise idle. The table goes to
`gsk_family\results\analysis\complexity\cec2017\`.

Every option, and how to call the two tools directly from your own scripts:
[Comparing Algorithms](gsk_family/docs/research/comparing_algorithms.md). To
add your own algorithm to the comparison: [New Variant Guide](NEW_VARIANT_GUIDE.md).

## 7. Common problems

| Message or symptom | What to do |
|---|---|
| `gskcec:mexMissingPrerequisite` or `gskcec:mexNotLoadable` | Build the MEX bridge (section 3, step 2). |
| The MEX build says it cannot replace the file | MATLAB still has the bridge loaded: run `gskcec_eval('clear'); clear mex` or close MATLAB, then build again. |
| `egsk:fminconUnavailable` | eGSK needs the Optimization Toolbox. |
| Out of memory, MATLAB exits during a parallel run | Use fewer workers (section 5) and continue with `overwrite = false`. |
| The parallel pool does not start | The runs continue one at a time with the same results; check the Parallel Computing Toolbox licence. |
| The first run is slow | MATLAB, the pool and the bridge start up once; later runs are faster. |
| `unknown optimizer 'x'` or a message naming `algorithms.ini` and a line | The name is not an algorithm or an alias, or the alias has a mistake; the message says which line and lists the accepted settings (section 4.4). |

More cases: [Troubleshooting](gsk_family/docs/getting-started/troubleshooting.md).

## 8. Build the HTML documentation

```powershell
cd C:\path\to\GSK_Family_MATLAB\gsk_family
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_docs.ps1 -Clean
```

Then open `gsk_family\docs\html\index.html` in a web browser. This runbook is
the page `runbook.html` there. The same command also refreshes `RUNBOOK.html`
and `NEW_VARIANT_GUIDE.html` next to this file: single-page copies of the two
guides for reading in a browser.

## 9. Where to go next

- [New Variant Guide](NEW_VARIANT_GUIDE.md): build your own GSK variant and compare it
  with the family.
- [Tutorial](gsk_family/docs/getting-started/tutorial.md): a guided first experiment.
- [User Guide](gsk_family/docs/getting-started/user_guide.md): all the ways to run.
- [Command Reference](gsk_family/docs/getting-started/command_reference.md): copy-paste
  commands for every algorithm.
- [Comparing Algorithms](gsk_family/docs/research/comparing_algorithms.md): add your own
  variant, convergence figures, Mean/SD tables and statistical tests.
- Algorithm guides: [GSK](gsk_family/docs/algorithms/gsk.md), [AGSK](gsk_family/docs/algorithms/agsk.md),
  [APGSK](gsk_family/docs/algorithms/apgsk.md), [FDB-AGSK](gsk_family/docs/algorithms/fdb-agsk.md),
  [ATMALS-GSK](gsk_family/docs/algorithms/atmals-gsk.md), [eGSK](gsk_family/docs/algorithms/egsk.md),
  [DT-GSK](gsk_family/docs/algorithms/dt-gsk.md).

## 10. Author and how to cite

This framework was designed and built by **Mostafa Elsayed Ahmed Masoud**, PhD
Candidate in Operations Research, Department of Operations Research, Faculty
of Graduate Studies for Statistical Research, Cairo University, Giza 12613,
Egypt (ORCID [0009-0003-8415-2158](https://orcid.org/0009-0003-8415-2158),
<moustafa.masoud@gmail.com>).

Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud. The notice covers this
framework's own code, tools and documentation. Each algorithm it runs (GSK,
AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, DT-GSK) and each benchmark suite
remains the work of its original authors; licensing and provenance are in
[gsk_family/LICENSES.md](gsk_family/LICENSES.md). Please keep this notice
and the author attribution.

> [!IMPORTANT]
> If you use this framework in a paper or thesis, please cite it
> (`gsk_family/CITATION.cff`) and the paper of every
> algorithm you use ([gsk_family/LICENSES.md](gsk_family/LICENSES.md)).
