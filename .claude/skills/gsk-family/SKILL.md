---
name: gsk-family
description: Step-by-step playbooks for the GSK Family MATLAB + C++ project - running or resuming CEC campaigns safely (exact chunk plan, pool sizing, monitoring, final pass, restoring backed-up runs), validating DT-GSK or any optimizer against imported reference runs and recording the results, editing comments and docs without changing code, changing optimizer code without changing results, rebuilding docs, link checks and pre-commit checks. Use for any task in this repository.
---

# GSK Family playbooks

Read `CLAUDE.md` (repository root) first: rules, current state, next steps.
`gsk_family/SKILL.md` has the architecture and the seed contract. Below,
`<G>` is the absolute path of `gsk_family/` with forward slashes (on the
owner's PC `D:/AI/Research-Lab/GSK_Family_MATLAB/gsk_family`). Other paths
are relative to `<G>`.

## Run or resume a campaign

**Never use a launcher for this**: launchers run with `overwrite = true`,
and their CONFIG values belong to the owner. Call the runner directly.
Example for DT-GSK on CEC2017; for another optimizer or suite change
`optimizer`, `suite`, `functions`, `dimensions` and `output_dir`.

1. **Preconditions.** `build/mex/gskcec_eval.mexw64` exists (else build the
   MEX bridge). No MATLAB process is running: `Get-Process MATLAB*` is empty.
2. **One chunk** = one background `matlab -batch` session. Open the pool
   before the run, write the log to the session scratchpad, and always pass
   `overwrite=false`:

   ```powershell
   matlab -batch "c = parcluster('Processes'); c.NumWorkers = 8; parpool(c, 8); addpath('<G>/src/runners'); run_experiment('optimizer','dt-gsk','suite','cec2017','functions',[1 3 4 5],'dimensions',100,'runs',51,'max_nfes',0,'project_root','<G>','output_dir','<G>/results/_run_all/dt-gsk/cec2017','overwrite',false,'verbose',false,'seed_policy','unified','rand_generator','threefry','use_parallel',true,'write_graphs',false); fprintf('CHUNK_DONE\n');" > <scratchpad>/chunk_d100_a.log 2>&1
   ```

   - **D100 chunk plan** (F2 is dropped automatically): `[1 3 4 5]`, `6:9`,
     `10:13`, `14:17`, `18:21`, `22:25`, `26:29`, `30`. Each chunk takes about
     1 to 2 hours on 8 workers.
   - D10/D30/D50 chunks can be a whole dimension each.
   - `max_nfes` 0 means the suite default (CEC2017: 10000*D).
   - DT-GSK always uses the unified seed and Threefry.
3. **Monitor.**
   - A chunk is done when the log shows `CHUNK_DONE` and the exit code is 0.
   - A nonzero exit, `remote execution failure` or `Out of memory` means a
     crash: run the same command again. Finished cells are reused when the
     seed, budget and generator match.
   - `summary/per_run.csv` gets a cell's 51 rows only when the whole cell
     finishes. Count progress with:
     `awk -F, 'NR>1 && $4==100' summary/per_run.csv | wc -l`
     (columns: optimizer, suite, function, dimension, run, seed,
     best_fitness, error, nfes, termination, runtime_seconds, max_nfes,
     rand_generator).
   - Between chunks check memory:
     `(Get-Counter '\Memory\Committed Bytes').CounterSamples[0].CookedValue/1GB`.
     If it nears the commit limit (about 56 of 64 GB on the owner's PC), drop
     to 6 workers. Budget about 2 GB per worker at D <= 30 and 3 GB or more
     at D >= 50.
4. **Completion targets.**
   - CEC2017 has 29 functions per dimension, so 1,479 runs per dimension.
   - A full campaign is 5,916 runs and 116 function cells.
   - Count unique `(dimension, function, run)` rows; stale history rows can
     exist.
5. **Final pass.** Use the same command with `'functions',1:30,'dimensions',[10 30 50 100]`
   and the same 8-worker pool. Nothing is computed when every run exists.
   Include only dimensions whose runs are in `summary/per_run.csv`; any
   missing dimension would be computed from scratch. The owner cleared
   `results/` on 2026-10-16, so D10–D50 are there only if their backup was
   restored.
   This pass rewrites `summary/<opt>_<suite>_D<d>.csv`, `environment.json`,
   `run_config.json` and `phase0_protocol.json`, so they describe the whole
   campaign.

**Restore backed-up runs** (for example after `results/` was cleared):
1. Create `results/_run_all/<opt>/<suite>/summary/`.
2. Copy the backed-up `per_run.csv` there. It must keep the header with
   `max_nfes` and `rand_generator`.
3. Run the final pass. Reused runs need no recomputation. Median-run curves of
   restored cells are missing; that only skips their graphs.

## Validate against reference runs

```matlab
cd('<G>'); addpath('scripts');
r = compare_reference_runs('results/_run_all/dt-gsk/cec2017', ...
      'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv', ...
      'out', 'results/_run_all/dt-gsk/cec2017/summary/comparison.csv', 'verbose', false);
fprintf('%d cells: %d MATCH, %d DIFFERS, Holm-significant %d\n', r.cells, r.matches, r.differs, r.holm_significant);
T = r.table;  % dim, func, best/median/mean_gen/_ref, best_ok, median_ok, mean_ok, p_ranksum, p_signrank, p_holm, verdict
```

- **MATCH** means a two-sided rank-sum p >= 0.05, and Best, Median and Mean
  each within one decade. Both sides are first rounded to 11 significant
  digits (the reference file's precision); keep that default.
- `p_signrank` pairs runs by run id. It is computed only when both sides used
  the same seed for every run, and it is informational: paired runs are
  near-replicas, so tiny last-digit offsets can look significant. Use
  `p_holm` for the multiple-test view.
- **Project check.** Run
  `build\gsk_validate.exe --verify results\_run_all\dt-gsk\cec2017 benchmarks\cec_reference_results --full`.
  It needs the summary tables, so run it after the final pass. It writes
  `summary/verification.json`, or `verification_<n>.json` if one exists; read
  the path it prints after "report:".
- **Record the results.** The DT-GSK README "CEC2017 campaign" section is the
  one place for the numbers. Keep its table columns: D | Functions | Match |
  Rank-sum p < 0.05 | Lowest rank-sum p. Then:
  - list every DIFFERS cell with which statistic differs and why;
  - update the one-line summaries in `docs/research/validation_report.md` and
    `docs/algorithms/dt-gsk.md` ("all N of 116 functions agree ...");
  - add a CHANGELOG "Unreleased" line;
  - update `CLAUDE.md` (current state and next steps).
- **If a cell DIFFERS beyond Best, or the verdict is DEVIATES:** still record
  it, change no optimizer code, and report to the owner the cell, the
  p-values, which statistic differs, the likely cause and a suggested
  follow-up (for example, rerun that cell serially).

## Edit comments or docs without changing code

- Style: plain English, short sentences. Keep every fact (shapes, indexing,
  units, seeds, budgets, error IDs, the reasons for quirks); drop history and
  filler. Keep license notices, directives (`%#ok`, `NOLINT`, Doxygen tags,
  `%%` cells) and the MATLAB H1 line form `%NAME One-line summary.`.
- Never edit `benchmarks/cec_suite_cpp/cec2017/src/cec17_func.cpp` (its SHA256
  is quoted in `cec2017/src/README.md`) or
  `benchmarks/cec_suite_cpp/cec2020/src/cec20_func.cpp`. Both are verbatim
  upstream copies and are never compiled.
- **Prove the edit is comment-only** against `git show HEAD:<path>`:
  - use the owner's local checker if available (memory: gsk-local-tools);
  - otherwise, for C++, compare `g++ -fpreprocessed -dD -E -P` output of the
    old and new files; for MATLAB, review `git diff --word-diff` line by line
    (text after `...` is a comment; strings must not change);
  - then rebuild and run all tests.
- Docs live in `docs/**`. The beginner page is the repository-root
  `RUNBOOK.md`. The detailed commands are in
  `docs/getting-started/command_reference.md`.

## Change optimizer code without changing results

Every optimizer has opt-in trace lines (`if tr.on; ... gsk_trace_add ...`,
`options.log_trace`). Keep them record-only, and include tracing-on runs in
the bit-identity check (`test_dynamics_trace.m` compares on and off).

1. **DT-GSK:** use the owner's oracle if available (memory: gsk-local-tools;
   25 fixed cases with stored baselines, `oracle_run` then `oracle_compare`).
2. **Otherwise**, before editing save baselines for fixed cases, then rerun
   them after the edit and require `isequal` on every field:

   ```matlab
   addpath(genpath('<G>/src')); addpath('<G>/build/mex');
   p = gskcec_make_problem('cec2017', f, D, '<G>', max_nfes);   % small budgets for speed
   r = <opt>_optimize(p, struct('seed', s));                    % keep best_x, best_fitness, nfes, convergence
   ```

   Cover D = 10, 30, 50 and 100 and a sphere case. Bit identity is the bar for
   refactors, renames and comment edits.
3. Run the MATLAB tests. `test_dt_gsk_smoke` checks the reference sphere
   golden values (seed 12345, 3,000 evaluations).
   - **Budget check:** on the same cases with `log_trace` on, require
     `result.nfes <= max_nfes`, `max(result.convergence.nfes) <= max_nfes`
     and nondecreasing `result.trace.rows(:,1)`. eGSK alone may overshoot
     slightly (its `fmincon` refinement; documented in
     `docs/algorithms/egsk.md`); its `nfes` must still equal the run before
     the edit.
   - **Before merging,** all of these must pass: the tests, the 25-case oracle
     (all IDENTICAL), trace off and on identical to the saved baseline, and
     the budget check. Report a failure; do not merge around it.
4. A numeric change to a port needs a note in
   `docs/reference/porting_notes.md` and the owner's approval.

## Rebuild and check

```powershell
cmake --build build -j; ctest --test-dir build            # 13/13
powershell -File scripts\build_mex_bridge.ps1             # after C++ suite or MEX changes
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"   # "All 16 test(s) passed."
powershell -File scripts\build_docs.ps1 -Clean            # 49 pages + the two root guides
```

Link check after a docs build. It must print nothing:

```powershell
Get-ChildItem docs\html\*.html, ..\RUNBOOK.html, ..\NEW_VARIANT_GUIDE.html | ForEach-Object {
  $f = $_; $html = Get-Content $f.FullName -Raw
  foreach ($m in [regex]::Matches($html, 'href="([^"#:]+)(#[^"]*)?"')) {
    if (-not (Test-Path (Join-Path $f.DirectoryName $m.Groups[1].Value))) { "$($f.Name): $($m.Groups[1].Value)" } } }
```

## Before committing

All three checks must return nothing. Run them from `<G>`; the CI that would
run them is inactive. `rg` is ripgrep; if it is not installed, use Claude
Code's Grep tool with the same patterns.

```powershell
rg --files . | rg '\.(py|pyx)$|cec2013\.cpp$'
rg --files benchmarks\cec_suite_cpp | rg '\.(m|R|c|py|pyx)$|cec2013\.cpp$'
rg -i "python|numpy|scipy|pypi|cython|pytest" -g "!**/evidence/**" -g "!**/.github/**"
```

The third check skips `.github/`: the CI contract check there names `*.py`
on purpose. The only other expected hit is this skill file, which holds the
word list (`rg` skips hidden folders by default; the Grep tool does not). Then follow the git rule in `CLAUDE.md`: branch, commit, and
fast-forward only on the owner's word.

**Authorship and licence check** (a change that touches notices, citations or
`LICENSES.md`):
- Copyright notices cover only the framework's own work. They state that
  each algorithm and benchmark suite stays with its original authors, and
  they name no licence. Every third-party author, DOI and licence row stays.
- Licensing changes (the GPL "pending confirmation" text, a licence name in
  a header, new redistribution terms) need the owner's separate approval.
- The framework `.m` files end their help text with this 3-line block (keep it
  exact; it is comment-only):

  ```text
  % Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
  % Cairo University: this framework code only; each algorithm belongs to its
  % original authors. Licensing: gsk_family/LICENSES.md. Cite gsk_family/CITATION.cff.
  ```

- DT-GSK citation: *Algorithms* 19(9), 769 (2026), DOI 10.3390/a19090769.
  `codemeta.json` must still parse after edits.

## Run an optimizer with changed settings (aliases)

- Add an `[alias]` to `algorithms.ini` in the repository root (`base =` plus
  settings) and list the alias in the launcher's `optimizers`, or pass it as
  `'optimizer'` to `run_experiment`. Never put an alias in the owner's
  launcher CONFIG without being asked.
- Plain names must give bit-identical results after any change to alias
  handling: rerun the seven plain on a few CEC2017 cells and compare
  `per_run.csv` with a run made before the change (`isequal` on
  `best_fitness`, `seed`, `nfes`).
- A new option of one of the seven goes into `alias_setting_names` in
  `run_experiment.m`, the table in `docs/getting-started/command_reference.md`
  ("Algorithm aliases") and the list at the top of `algorithms.ini`.

## Add a new optimizer

The quick path for a researcher is `new_gsk_variant('<name>','base','<one of
the seven>')` (no registration for MATLAB runs; `NEW_VARIANT_GUIDE.md`). For a
family member with reference reproduction, follow
`docs/development/extension_guide.md`. In short:

- Create `src/optimizers/<slug>/<slug_underscored>_optimize.m` with the
  result contract of `docs/reference/matlab_interface.md`.
- Register the slug in `src/runners/run_experiment.m`:
  `canonical_optimizer_id`, `optimizer_function_stem`, and the seed and
  generator switches.
- Register it in the C++ tools: `kOptimizers` in
  `benchmarks/cec_suite_cpp/cec_tools/src/cli/gsk_run.cpp`, and `gsk_list.cpp`.
- Add `src/tests/test_<slug_underscored>_smoke.m`.
- Add `docs/algorithms/<slug>.md` and list it in `scripts/build_docs.ps1`.
