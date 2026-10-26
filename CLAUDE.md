# CLAUDE.md

Orientation for Claude Code sessions. This file, `gsk_family/SKILL.md`
(architecture, seed contract, preservation rules) and the `gsk-family` skill
(`.claude/skills/gsk-family/SKILL.md`: step-by-step playbooks with exact
commands) are enough to continue work without re-reading the repository.
`RUNBOOK.md` is the human how-to. The DT-GSK validation record is
`gsk_family/src/optimizers/dt-gsk/README.md`. The owner's private notes
(machine limits, local tools, backups) are in Claude's project memory, outside
the repository. For project state, this file is authoritative.

## The project in brief

Seven Gaining-Sharing Knowledge optimizers in MATLAB (`gsk`, `agsk`, `apgsk`,
`fdb-agsk`, `atmals-gsk`, `egsk`, `dt-gsk`) run on five CEC benchmark suites
(`cec2011`, `cec2013`, `cec2013lsgo`, `cec2017`, `cec2020`). The benchmark
functions are C++20 ports that MATLAB calls through one MEX bridge
(`gskcec_eval`). `gsk_run` writes a CONSISTENT/DEVIATES verdict
(`verification.json`) for every run. Launcher and direct `run_experiment` runs
print a comparison table; run `gsk_validate --verify` for the verdict.

```text
<repo root>   git root; origin = github.com/MostafaMassoud/GSK_Family_MATLAB
  CLAUDE.md  README.md  RUNBOOK.md  RUNBOOK.html (generated, tracked)  build.txt  .gitignore
  run_all_cec2011.m ... run_all_cec2020.m      launchers (owner's CONFIG block at the top)
  .claude/skills/gsk-family/SKILL.md           playbooks
  gsk_family/                                  the project ("project root" in its docs)
    src/{optimizers,runners,common,experiments,tests}     MATLAB
    benchmarks/cec_suite_cpp/      C++ suites, input data, cec_tools (CLIs, MEX, C++ tests)
    benchmarks/cec_reference_results/   imported reference tables (read-only)
    scripts/ docs/ configs/ .github/ CMakeLists.txt SKILL.md README.md LICENSES.md
    CHANGELOG.md CITATION.cff codemeta.json build.txt
    build/  results/  docs/html/   generated, gitignored
```

## Rules (the owner's; always follow)

- **MATLAB and C++ only** in the repository. Comments and docs never name the
  reference implementation's language or its libraries; write "the reference
  implementation". CI would enforce part of this but does not run (see
  decisions below), so before any commit run the checks in the skill,
  "Before committing".
- **Fidelity over cleverness.** Preserve reference numerics and documented
  quirks (`gsk_family/docs/reference/porting_notes.md`). Never weaken a test
  tolerance. When results disagree with a reference, record and report the
  difference with a likely explanation; never tune code to force agreement.
- **Launchers:** never change the owner's CONFIG values in `run_all_cec*.m`
  (comments only). Do not run launchers for campaign work: their CONFIG has
  `overwrite = true`, which moves the existing result tree aside. Call
  `run_experiment` directly with `overwrite=false` (skill).
