# Runbook

How to set up the project and run your first experiment, step by step. No prior
knowledge of the code is needed. For every option of every algorithm, see the
[Command Reference](gsk_family/docs/getting-started/command_reference.md).

**What the project does:** it runs seven optimization algorithms (GSK, AGSK,
APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK) on the standard CEC benchmark suites
(CEC2011, CEC2013, CEC2013-LSGO, CEC2017, CEC2020) and saves tables of results.
The algorithms are written in MATLAB. The benchmark functions are written in C++
and are called from MATLAB through a small compiled bridge (a "MEX file").

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
| Statistics and Machine Learning Toolbox | only `gsk_family/scripts/compare_reference_runs.m` | that one script stops; everything else works |

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
  run_all_cec2011.m             <- launchers: open one in MATLAB and press Run
  run_all_cec2013.m
  run_all_cec2013lsgo.m
  run_all_cec2017.m
  run_all_cec2020.m
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

Every test should print `PASS`. You only repeat steps 1-3 after changing C++
code (steps 1 and 2) or to re-check the setup.

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

### 4.3 Next steps

When the small test works, raise the settings. The standard CEC2017 protocol
is `functions = 1:30`, `dimensions = [10 30 50 100]`, `runs = 51`. A full
campaign for one algorithm can take many hours, so read section 5 first. The
other launchers (`run_all_cec2011.m`, `run_all_cec2013.m`,
`run_all_cec2013lsgo.m`, `run_all_cec2020.m`) work the same way for their
suites. There is also a C++ command-line tool, `gsk_run`, that runs an
experiment from a config file; see the
[Command Reference](gsk_family/docs/getting-started/command_reference.md).

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

## 6. Compare algorithms: convergence figures and tables

To compare algorithms, for example GSK and your own variant, run them all
with the same settings (list them in the launcher, e.g.
`optimizers = {'gsk', 'my-gsk'}`). Then type in MATLAB, in the `gsk_family`
folder:

```matlab
addpath('scripts');
plot_convergence('suite','cec2017', 'optimizers',{'my-gsk','gsk'});
compare_algorithms('suite','cec2017', 'optimizers',{'my-gsk','gsk'}, 'proposed','my-gsk');
```

- `plot_convergence` draws one figure per function and dimension with every
  algorithm's convergence curve, plus one overview per dimension, as PNG and
  PDF in `results\analysis\convergence\<suite>\`.
- `compare_algorithms` writes Mean (SD) tables (CSV and LaTeX), the Wilcoxon
  rank-sum test per function (+/=/-), the Wilcoxon signed-rank test (R+, R-,
  p) and the Friedman ranks, in `results\analysis\compare\<suite>\`.

Both work for every suite and every algorithm. How to add your own variant,
all options, and how to read the results:
[Comparing Algorithms](gsk_family/docs/research/comparing_algorithms.md).

## 7. Common problems

| Message or symptom | What to do |
|---|---|
| `gskcec:mexMissingPrerequisite` or `gskcec:mexNotLoadable` | Build the MEX bridge (section 3, step 2). |
| The MEX build says it cannot replace the file | MATLAB still has the bridge loaded: run `gskcec_eval('clear'); clear mex` or close MATLAB, then build again. |
| `egsk:fminconUnavailable` | eGSK needs the Optimization Toolbox. |
| Out of memory, MATLAB exits during a parallel run | Use fewer workers (section 5) and continue with `overwrite = false`. |
| The parallel pool does not start | The runs continue one at a time with the same results; check the Parallel Computing Toolbox licence. |
| The first run is slow | MATLAB, the pool and the bridge start up once; later runs are faster. |

More cases: [Troubleshooting](gsk_family/docs/getting-started/troubleshooting.md).

## 8. Build the HTML documentation

```powershell
cd C:\path\to\GSK_Family_MATLAB\gsk_family
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_docs.ps1 -Clean
```

Then open `gsk_family\docs\html\index.html` in a web browser. This runbook is
the page `runbook.html` there. The same command also refreshes `RUNBOOK.html`
next to this file, a single-page copy of this runbook for reading in a browser.

## 9. Where to go next

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
