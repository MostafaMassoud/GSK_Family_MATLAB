# Full Project Review Prompt

> **What this page is.** A paste-ready whole-project review prompt for the
> hybrid MATLAB + C++ `gsk_family` project. **For.** Maintainers, reviewers, and
> capable coding agents performing a production-grade audit. **Prerequisites.**
> The reviewer has read `README.md`, `SKILL.md`, and the reference docs listed
> below. **After using it** the reviewer should produce severity-ranked findings,
> narrowly scoped fixes, verification evidence, and remaining risks.

This prompt is the MATLAB/C++ counterpart of the sibling project's
`REVIEW_PROMPT.md`, adapted to this repository's current implementation. Use it
for an end-to-end pass across source code, C++ tooling, MATLAB runners,
benchmarks, configs, tests, documentation, build files, and generated-artifact
policy.

Related prompts in this folder:

- [DOCS_DEEP_REVIEW_PROMPT.md](DOCS_DEEP_REVIEW_PROMPT.md) - deep documentation
  pedagogy, examples, and diagrams.
- [documentation_review_prompt.md](documentation_review_prompt.md) -
  documentation consistency and stale-reference gate.
- [INLINE_DOCUMENTATION_REVIEW_PROMPT.md](INLINE_DOCUMENTATION_REVIEW_PROMPT.md)
  - MATLAB comments, help text, C++ Doxygen, script comments, and config notes.
- [documentation_parity_prompt.md](documentation_parity_prompt.md) - keep this
  documentation set structurally aligned with the sibling project while
  preserving MATLAB/C++ facts.
- [llm_review_prompt.md](llm_review_prompt.md) - legacy-compatible broad review
  prompt retained for existing links.

---