- **Read-only:** `gsk_family/benchmarks/cec_reference_results/**` (including
  `evidence/`), the verbatim upstream files `cec17_func.cpp` and
  `cec20_func.cpp`, and the external DT-GSK reference implementation v2.46
  (github.com/MostafaMassoud/DT-GSK; local copy noted in the owner's memory).
- **No new folder structures**; work in the existing layout. Never hand-edit
  `docs/html/`, `RUNBOOK.html` or `NEW_VARIANT_GUIDE.html`; regenerate them
  with `build_docs.ps1` (the root pages' design is the `$rootTemplate` in
  that script). Commit each root `.md` with its `.html`.
- **Git:** commit only when asked. On `main`, create a branch
  (`docs/<topic>`, `fix/<topic>` or `feat/<topic>`), commit there, and
  fast-forward `main` only when the owner says so. Never push (the owner
  pushes). Licensing stays in `gsk_family/LICENSES.md` (no root `LICENSE`
  file).
- Comment-only edits must leave code identical outside comments: check it
  (skill) and run the tests.
- **Authorship and licensing.** Copyright notices cover only the framework's own
  work. Never claim the algorithms or benchmark suites, never remove a
  third-party attribution, and never name or change a licence without the
  owner's explicit review (licensing lives in `LICENSES.md`).
- **Before merging** a change to an optimizer, run the MATLAB tests, the
  owner's 25-case DT-GSK oracle, the trace-on/trace-off identity check and
  the evaluation-budget check (skill, "Change optimizer code without changing
  results"). Report any failure; never bypass it.

## Commands (PowerShell, from `gsk_family/` unless noted)

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release   # once
cmake --build build -j; ctest --test-dir build                        # expect 13/13 C++ tests
powershell -File scripts\build_mex_bridge.ps1                         # MEX bridge (close MATLAB first)
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"               # expect "All 16 test(s) passed."
powershell -File scripts\build_docs.ps1 -Clean                        # 49 pages + the two root guides
```

From Git Bash, give MATLAB Windows paths (`D:/...`), never `/d/...`. Run
anything longer than a few minutes in the background, with logs in the
session scratchpad, never in the repository.

## Current state (2026-10-26)

- `main` = `0867d00`, the owner's latest fast-forward. Origin has everything up
  to `84b3742`; `0867d00` was not pushed when this was written (the owner
  pushes). Merged local branches that can be deleted with the owner's OK:
  `docs/share-ready-runbook`, `docs/claude-handoff`, `feat/compare-algorithms`,
  `feat/variant-guide`, `feat/my-gsk`, `feat/algorithm-aliases`,
  `feat/q1-statistics`, `feat/q1-group-b`, `feat/q1-group-c`.
- **Checks, 2026-10-26 on `0867d00`:**
  - all 16 MATLAB tests pass;
  - the owner's DT-GSK oracle gives 25/25 IDENTICAL (cases 18 and 22
    included);
  - 42 fixed cases (all optimizers and `my-gsk`) are bit-identical to before
    group C, with the trace off and on;
  - the docs build gives 49 pages and the two root guides, with no broken
    links.
  - The C++ tests (13) were not rerun this session; no C++ changed.
- **Evaluation budget:** every optimizer stays within `max_nfes` except eGSK.
  Its `fmincon` refinement can overshoot slightly (4032/4000 and 6001/6000 in
  the gate). This is the reference's documented behaviour
  (`docs/algorithms/egsk.md`), not a bug; do not "fix" it.
- **Authorship (`84b3742`, `0867d00`):**
  - Mostafa Elsayed Ahmed Masoud, ORCID 0009-0003-8415-2158, Cairo University.
    The name appears in `CITATION.cff`, `codemeta.json`, `LICENSES.md`, both
    READMEs, RUNBOOK section 10, NEW_VARIANT_GUIDE section 12 and the docs
    footers.
  - DT-GSK is cited as *Algorithms* 19(9), 769 (2026), DOI
    10.3390/a19090769 (verified by the owner).
  - The framework's `.m` files end their help text with a 3-line copyright
    comment: the launchers, `run_compare_algorithms`, `run_experiment`,
    `read_algorithm_aliases` and `scripts/*.m`.
  - Notices cover only the framework's own work. Each algorithm and
    benchmark suite stays with its original authors, file headers name no
    licence, and the licensing in `LICENSES.md` is unchanged (see Rules).
- **Q1 analyses, group C (`5e287f8`; the owner approved the optimizer edits):**
  - opt-in `options.log_trace` in all seven optimizers and `my-gsk`
    (record-only lines; helpers `src/common/gsk_trace_*.m`);
  - runner options `'log_trace'` and `'trace_rows'`, which write
    `trace/Dynamics_*.csv`;
  - a commented `log_trace` line in the launchers;
  - `scripts/plot_dynamics.m` (diversity, exploration/exploitation,
    population size, parameters), and `dynamics` in
    `run_compare_algorithms.m`;
  - the test `test_dynamics_trace.m`.
  - Any later edit of an optimizer must keep the trace lines record-only.
- **Q1 analyses, group B (`3c2ce91`):**
  - runtime table and chart;
  - `plot_performance.m` (success rate, ERT, ECDF);
  - `make_study_aliases.m`, `plot_sensitivity.m` and `plot_ablation.m`;
  - the runner's opt-in `trace_points` (`gen_logs/BestTrace_*.csv`).
- **Q1 statistics, group A (`3e5831a`):**
  - `compare_algorithms` gains post-hoc tests (Bonferroni-Dunn, Holm,
    Hochberg, Finner), Iman-Davenport, the Nemenyi CD, Holm-adjusted rank-sum
    p and effect sizes (A12, Cliff's delta);
  - `plot_statistics.m`: CD diagram, box plots, rank charts; violins are
    opt-in with >= 20 runs;
  - IQR bands in `plot_convergence`;
  - `cec_complexity.m`.
  - The owner approved the box-plot style; use it for new charts: light fill,
    coloured edge, median line, every run as a dot, no top/right border,
    light theme. They rejected the violin look.
- **Algorithm aliases (`e7e78ce`):**
  - `algorithms.ini` (root; examples commented) names an optimizer plus its
    own settings.
  - Launchers, `run_experiment` and `run_compare_algorithms` take an alias
    like an optimizer. The base decides code, seeds and options; the alias
    names files and results.
  - `compare_algorithms` writes `settings_<suite>.csv/.tex`.
  - `gsk_run`/YAML do not read aliases (owner's choice).
- **Researcher tools:**
  - `my-gsk` (`faf0567`): an unedited GSK copy that reproduces GSK exactly.
  - `3269d00`: `scripts/new_gsk_variant.m`, the root
    `run_compare_algorithms.m`, the root `NEW_VARIANT_GUIDE.md`/`.html` and
    the root page design.
  - `7d42135`: `plot_convergence.m`, `compare_algorithms.m`,
    `docs/research/comparing_algorithms.md`, and user-added optimizers that
    need no registration.
  - The p-values equal the Statistics Toolbox's.
- **DT-GSK CEC2017 validation:** D10, D30 and D50 are complete (4,437 runs:
  51 per function, unified seeds, Threefry, full budget).
  - 85 of 87 functions match the reference runs (rank-sum p >= 0.05; Best,
    Median and Mean within one decade).
  - D10 F26 and D50 F4 differ only in Best (one lucky run each).
  - `gsk_validate --verify` reported CONSISTENT.
  - The numbers are recorded in the DT-GSK README. **D100 has not been run.**
- **The owner cleared `gsk_family/results/` on purpose** (2026-10-16). Keep
  it empty unless asked; tests and checks write to the session scratchpad.
  - A private backup of the D10–D50 `per_run.csv` exists (owner's memory:
    gsk-local-tools).
  - Restoring it to `results/_run_all/dt-gsk/cec2017/summary/per_run.csv`
    would let the runner reuse all 4,437 runs. Re-running them would cost
    about 51 CPU hours.

## Next steps

1. **Finish DT-GSK CEC2017 D100** (1,479 runs, about 7 to 13 hours on 8
   workers), but only when the owner asks.
   - First ask: restore the D10–D50 backup, so the final pass and the
     comparison cover all 116 functions? Or run and compare D100 alone (29
     functions, final pass with `'dimensions',100` only)?
   - Use the chunk plan, the exact commands and the completion checks in the
     skill, "Run or resume a campaign". The reference evidence covers D10 to
     D100, 5,916 runs.
   - Afterwards, update the DT-GSK README table, the one-line summaries in
     `docs/research/validation_report.md` and `docs/algorithms/dt-gsk.md`, a
     CHANGELOG line, and this file.
2. **Owner decisions still open** (present the options, do not decide):
   - **License:** `LICENSES.md` calls GPL-3.0-or-later "pending
     confirmation" (the CEC2013 suite's GPL (>= 3) is the binding
     constraint), and the project rule says no root `LICENSE` file. Any
     licensing change needs the owner's separate, explicit review.
   - **Email:** the files use `moustafa.masoud@gmail.com`; git commits use
     `dr.moustafa.masoud@gmail.com`.
   - **Copyright comments in the optimizer ports:** not added, because the
     ports are of other authors' algorithms. Add them only if the owner asks.
   - **CI:** `gsk_family/.github/workflows/ci.yml` never runs, because the git
     root is the parent folder. Options: move it to `.github/workflows/` with
     `working-directory: gsk_family`, or keep running the checks locally.
   - **Repository size:** about 0.5 GB, mostly reference convergence curves.
     Options: keep, or move them to Git LFS or a release archive.
   - **Version:** 1.0.0 everywhere. Bump `CITATION.cff`, `codemeta.json`,
     `CMakeLists.txt` and the CHANGELOG together (for example to 1.1.0).
   - **eGSK `fmincon` thread count:** results can differ between parallel and
     serial runs. Options: (a) document it, (b) call `maxNumCompThreads(1)`
     inside eGSK runs, (c) validate eGSK serially only.
   - **`run_all_cec2011.m`** CONFIG runs only problems `4:6`; the full suite is
     `1:22`. It is the owner's value.
   - **Maintainer prompts:** whether `docs/prompts/` stays in the public docs
     site.
   - **Root `.gitattributes`:** for example `* text=auto`, `*.mexw64 binary`,
     to fix line endings and silence the CRLF warnings.
3. DT-GSK on the other suites is **not planned**: CEC2017 is the validation
   target. A tiny check showed their summary folders get the same files as
   GSK's.

## Pitfalls learned

- **Memory.** If no pool is open, `run_experiment` starts one worker per
  physical core (16 here). Workers grow to about 2.6 GB each over hours, and
  this crashed long campaigns twice. Open an 8-worker pool first, run long
  campaigns as short `matlab -batch` chunks, and check committed memory
  between chunks (skill).
- **Summary files after chunked runs.** `environment.json`, `run_config.json`
  and `phase0_protocol.json` describe only the latest call. The per-dimension
  tables merge earlier rows. `per_run.csv` gets a cell's rows only when all 51
  runs of that function and dimension finish, so a crash loses the cell in
  progress. After chunked runs, finish with one pass over everything.
- **Reference precision.** Reference `per_run.csv` files keep 11 significant
  digits; keep the `compare_reference_runs.m` default `sig_digits` 11.
- **MEX rebuild** fails while MATLAB holds the bridge: run
  `gskcec_eval('clear'); clear mex` or close MATLAB first.
- **Line-ending warnings.** Git prints "LF will be replaced by CRLF" for many
  files (`core.autocrlf`); they are harmless.
