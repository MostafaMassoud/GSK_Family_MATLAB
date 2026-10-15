# Inline Documentation Review Prompt

> **What this page is.** A focused prompt for reviewing inline documentation:
> MATLAB help text, `%` comments, C++ Doxygen comments, script comments, config
> comments, and test comments. **For.** Maintainers who want code-adjacent prose
> refreshed without changing behavior. **Prerequisites.** The reviewer can read
> MATLAB, C++, CMake, PowerShell, YAML configs, and the existing docs. **After
> using it** comments should be accurate, concise, helpful, and aligned with the
> current implementation.

This prompt is intentionally narrower than [REVIEW_PROMPT.md](REVIEW_PROMPT.md)
and [DOCS_DEEP_REVIEW_PROMPT.md](DOCS_DEEP_REVIEW_PROMPT.md). It is for inline
documentation only. If a comment reveals a real bug, report the bug separately;
do not hide behavior changes inside a comment-cleanup pass.

---

```text
You are an inline-documentation review team for the hybrid MATLAB + C++
`gsk_family` project. Review comments, help text, Doxygen blocks, config notes,
script comments, and test comments for accuracy and usefulness. Preserve all
runtime behavior.

Project root:

  <workspace>\gsk_family

Also include the root MATLAB launchers one level up:

  <workspace>\run_all_cec2011.m
  <workspace>\run_all_cec2013.m
  <workspace>\run_all_cec2013lsgo.m
  <workspace>\run_all_cec2017.m
  <workspace>\run_all_cec2020.m

===============================================================================
1. GROUND RULES
===============================================================================

1. Review inline documentation only.
2. Do not change optimizer mathematics, benchmark objective logic, RNG behavior,
   seed formulas, result schemas, file naming, evaluation budgets, or stopping
   criteria.
3. If a comment reveals a behavior bug, record a finding with file:line and
   evidence. Do not silently fix behavior in this pass.
4. Prefer short, purposeful comments. Good comments explain why a non-obvious
   choice exists, what invariant must be preserved, or what external protocol a
   line implements.
5. Remove comments that merely restate obvious code.
6. Remove stale TODO/FIXME/HACK notes only when they no longer describe real
   work. If the debt is real, rewrite it with a concrete condition or pointer.
7. Preserve comments that protect reproducibility, reference compatibility,
   path safety, or benchmark provenance.
8. Keep terminology consistent:
   - optimizer IDs: `gsk`, `agsk`, `apgsk`, `fdb-agsk`, `atmals-gsk`, `egsk`,
     `dt-gsk`;
   - MATLAB function names use underscores where required;
   - benchmark path is `benchmarks/cec_suite_cpp`;
   - reference-result path is `benchmarks/cec_reference_results`.
9. Do not add Python examples, Python scripts, or Python-specific terminology to
   this MATLAB/C++ project. Comments that cite the DT-GSK Python reference
   implementation as provenance (its names, tests, or version) are allowed.
10. Every revised comment should help a future maintainer avoid a mistake.

===============================================================================
2. CURRENT BEHAVIOR THAT COMMENTS MUST MATCH
===============================================================================

- `run_experiment.m` defaults to `seed_policy='unified'`,
  `rand_generator='threefry'`, `overwrite=false`, `use_parallel=false`, and
  `write_graphs=false`.
- Root `run_all_cec*.m` launchers expose `overwrite`, `write_graphs`,
  `use_parallel`, `seed_policy`, and `rand_generator` in their CONFIG blocks.
- `overwrite=false` resumes/appends; `overwrite=true` archives the previous
  active output tree under `_overwrite_archive/` and starts clean.
- `write_graphs=false` skips slow PNG graph rendering only. Numeric
  `curves/*.csv` and `gen_logs/*.csv` are still written.
- Unified seed:

  seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1

- Reference seeds:
  - GSK/eGSK/ATMALS-GSK: `base_seed + 9973*func + run - 1`
  - AGSK/APGSK/FDB-AGSK: `D*func*run`
  - DT-GSK: the unified seed + `threefry` under every seed policy
    (`is_unified_only`); it samples its own NP = 5*D population and ignores a
    runner `X0` (documented fair-start exception).
- CEC2017 F2 is implemented but excluded from default comparisons.
- ATMALS-GSK on CEC2017 reports absolute error.
- eGSK's fmincon-dependent refinement must not be silently stubbed when the
  Optimization Toolbox is unavailable.
- CEC benchmark calls go through the `gskcec_eval` MEX bridge into C++ ports.
- Imported reference evidence is read-only during normal runs.

===============================================================================
3. INVENTORY COMMANDS
===============================================================================

Start read-only:

  rg -n "%|TODO|FIXME|HACK|XXX|NOTE|warning|compatibility|overwrite|seed|rng|F2|fmincon|graph|reference" src ..\run_all_cec*.m scripts configs benchmarks\cec_suite_cpp\cec_tools -g "*.m" -g "*.cpp" -g "*.hpp" -g "*.h" -g "*.ps1" -g "*.yml" -g "*.txt"

Then inspect high-impact files:

- `src/runners/run_experiment.m`
- `src/runners/get_cec_seed.m`
- `src/runners/derive_run_seed.m`
- `src/runners/gskcec_make_problem.m`
- `src/runners/verify_unified_seed_schedule.m`
- `src/common/*.m`
- `src/optimizers/*/*.m`
- root `run_all_cec*.m`
- `scripts/*.ps1`
- `scripts/*.m`
- `configs/*.yml`
- `configs/README.md`
- `benchmarks/cec_suite_cpp/cec_tools/include/**/*.hpp`
- `benchmarks/cec_suite_cpp/cec_tools/src/**/*.cpp`
- `benchmarks/cec_suite_cpp/cec_tools/src/**/*.hpp`
- `CMakeLists.txt`

===============================================================================
4. REVIEW PHASES
===============================================================================

Phase A - MATLAB help text:

- Every public `.m` function should have a concise help block when it is called
  directly or is a shared utility.
- Help text must state important parameters, return shape, side effects, RNG
  behavior, and benchmark assumptions only where those facts are not obvious.
- Do not over-document trivial local helpers.

Phase B - Runner comments:

Check comments around:

- argument parsing;
- path setup;
- overwrite/archive path safety;
- resume/add checks;
- seed schedule;
- unified `X0`;
- parfor process pool;
- CEC problem handle cleanup;
- result writing;
- graph rendering.

Comments must clarify invariants, especially where changing a line could alter
RNG draw order, NFEs, or output schema.

Phase C - Optimizer comments:

For each optimizer, comments should explain:

- initialization source (`X0` vs optimizer draw);
- main update phases;
- junior/senior or adaptive mechanisms;
- bounds repair;
- selection and best-so-far tracking;
- evaluation-budget accounting;
- stopping criteria;
- reference quirks intentionally preserved.

Do not add broad tutorial prose inside optimizer code. Put long explanations in
`docs/algorithms/*.md` (DT-GSK: `src/optimizers/dt-gsk/README.md`).

Phase D - C++ and MEX comments:

Review Doxygen comments and inline notes for:

- benchmark factory ownership;
- suite/function/dimension validation;
- input data loading;
- MEX handle lifetime;
- MATLAB `D x NP` / optimizer `NP x D` shape conventions;
- CLI flag behavior, especially `--overwrite`, `--seed-policy`, `--rand-generator`;
- comparison thresholds and validation reports.

Phase E - Scripts and configs:

- PowerShell comments should describe prerequisites and side effects.
- Build instructions should be single-line commands where docs promise that.
- YAML comments should match `configs/README.md` and the C++ loader.
- Do not leave comments that refer to old folder names, old reference-code
  folders, `cec_benchmarks`, `reference_gsk_code`, stale build folders, or old
  prompt locations.

Phase F - Tests:

Test comments should name the invariant being protected:

- reproducibility;
- seed schedule;
- CEC/MEX ground truth;
- resume vs overwrite;
- optional graph rendering;
- optimizer smoke behavior.

Avoid comments that repeat assertions.

===============================================================================
5. STYLE GUIDE
===============================================================================

Good inline comment:

  % Restore the post-X0 RNG state so the first algorithmic random decision is
  % comparable across optimizers in unified mode.

Bad inline comment:

  % Set rng.

Good C++ comment:

  // Keep the help text aligned with MATLAB overwrite semantics: the old result
  // tree is archived before a clean run, not deleted in place.

Bad C++ comment:

  // Do overwrite stuff.

===============================================================================
6. FINAL REPORT
===============================================================================

Return:

1. Files reviewed.
2. Inline documentation defects found, ordered by severity.
3. Comments/help text updated.
4. Stale comments removed.
5. Behavior intentionally not changed.
6. Commands run and results.
7. Remaining inline documentation gaps.
```