```text
You are a coordinated review team of senior experts auditing the hybrid MATLAB
+ C++ GSK Family research-software project. Treat the repository as production
scientific software: runnable, reproducible, benchmark-valid, documented,
maintainable, performant, and traceable to imported reference evidence.

Project root for this prompt:

  <workspace>\gsk_family

The human-friendly MATLAB launchers live one level above that folder:

  <workspace>\run_all_cec2011.m
  <workspace>\run_all_cec2013.m
  <workspace>\run_all_cec2013lsgo.m
  <workspace>\run_all_cec2017.m
  <workspace>\run_all_cec2020.m

Work directly in the project. Preserve user changes. Do not create a separate
mirror workspace. Do not delete existing result evidence. Do not change core
optimizer mathematics, seed behavior, evaluation-budget accounting, benchmark
semantics, result schemas, or reference-compatibility rules unless a verified
bug exists and the change is explicitly justified.

===============================================================================
0. READ FIRST
===============================================================================

Before editing anything, read:

1. README.md
2. SKILL.md
3. LICENSES.md
4. CHANGELOG.md
5. docs/index.md
6. docs/reference/project_structure.md
7. docs/reference/architecture.md
8. docs/reference/module_dependencies.md
9. docs/reference/workflows.md
10. docs/reference/matlab_interface.md
11. docs/reference/api.md
12. docs/reference/seed_policy.md
13. docs/reference/benchmark_protocol.md
14. docs/reference/benchmark_mapping.md
15. docs/reference/result_schema.md
16. docs/reference/reference_inventory.md
17. docs/reference/porting_notes.md
18. docs/reference/glossary.md
19. docs/research/reproducibility.md
20. docs/research/validation_report.md
21. docs/research/performance.md
22. configs/README.md
23. scripts/README.md
24. scripts/build_docs.ps1
25. scripts/build_mex_bridge.ps1
26. src/README.md and the README files under src/ subfolders, if present.

Use `rg` / `rg --files` for inventory and search. When docs and code disagree,
the committed code is ground truth for behavior unless you can prove a code bug.
If code is correct and docs are stale, fix docs. If code is wrong, report the
bug clearly and keep the behavioral patch narrow.

===============================================================================
1. CURRENT REPOSITORY CONTRACT
===============================================================================

Source ownership:

- MATLAB optimizers, shared operators, runners, helpers, and smoke tests live
  under `src/`.
- C++20 benchmark ports, C++ helper library, CLIs, validation logic, and the
  `gskcec_eval` MEX bridge source live under
  `benchmarks/cec_suite_cpp/cec_tools/`.
- CEC input data lives under `benchmarks/cec_suite_cpp/<suite>/`.
- Imported reference results and curated reference-side curves/logs live under
  `benchmarks/cec_reference_results/` and are read-only evidence.
- Strict flat YAML experiment configs live under `configs/`.
- PowerShell and MATLAB helper scripts live under `scripts/`.
- Markdown docs live under `docs/`; generated HTML lives under `docs/html/`.
- Build outputs live under `build/` and related build folders.
- Generated experiment outputs live under `results/`.

Root-file policy:

- Keep `README.md`, `SKILL.md`, `LICENSES.md`, `CHANGELOG.md`, `CITATION.cff`,
  `codemeta.json`, `CMakeLists.txt`, `.clang-format`, `.clang-tidy`, and
  `.gitignore` unless the user explicitly asks otherwise.
- Do not reintroduce a separate `LICENSE` file; `LICENSES.md` is the license and
  provenance record.
- Do not reintroduce retired root prompt files. Prompts belong in
  `docs/prompts/`.

Toolchain policy:

- The project is MATLAB and C++ only (no other languages or generated
  bindings). The supported toolchain is MATLAB, C++20, CMake, MinGW Makefiles
  on Windows, PowerShell, Pandoc, and Doxygen.
- Documentation is built by `scripts/build_docs.ps1`; do not hand-edit
  `docs/html/`.
- CEC/MEX code is built through CMake and `scripts/build_mex_bridge.ps1`.

===============================================================================
2. SUPPORTED ALGORITHMS AND SUITES
===============================================================================

Review exactly these seven optimizer IDs and entry points:

- `gsk` -> `src/optimizers/gsk/gsk_optimize.m`
- `agsk` -> `src/optimizers/agsk/agsk_optimize.m`
- `apgsk` -> `src/optimizers/apgsk/apgsk_optimize.m`
- `fdb-agsk` -> `src/optimizers/fdb-agsk/fdb_agsk_optimize.m`
- `atmals-gsk` -> `src/optimizers/atmals-gsk/atmals_gsk_optimize.m`
- `egsk` -> `src/optimizers/egsk/egsk_optimize.m`
- `dt-gsk` -> `src/optimizers/dt-gsk/dt_gsk_optimize.m` (plus
  `dt_gsk_config.m` and `dt_gsk_graph.m`; behavior and validation are
  summarized in `src/optimizers/dt-gsk/README.md`)

Use hyphenated IDs in user-facing optimizer slugs and result folders. Use
underscore names only where MATLAB function/file names require them.

Review these benchmark suites:

- `cec2011`: 22 native-dimension real-world problems, 150000 NFEs, raw
  objective statistics.
- `cec2013`: 28 functions, standard dimensions, budget `10000*D`.
- `cec2013lsgo`: 15 large-scale functions, native dimensions, 3000000 NFEs.
- `cec2017`: 30 implemented functions, dimensions 10/30/50/100, budget
  `10000*D`, optimum `100*function`. F2 is implemented but excluded from
  default comparisons and aggregate publication-style runs.
- `cec2020`: 10 functions, dimensions 5/10/15/20, budgets 50000/1000000/
  3000000/10000000.
- `sphere`: internal runner/test suite only.

Keep `cec2013` and `cec2013lsgo` separate. Do not merge their function counts,
dimensions, data paths, budgets, or reference tables.

===============================================================================
3. REPRODUCIBILITY CONTRACT
===============================================================================

Seed policies:

- `run_experiment.m` and root `run_all_cec*.m` launchers default to
  `seed_policy='unified'` and `rand_generator='threefry'`.
- `gsk_run`, shipped YAML configs, and `scripts/run_all.ps1` default to
  `seed_policy='reference'` with requested `rand_generator='threefry'`.
- `base_seed` default is `20240620`, centralized in `run_experiment.m`.
- `unified` seed formula:

  seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1

  It is optimizer-independent. In unified mode the runner generates the initial
  population once, passes `X0` to every optimizer, and restores the post-X0 RNG
  state before the first algorithmic random draw. Documented exception: DT-GSK
  samples its own NP = 5*D population from named Threefry substreams, so the
  runner draws no `X0` for it.

- `reference` formulas:
  - `gsk`, `egsk`, `atmals-gsk`: `base_seed + 9973*func + run - 1`
  - `agsk`, `apgsk`, `fdb-agsk`: `D*func*run`
  - `dt-gsk` is unified-only (`is_unified_only` in `run_experiment.m`): it is
    scheduled with the unified seed and `threefry` under every `seed_policy`,
    mirroring the reference implementation's `UNIFIED_ONLY_OPTIMIZERS`.
- Under reference mode, AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK use legacy `seed`;
  GSK uses `twister`. Under unified mode the effective generator is
  threefry when available, otherwise twister.
- `native` and `derived` go through the diagnostic derived-seed path and must not
  be described as fair cross-family schedules.

Result/output policy:

- Root `run_all_cec*.m` launchers write under
  `gsk_family/results/_run_all/<optimizer>/<suite>/`.
- `gsk_run` writes under `gsk_family/results/<optimizer>/<suite>/` unless the
  user passes an output override.
- `overwrite=false` resumes/appends inside an existing result tree.
- `overwrite=true` archives the previous active result tree under
  `_overwrite_archive/<suite>_<timestamp>/` beside that suite folder, then starts
  a clean replacement run.
- `write_graphs=false` is the default. Numeric `curves/*.csv` and
  `gen_logs/*.csv` remain enabled; PNG graph rendering under `curves/graphs/` is
  opt-in.
- Generated output must never be written into `benchmarks/cec_reference_results`.

Reporting quirks:

- On known-optimum suites, report `best_fitness - optimum` with the 1e-8 zero
  cutoff.
- ATMALS-GSK on CEC2017 intentionally reports `abs(best_fitness - optimum)`.
- Do not remove CEC2017 F2 support, but do not re-add F2 to default comparisons.

===============================================================================
4. REVIEW TEAM ROLES
===============================================================================

Apply these lenses:

1. MATLAB scientific-computing architect
2. C++20/CMake/MEX engineer
3. Numerical optimization and metaheuristics expert
4. CEC benchmark integration expert
5. Reproducibility and deterministic-computation reviewer
6. Performance and parallelization engineer
7. Test strategy and QA engineer
8. Documentation and developer-experience reviewer
9. Security/path-safety/generated-artifact reviewer
10. Research workflow and publication-readiness reviewer

===============================================================================
5. REVIEW PHASES
===============================================================================

Phase 0 - Baseline inventory, read-only:

- Record `git status --short`.
- Inventory root files, `src/`, `benchmarks/`, `configs/`, `scripts/`, `docs/`,
  build folders, and result folders.
- Identify generated paths and protected evidence paths.
- Do not edit in this phase.

Phase 1 - Build and benchmark integration:

- Check CMake configuration, `build/` policy, C++ CLIs, MEX bridge source, and
  PowerShell build scripts.
- Verify documented build commands match current paths:
  `benchmarks/cec_suite_cpp`, `benchmarks/cec_suite_cpp/cec_tools`,
  `build/mex/gskcec_eval.mexw64`.
- Check C++ CLI help text, YAML config parsing, reference-table validation, and
  MEX bridge path discovery.

Phase 2 - MATLAB runner and experiment protocol:

- Inspect `run_experiment.m`, `get_cec_seed.m`, `derive_run_seed.m`,
  `gskcec_make_problem.m`, `verify_unified_seed_schedule.m`, and the root
  `run_all_cec*.m` launchers.
- Verify seed formulas, generator selection, fair-start `X0`, F2 exclusion,
  overwrite archive behavior, `write_graphs` behavior, resume/add behavior,
  summary table formatting, and result schemas.
- Confirm CEC2011 native dimensions, CEC2013/CEC2013LSGO separation, CEC2020
  budget ladder, and target/error handling.

Phase 3 - Optimizer implementation review:

- Inspect all seven optimizer entry points and shared operators.
- Confirm evaluation-budget accounting, stopping criteria, boundary handling,
  donor/index selection, local search, fmincon guard in eGSK, ATMALS local
  search behavior, APGSK/AGSK adaptation, FDB logic, DT-GSK dimension tiers
  and Threefry substreams, and output structs.
- Classify differences from reference code as intentional policy, harmless
  refactor, documentation mismatch, likely bug, or requires-user-approval.

Phase 4 - Performance and scalability:

- Look for vectorization, repeated computation, memory allocation, RNG overhead,
  CEC call overhead, population update inefficiency, logging/I/O overhead,
  graph-rendering overhead, and parfor setup overhead.
- Apply only behavior-preserving optimizations. Preserve RNG draw order and
  evaluation counts.

Phase 5 - Documentation and prompts:

- Check README, RUNBOOK (the beginner runbook), SKILL, configs README, scripts
  README, every docs page, every prompt page, and generated HTML freshness.
- Update source Markdown first, rebuild HTML with `scripts/build_docs.ps1`, and
  never hand-edit `docs/html/`.
- Ensure all command examples reflect current overwrite, write_graphs, seed,
  output, CEC, and build behavior.

Phase 6 - Tests and validation:

Run the strongest feasible verification commands. At minimum consider:

  cmake --build build -j
  ctest --test-dir build --output-on-failure
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_mex_bridge.ps1
  matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
  build\gsk_list.exe --benchmarks
  build\gsk_list.exe --optimizers
  build\gsk_validate.exe --references benchmarks\cec_reference_results
  build\gsk_validate.exe --suite cec2017 --smoke --root .

If a full command is too expensive, run a reduced command and state exactly what
remains unverified.

===============================================================================
6. FINDINGS AND FINAL REPORT FORMAT
===============================================================================

Start with findings, ordered by severity:

- Critical: incorrect scientific results, corrupted reference evidence,
  nondeterminism where determinism is promised, destructive path handling, or
  false publication/reproduction claim.
- High: wrong seed/default/output/budget behavior, broken benchmark integration,
  broken launcher, stale docs that mislead experiments, or performance change
  that changes algorithm behavior.
- Medium: missing tests, stale but nonblocking docs, inefficient but correct
  runtime path, weak workflow clarity.
- Low: wording, organization, duplication, minor polish.

For each finding include:

  severity | file:line | issue | evidence | fix or recommendation | verification

Then list:

1. Changes made.
2. Stale files/folders removed or rewritten.
3. Behavior intentionally preserved.
4. Performance opportunities found/applied.
5. Verification commands and results.
6. Remaining risks/open questions.
7. Confirmation that source docs, generated docs, configs, and inline comments
   match current code.
```
