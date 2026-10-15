# LLM Review Prompt

Use this prompt when asking an LLM agent to perform a full-repository review,
cleanup, validation, and performance-tuning pass on the current `gsk_family`
project. It is aligned with the repository state after the docs restructure
(five-folder taxonomy plus `docs/prompts/`), the root cleanup (`SKILL.md` at the
project root, `LICENSES.md` as the single license/provenance record, no retired
root prompt files), and the C++20 CEC tooling under `benchmarks/`. It also
anchors the review to the external extracted reference-code corpus at
`<reference-corpus>`.

For new whole-project reviews, prefer the canonical
[REVIEW_PROMPT.md](REVIEW_PROMPT.md). This file is retained as a legacy-compatible
broad prompt for existing links and prior workflows.

Copy everything inside the single fenced block below into the agent. The block
is intentionally self-contained: it restates the current repository contract,
exact seed formulas, supported algorithms and suites, the verification
thresholds, and the precise validation commands, so the agent does not have to
guess at any project fact.

```text
# Ultimate Expert Review, Cleanup, Validation, and Performance-Tuning Prompt
# Current target: gsk_family MATLAB + C++20 repository

You are working directly in:

<repo>\gsk_family

The root run_all launchers live one level up, in the workspace root:

<repo>\run_all_cec2011.m
<repo>\run_all_cec2013.m
<repo>\run_all_cec2013lsgo.m
<repo>\run_all_cec2017.m
<repo>\run_all_cec2020.m

Act as a multidisciplinary review board with deep expertise in evolutionary
computation, global numerical optimization, the GSK family of algorithms
(Gaining-Sharing Knowledge and its adaptive, parameter-adaptive, fitness-
distance-balance, two-mode-adaptive-local-search, enhanced, and dimension-tiered
variants), CEC
single-objective and large-scale benchmark suites, MATLAB performance
engineering, C++20 performance engineering, scientific computing, reproducible
research, numerical analysis, build systems (CMake + MinGW Makefiles), static
analysis, MEX interfacing, technical documentation, and research software
engineering.

Your mission is to make the repository clean, reproducible, benchmark-valid,
publication-ready, and maintainable WHILE preserving the exact intended
algorithm behavior, seed behavior, evaluation-budget accounting, benchmark
semantics, and reference compatibility. Correctness and reproducibility outrank
elegance, brevity, and speed in every trade-off.

Use the external reference code as evidence for algorithmic intent and porting
differences, but do not treat every textual difference as a required change.
The current project has deliberate protocol decisions that must NOT be
rewritten, especially the current seed/RNG policy, the per-optimizer reference-
seed formulas, the CEC2017 F2 exclusion from default comparisons, and the
ATMALS-GSK absolute-error reporting exception on CEC2017.

## First Read These Files

Before changing anything, read these in order. Treat the docs as the current
project contract unless direct code inspection proves a doc is stale.

1. README.md
2. SKILL.md
3. docs/index.md
4. docs/reference/project_structure.md
5. docs/reference/architecture.md
6. docs/reference/module_dependencies.md
7. docs/reference/benchmark_protocol.md
8. docs/reference/benchmark_mapping.md
9. docs/reference/seed_policy.md
10. docs/reference/result_schema.md
11. docs/reference/matlab_interface.md
12. docs/reference/api.md
13. docs/reference/porting_notes.md
14. docs/reference/reference_inventory.md
15. docs/reference/workflows.md
16. docs/reference/glossary.md
17. docs/research/reproducibility.md
18. docs/research/validation_report.md
19. docs/research/performance.md
20. LICENSES.md
21. configs/README.md
22. scripts/README.md
23. src/README.md and the per-folder READMEs under src/

Use `rg` and `rg --files` for repository searches (ripgrep is the expected
search tool; do not assume a POSIX `grep`/`find` layout). When a doc and the
code disagree, the committed code is ground truth for behavior, and the doc is
the thing to fix.

## Current Repository Contract

The project is intentionally split by responsibility:

- MATLAB GSK-family optimizers, common operators, runners, experiment matrix,
  and smoke tests are under src/.
- C++20 CEC benchmark ports, the benchmark interface and factory, the four
  command-line tools, the experiment/verification logic, and the MEX bridge
  source live under benchmarks/cec_suite_cpp/cec_tools/. The benchmark input data
  and imported reference result tables live under benchmarks/cec_suite_cpp/<suite>/
  and benchmarks/cec_reference_results/<suite>/.
- Experiment configurations are under configs/ and use the documented strict
  flat YAML subset.
- Helper scripts (PowerShell + MATLAB) are under scripts/.
- Documentation is under docs/ in a five-folder taxonomy plus docs/prompts/
  (detailed below).
- Generated build outputs live under build/ (including the compiled MEX bridge
  at build/mex/gskcec_eval.mexw64).
- Generated experiment outputs live under results/.
- Project-local agent instructions live at the root SKILL.md.
- License and provenance are tracked in the root LICENSES.md.

Do not reintroduce retired root prompt files. Keep maintained prompts under
docs/prompts/. Do not reintroduce a separate root LICENSE file; the root
LICENSES.md is the single record. Keep the root clean.

Keep these conventional root files unless there is an explicit user decision to
remove them:

- CMakeLists.txt
- README.md
- SKILL.md
- LICENSES.md
- CHANGELOG.md
- CITATION.cff
- codemeta.json
- .clang-format
- .clang-tidy

The project is MATLAB and C++ only (no other languages or generated bindings).
Do not add scripts, wrappers, generated bindings, notebooks, or package
dependencies in other languages. Tooling is MATLAB, C++20, PowerShell, CMake,
Pandoc, and Doxygen only. (Citing the DT-GSK reference implementation as
provenance is allowed; it is not part of this project.)

## Supported Algorithms

Review exactly these seven MATLAB optimizers (slug -> entry point under
src/optimizers/<slug>/):

- gsk          -> gsk_optimize.m
- agsk         -> agsk_optimize.m
- apgsk        -> apgsk_optimize.m
- atmals-gsk   -> atmals_gsk_optimize.m
- egsk         -> egsk_optimize.m
- fdb-agsk     -> fdb_agsk_optimize.m
- dt-gsk       -> dt_gsk_optimize.m (plus dt_gsk_config.m and dt_gsk_graph.m)

Termination contract (verify it is preserved exactly):

- gsk, atmals-gsk, egsk, fdb-agsk, and dt-gsk run the FULL evaluation budget
  and set result.termination = 'max_evaluations'. The reference implementations
  of these five never stop early.
- Only agsk and apgsk may stop early: they branch to
  result.termination = 'target_error_reached' when the best error reaches the
  target, otherwise 'max_evaluations'.

eGSK toolbox dependency: the reference IP local-refinement stage uses fmincon
(SQP). egsk_optimize.m guards on
license('test','Optimization_Toolbox') && exist('fmincon','file') and, when the
reference IP stage is required but fmincon is unavailable, raises the error id
egsk:fminconUnavailable. Do not silently stub, disable, or replace this stage;
the guard and error id are part of the contract.

Every optimizer must remain faithful to the committed implementation and the
documented provenance (the historical-source comments and
docs/reference/porting_notes.md). If behavior differs from a documented source
contract, document the reason in docs/reference/porting_notes.md rather than
silently inventing a replacement. Per-optimizer detail pages live under
docs/algorithms/<slug>.md; DT-GSK's behavior and validation summary is
src/optimizers/dt-gsk/README.md.

## External Reference Code Corpus

Use this read-only reference corpus for deep comparison:

<reference-corpus>

Reference-code mapping (subfolder -> current optimizer/material):

- gsk        -> gsk
- agsk       -> agsk
- apgsk      -> apgsk
- atmalsgsk  -> atmals-gsk
- egsk       -> egsk
- fdb-agsk   -> fdb-agsk
- benchmarks -> CEC benchmark material

DT-GSK is not in this corpus. Its source is the DT-GSK reference implementation
v2.46 (MIT license, https://github.com/MostafaMassoud/DT-GSK); use it the same
way, as read-only evidence.

Do not edit, move, delete, or normalize files in the external reference corpus.
Do not copy large reference files wholesale into the current project. Use it to
trace behavior, compare implementation details, and explain differences.

For each current-vs-reference difference, classify it as exactly one of:

- intentional current project policy
- seed/RNG policy difference that must not be changed
- per-optimizer reference-seed formula difference that must not be changed
- CEC2017 F2 default-exclusion difference that must not be changed
- ATMALS-GSK CEC2017 absolute-error reporting exception (intentional)
- benchmark adapter/interface difference (port vs original dispatch)
- harmless refactor or performance rewrite
- documentation/provenance mismatch
- likely implementation bug
- risky scientific change requiring explicit user approval

When a difference is seed-related, F2-exclusion-related, or the ATMALS-GSK
absolute-error exception, record it as intentional and do not propose changing
it.

## Supported Benchmark Suites

Review all five supported CEC suites. Each port lives under
benchmarks/cec_suite_cpp/<suite>/ with reference tables under
benchmarks/cec_reference_results/<suite>/.

- cec2017: 30 functions, dims 10/30/50/100, budget 10000*D, optimum value
  100*function_id, search domain [-100,100]^D. F2 is implemented and may be run
  explicitly but is EXCLUDED from default comparisons and aggregate published-
  table reproduction. A 1e-8 zero cutoff applies on this known-optimum suite.
- cec2011: 22 functions, native (per-function fixed) dimensions, budget 150000,
  raw objective values (most functions have no published optimum; optimum()
  returns NaN).
- cec2020: 10 functions, dims 5/10/15/20, budgets 50000 / 1000000 / 3000000 /
  10000000 by dimension (per the AGSK CEC2020 reference protocol).
- cec2013: 28 functions, budget 10000*D.
- cec2013lsgo: 15 functions, fixed large dimensions (~1000-D), budget 3000000.

Keep cec2013 and cec2013lsgo strictly SEPARATE. They are different suites with
different function counts, dimensions, input data, budgets, and reference
tables. Never merge their assumptions or tables.

Error/optimum reporting:

- On known-optimum suites, the reported error is best_fitness - optimum, with a
  1e-8 zero cutoff.
- EXCEPTION: ATMALS-GSK on cec2017 reports abs(best_fitness - optimum). This is
  the only optimizer/suite combination that uses absolute value, and it is
  intentional. (When problem.optimum is NaN under the cec2017 protocol, the
  optimum-based ATMALS signal degrades gracefully because the reference never
  ran cec2017 with unknown optima.)

CEC2017 F2 is implemented and may be run explicitly, but it is excluded from
default CEC2017 comparisons and aggregate published-table reproduction. Do not
remove this exclusion and do not re-add F2 to default runs.

## Non-Negotiable Preservation Rules

Do not change core mathematical behavior unless a bug is PROVEN from the
committed implementation or from a documented benchmark contract.

Do not alter, unless explicitly proven necessary and documented in
docs/reference/porting_notes.md:

- gained/shared junior and senior knowledge operators
  (Gained_Shared_Junior_R1R2R3, Gained_Shared_Senior_R1R2R3, and the
  optimizer-local variants)
- donor and R1/R2/R3 index selection
- archive logic
- local-search and restart triggers (including the ATMALS two-mode local search
  and the eGSK IP refinement)
- population evolution logic
- population-size policy (including any linear reduction / survivor selection)
- parameter schedules (KF/KR, junior/senior partition, p-best fraction,
  parameter-adaptation pools, FDB weighting)
- boundary handling (gsk_bound_repair and optimizer-local bound constraints)
- benchmark optimum/error calculation (including the ATMALS-GSK cec2017
  absolute-error exception and the 1e-8 cutoff)
- evaluation-budget accounting and number-of-function-evaluations counting
- stopping criteria and the per-optimizer termination strings
- published experimental methodology
- default seed policy and the per-optimizer reference-seed formulas
- random-number generator family selection per policy
- CEC2017 default F2 exclusion

All performance optimizations must preserve:

- algorithm behavior (bit-for-bit where the reference is bit-reproducible)
- reference compatibility
- deterministic reproducibility
- benchmark validity
- evaluation-budget accounting
- output schema compatibility (result struct and on-disk result files)

Classify any proposed behavior-changing fix as a scientific change. Do not mix
it with pure cleanup or performance work. Never "fix" the seed policy, the
per-optimizer reference-seed formulas, the CEC2017 F2 exclusion, or the
ATMALS-GSK absolute-error exception during this review. If a reference source
disagrees, report it as an intentional protocol difference rather than applying
a change.

## Current Seed Policy

Verify and preserve the seed policies implemented by
src/runners/run_experiment.m and documented in docs/reference/seed_policy.md.
The centralized default base seed is default_base_seed = 20240620 in
run_experiment.m; the root run_all launchers do not expose base_seed and rely on
this default.

There are four accepted seed-policy labels grouped into three behavior families:

1. unified (centralized cross-family policy): same (D, function, run)
   seed for EVERY optimizer, optimizer-independent. Implemented by
   src/runners/get_cec_seed.m using uint64 arithmetic:

       MAX_SAFE_SEED = 2147483646   (= 2^31 - 2)
       seed = mod( base_seed
                   + 1000003 * dim
                   + 1000033 * func
                   + 1000037 * run,
                   MAX_SAFE_SEED ) + 1

   This must be evaluated with uint64 arithmetic and must NOT include optimizer
   name, optimizer index, alg_code, population size, evaluation budget, suite
   name, local-search settings, or any other algorithm-specific value. For the
   same (dim, func, run), every optimizer receives the identical seed.

2. reference: per-optimizer reference-reproduction seeds.

       gsk, egsk, atmals-gsk : seed = base_seed + 9973 * func + (run - 1)
       agsk, apgsk, fdb-agsk : seed = D * func * run

   Run the reference policy to reproduce the published CEC reference tables.
   dt-gsk is unified-only (is_unified_only in run_experiment.m): it gets the
   unified seed and threefry under EVERY policy, because its reference campaign
   was produced that way (the reference implementation's
   UNIFIED_ONLY_OPTIMIZERS).

3. native and derived: both honor the requested generator and use the diagnostic
   optimizer/suite-hashed seed via src/runners/derive_run_seed.m.

RNG generator selection (src/runners/choose_cec_rng_generator.m and the policy
dispatch):

- reference policy: agsk, apgsk, fdb-agsk, egsk, and atmals-gsk use the
  deterministic legacy generator 'seed' (the multiplicative congruential
  mcg16807 stream); gsk uses 'twister'.
- unified policy: prefer the counter-based 'threefry' generator when the
  installed MATLAB supports it, else fall back to 'twister'. The choice must
  depend only on (base_seed, dim, func, run) and must not consult or perturb the
  global RNG state (the helper saves and restores rng around its probe).
- native/derived policy: honor the requested generator.
- dt-gsk: always 'threefry' (options.rand_generator must be threefry;
  empty/auto/default are accepted).

Entry-point defaults (verify these exactly, they differ by caller):

- run_experiment.m default and the root run_all_cec*.m launchers default to
  seed_policy = 'unified' with rand_generator = 'threefry' for fair cross-family
  experiments.
- The gsk_run CLI and the shipped YAML configs and scripts/run_all.ps1 default
  to seed_policy = 'reference' with 'threefry' requested (reference reproduces
  the published tables).

Fair-start initial population (unified policy): the runner draws the NP = 100
initial population ONCE via src/common/gsk_init_population.m, captures the
post-initialization RNG state, and each optimizer restores that state
(src/common/gsk_restore_rng_after_initialization.m) so every optimizer starts
from the identical X0 and the identical downstream RNG stream. DT-GSK is the
documented exception: it derives named Threefry substreams from the run seed,
samples its own NP = 5*D population, and ignores a runner X0 (the runner draws
none for it). Launchers call
src/runners/verify_unified_seed_schedule.m to assert the schedule. Wall-clock /
shuffle-based seeding is forbidden and is not a supported mode.

This seed/RNG split is intentional. Do not simplify it, unify the two reference
formulas, replace it with a time-based seed, or "clean up" the generator
fallback. Report any reference-code disagreement as a controlled protocol
difference unless the user explicitly asks to change seed behavior.

Rerun and graph-output policy:

- overwrite=false resumes/appends inside the active result tree.
- overwrite=true archives the previous active result tree under
  _overwrite_archive/<suite>_<timestamp>/ and starts a clean replacement run.
- write_graphs=false is the default; numeric curves/*.csv and gen_logs/*.csv
  remain enabled, while PNG files under curves/graphs/ are opt-in.

Audit all randomness:

- optimizer entry-point seeding via src/common/gsk_set_rng.m
- initial population sampling (gsk_init_population.m,
  gsk_initial_population_from_options.m) and the post-init state capture/restore
- donor, archive, and R1/R2/R3 index sampling
- mutation/crossover sampling and parameter-pool draws
- random permutations (randperm) and roulette-wheel selection
- local-search, IP-refinement, and restart paths
- runner-level seed scheduling (get_cec_seed, derive_run_seed,
  unified_run_seed)
- result files that record seeds (seed schedule / run metadata)
- parallel-execution hazards (parfor)

Detect hidden RNG state creation, accidental reseeding, inconsistent seed
propagation, platform-dependent randomness, and nondeterministic parallel
execution. Preserve serial execution as the reproducibility baseline unless the
user explicitly asks for parallel experiments; if parfor is used, confirm each
iteration seeds deterministically from (D, func, run) and never from worker
identity or wall-clock.

## Reference Result Investigation

Investigate reproduced-vs-published benchmark discrepancies. Known current
context:

- Under the reference policy, GSK / AGSK / APGSK / FDB-AGSK reproduce the
  published CEC2017 tables closely; ATMALS-GSK and eGSK reference fidelity
  depends on their toolbox-dependent stages and historical clock-seeded origins.
- DT-GSK references for all five suites are imported from its reference
  implementation (benchmarks/cec_reference_results/<suite>/dt-gsk/; per-run
  evidence and PROVENANCE.md under cec2017/dt-gsk/). Its validation and CEC2017
  campaign results are recorded in src/optimizers/dt-gsk/README.md;
  scripts/compare_reference_runs.m compares two per_run.csv sets per
  (dimension, function) cell (Wilcoxon rank-sum with Holm-adjusted p-values;
  needs the Statistics and Machine Learning Toolbox).
- Any GSK-family variant may deviate and require detailed root-cause analysis.

For each discrepancy, inspect:

- seed formula and RNG stream (per the policy in force)
- initialization range, population size (NP = 100; DT-GSK self-initializes
  NP = 5*D), and the shared-X0 contract
- sorting/ranking behavior and any partial-sort substitution
- parameter schedule and adaptation pools
- boundary repair
- archive update
- fitness-distance-balance selection (fdb-agsk)
- local-search / IP-refinement availability and fallback behavior
- benchmark function dispatch via the C++ port vs the original
- optimum/error calculation (including the ATMALS-GSK abs exception and the
  1e-8 cutoff)
- NFE counting and stopping criteria
- reference-table mapping (docs/reference/benchmark_mapping.md)
- skipped / unavailable cells (e.g. F2 in default cec2017, toolbox-gated eGSK)
- MATLAB version / toolbox differences

Explicitly EXCLUDE the following from the fix list unless the user requests a
policy change (you may cite them as context, but do not recommend changing them
and do not modify code/docs to remove them):

- the unified and reference seed formulas
- the effective per-policy RNG families
- the CEC2017 default exclusion of F2
- the ATMALS-GSK CEC2017 absolute-error exception

For each finding, report: optimizer; suite/function/dimension/run if applicable;
observed behavior; expected/reference behavior; likely root cause; evidence
(file:line); severity (P0-P3); fix recommendation; validation command or
experiment.

## Repository-Wide Cleanup

Review every tracked file and every relevant untracked project file, but do not
delete blindly. Classify each questionable file as:

- keep: active, source-of-truth, or conventional metadata
- update: useful but stale
- move: useful but in the wrong folder
- remove: generated, obsolete, duplicate, or misleading
- ask: ambiguous or risky to remove

Generated folders (build/, results/, docs/html/) are not source of truth. They
may be cleaned when safe, but do not kill MATLAB or user processes to unlock
result files. If a file is locked by an active experiment, leave it and report
it.

Look for:

- stale documentation, especially references to the OLD flat docs/*.md layout
  (those paths are gone; see the new taxonomy below)
- references to retired root prompt files
- references to a separate root LICENSE file
- obsolete scripts and duplicate helpers
- dead code and abandoned experiments
- generated artifacts committed by mistake
- misleading comments and stale historical-source notes
- stale result files
- outdated configuration keys
- old run scripts that disagree with run_experiment.m

Every remaining file should have a clear purpose consistent with
docs/reference/project_structure.md.

## Architecture Review

Evaluate:

- the clean separation between the C++ benchmark layer
  (benchmarks/cec_suite_cpp/cec_tools/) and the MATLAB optimizer layer (src/), and
  whether the MEX bridge is the only coupling point
- MEX bridge ownership and lifecycle (build/mex/gskcec_eval.mexw64, the
  'new'/'eval'/'info'/'free'/'clear' handle protocol, and the D x NP column-
  major contract)
- runner/optimizer interface boundaries (the problem struct produced by
  src/runners/gskcec_make_problem.m and consumed by every optimizer)
- config loading and validation (the strict flat YAML subset; src/experiments
  matrix expansion)
- result schema generation vs docs/reference/result_schema.md
- verification against reference tables (the C++ comparison logic)
- documentation organization vs the taxonomy and the build_docs nav
- root cleanliness
- duplication across the seven optimizers and the runner stack; consult
  docs/reference/module_dependencies.md and docs/reference/workflows.md

Recommend simplifications only when they preserve algorithm compatibility.
Prefer local project patterns over new abstractions.

## MATLAB Optimizer Deep Review

Perform a line-by-line MATLAB review of:

- src/common (Gained_Shared_Junior_R1R2R3, Gained_Shared_Senior_R1R2R3,
  gsk_bound_repair, gsk_init_population, gsk_initial_population_from_options,
  gsk_reduction_survivors, gsk_restore_rng_after_initialization, gsk_set_rng)
- src/optimizers/<slug> for all seven optimizers
- src/runners (run_experiment, get_cec_seed, derive_run_seed, unified_run_seed,
  choose_cec_rng_generator, gskcec_make_problem, gskcec_require_mex,
  verify_unified_seed_schedule)
- src/experiments (default_experiment_matrix)
- src/tests (run_matlab_smoke_tests and the per-optimizer / helper tests)
- MATLAB scripts under scripts/ (analyze_results.m, compare_reference_runs.m)

Generic checks:

- input parsing and defaults; options propagation; the problem struct contract
  (fields lb/ub/dimension/optimum/evaluate and the suite/function identity)
- seed propagation and the post-init state restore
- NFE accounting (every objective call counted exactly once; budget never
  exceeded; vectorized batch evaluation counted as NP)
- boundary handling
- result struct contract (best, error, convergence curve, termination,
  metadata) vs the result schema
- logging and output writing
- missing preallocation; repeated allocation inside generation loops
- repeated objective calls; repeated full sorting; unnecessary dynamic dispatch
- excessive file I/O; parallel-execution risks

Per-optimizer deep checks and preserved quirks (verify each is intact):

- gsk: junior/senior partition schedule, KF/KR settings, full-budget run, basic
  gained/shared operators; termination 'max_evaluations'.
- agsk: parameter-adaptation pools and probability updates, linear population
  reduction / survivor selection if present, EARLY-STOP branch to
  'target_error_reached' on target error.
- apgsk: parameter-adaptive pools (its own adaptation), the EARLY-STOP branch to
  'target_error_reached'.
- atmals-gsk: the two-mode protocol selector (options.protocol 'cec2017'
  default vs 'cec2011'), G_Max = fix(max_nfes/np), the Mean_Fit signal over the
  best half of abs(fitness - optimum) on cec2017, roulette-wheel selection, the
  cec2017-local junior/senior partition, local-search out-of-bound handling, and
  the CEC2017 absolute-error reporting; termination 'max_evaluations'.
- egsk: the enhanced operators plus the IP local-refinement stage
  (egsk_ip_refine, fmincon SQP, budget ceil(0.002*max_nfes)), the
  Optimization_Toolbox guard and egsk:fminconUnavailable error id, the
  egsk:options error when options.seed is missing; termination
  'max_evaluations'.
- fdb-agsk: the fitness-distance-balance donor/index selection layered on the
  AGSK adaptation; termination 'max_evaluations'.
- dt-gsk: the pub profile by dimension tier (dt_gsk_config.m: D < 20,
  20 <= D < 50, D >= 50 with the interaction graph of dt_gsk_graph.m,
  D >= 100), NP = 5*D with nonlinear population reduction, named Threefry
  substreams derived from options.seed (the global RNG is never touched), a
  runner X0 ignored by design; termination 'max_evaluations'. Its parity with
  the reference implementation is summarized in src/optimizers/dt-gsk/README.md.

Performance opportunities to identify (propose, gate on risk):

- vectorization that preserves random-call ORDER and COUNT only when provably
  safe
- preallocation and reusable buffers
- removal of repeated constant computations and repeated path setup in inner
  loops
- fewer wrapper calls around objective evaluation; prefer one batched MEX
  'eval' over per-candidate calls when the random stream is unaffected
- efficient randperm / sampling patterns
- avoiding a full sort when only a minimum, a top-k, or a partial order is needed
  (only if it does not change which individuals are selected)
- minimizing string/table/file writes inside hot loops

Never apply a vectorization that changes the sequence or count of random draws
unless the user explicitly accepts a non-reference trajectory.

## C++/CEC Deep Review

Review:

- CMakeLists.txt (targets, C++20 standard, static linking, MinGW Makefiles
  generator, warning flags, the GSKCEC_NATIVE option, and the MEX-bridge build
  wiring)
- benchmarks/cec_suite_cpp/cec_tools/include/gskcec (the benchmark interface in
  benchmark/benchmark.hpp with the pure-virtual dimension()/bounds()/optimum()/
  evaluate(span<const Real>); the per-suite headers cec2011/cec2013/
  cec2013lsgo/cec2017/cec2020.hpp; the factory.hpp make_problem and the
  per-suite supported_dimensions()/native_dimension(); the experiment headers
  comparison.hpp/config.hpp/result.hpp)
- benchmarks/cec_suite_cpp/cec_tools/src/benchmark (data_loading.cpp, factory.cpp,
  reference_results.cpp -- the five CEC ports and the make_problem factory plus
  reference-table loading)
- benchmarks/cec_suite_cpp/cec_tools/src/experiment (comparison.cpp, config.cpp --
  the verification verdict and config parsing)
- benchmarks/cec_suite_cpp/cec_tools/src/cli (gsk_list.cpp, gsk_validate.cpp,
  gsk_run.cpp, gsk_bench.cpp)
- benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/gskcec_eval_mex.cpp
- benchmarks/cec_suite_cpp/cec_tools/tests/unit (the eleven unit-test translation
  units), tests/cli (gsk_run_exit_codes.cmake and the fake_matlab.cpp stub), and
  tests/data (the fixed-vector ground-truth points and expected CSVs)

Check:

- C++20 portability and warning cleanliness under MinGW GCC
- numerical equivalence of every port to its reference: the ports are validated
  against fixed-vector ground truth (saved candidate points and expected
  objective values). Expected tolerances are approximately 1e-10 for cec2017 and
  1e-12 for the cec2013 saved-vector regression; do not loosen them
- allocation patterns and per-evaluation overhead (no per-call heap thrash in
  evaluate())
- input-data loading (shift/rotation/shuffle data, bounds files) and that the
  data_root resolution is correct
- function dispatch overhead and the make_problem factory dimension handling
  (pass dimension 0 to use the native dimension for the per-function fixed-dim
  suites cec2011 and cec2013lsgo)
- the MEX bridge: the 'eval' command takes X as a D x NP double matrix (one
  candidate per column, column-major) and returns a 1 x NP fitness row; verify
  the row-count check against problem.dimension(), the handle table, and that
  'clear' drops every live handle without leaks
- reference-result loading (reference_results.cpp) and table mapping
- CLI error handling, usage messages, and exit codes for the four tools
- test coverage across the thirteen ctest suites (named below)
- GSKCEC_NATIVE behavior and floating-point safety

The thirteen registered ctest suites are:

    gskcec_core_tests
    gskcec_reference_results_tests
    gskcec_experiment_tests
    gskcec_cec2011_tests
    gskcec_cec2011_wpa_tests
    gskcec_cec2011_wpb_tests
    gskcec_cec2011_wpc_tests
    gskcec_cec2013_tests
    gskcec_cec2013lsgo_tests
    gskcec_cec2017_tests
    gskcec_cec2020_tests
    gskcec_bench_smoke
    gskcec_cli_exit_codes   (gsk_run / gsk_validate / gsk_bench exit codes and
                             flag parsing, with stub MATLAB executables)

Do not enable fast-math or any floating-point mode that can change benchmark
values. Preserve the exactness tolerances documented in the tests.

## Verification-Logic Review

Review the C++ comparison/verification path
(benchmarks/cec_suite_cpp/cec_tools/src/experiment/comparison.cpp and
include/gskcec/experiment/comparison.hpp). Verify the verdict is computed
exactly as currently implemented:

- the overall verdict is "CONSISTENT" when hard_failures == 0, otherwise
  "DEVIATES"
- hard-failure thresholds (defaults): negative_error_floor = -1e-6 (a known-
  optimum best below this floor is a hard failure); gross_factor = 1e6 (the
  generated mean exceeding gross_factor times the absolute reference mean is a
  hard failure, but only when the reference mean magnitude exceeds
  reference_trivial_floor); reference_trivial_floor = 1e-8 (references at or
  below this magnitude are treated as trivially small and not used as a gross
  baseline)
- the reduced_budget flag suppresses the gross-deviation hard failure: a run is
  reduced_budget when the budget was overridden (non-reference) OR fewer than 25
  runs were used. Reduced-budget runs must not be reported as DEVIATES purely on
  the gross-factor check
- the JSON-like report emits verdict, hard_failures, reduced_budget, and the
  thresholds block

Do not weaken, invert, or silently retune these thresholds. If you believe a
threshold is wrong, report it as a scientific change with evidence; do not apply
it.

## Runners and Launchers Review

Review:

- src/runners/run_experiment.m (the centralized runner: default base_seed
  20240620, default seed_policy 'unified' + 'threefry', the unified X0 draw and
  post-init state restore, the reference-stale result filtering on seed-policy
  change, NFE/result-schema emission)
- src/runners/get_cec_seed.m (the unified uint64 formula)
- src/runners/derive_run_seed.m and unified_run_seed.m (the native/diagnostic
  hashed seeds)
- src/runners/choose_cec_rng_generator.m (threefry-or-twister, state-preserving
  probe)
- src/runners/verify_unified_seed_schedule.m (the schedule assertion called by
  launchers)
- src/runners/gskcec_make_problem.m and gskcec_require_mex.m (problem struct
  construction and MEX availability gating)
- the five root launchers run_all_cec2011.m / run_all_cec2013.m /
  run_all_cec2013lsgo.m / run_all_cec2017.m / run_all_cec2020.m (one per suite;
  they default to unified + threefry, do not expose base_seed, and call the
  schedule verifier)
- scripts/run_all.ps1 (defaults to reference + threefry)
- the C++ gsk_run CLI
- all configs under configs/ (smoke.yml, agsk_cec2020.yml, all_cec2011.yml,
  all_cec2017.yml)

Verify:

- defaults match docs/reference/seed_policy.md AND match per-entry-point
  expectations (unified for run_experiment/run_all_cec*.m; reference for
  gsk_run / YAML / run_all.ps1)
- output directories match docs/reference/result_schema.md; full benchmark
  matrices never overwrite imported reference tables under
  benchmarks/cec_reference_results/
- dry-run behavior is accurate
- config keys are documented and parsed by the strict flat YAML subset
- parallel handling is honest and reproducible (deterministic per-cell seeding)
- failures are visible and non-silent
- verification results are written and interpreted with the correct
  CONSISTENT/DEVIATES verdict and thresholds

Remove duplication or stale launcher documentation where safe.

## Scientific Computing Audit

Verify:

- NFE counting and the max-NFE default per suite/dimension (cec2017 10000*D;
  cec2011 150000; cec2020 50000/1e6/3e6/1e7 by dim; cec2013 10000*D;
  cec2013lsgo 3000000)
- error = best_fitness - optimum on known-optimum suites, the 1e-8 zero cutoff,
  and the ATMALS-GSK cec2017 abs() exception
- benchmark objective orientation (minimization; cec2011 raw objective with NaN
  optimum)
- skipped cells (default-excluded cec2017 F2; toolbox-gated eGSK; any
  unsupported function/dimension)
- summary statistics: best, median, mean, worst, standard deviation
- median-run convergence-curve selection
- reference-table comparison tolerances and the CONSISTENT/DEVIATES verdict
- run metadata and environment capture
- reproducible reruns from the seed schedule under the reference protocol

If statistical tests are documented but not implemented, state that clearly
instead of implying they are present.

## Documentation Synchronization

The docs are in a FIVE-folder taxonomy plus docs/prompts/, with a root
LICENSES.md. The OLD flat docs/*.md paths are GONE; update any reference that
still points at them. Current layout:

- docs/index.md (landing page)
- docs/getting-started/: explainer.md, tutorial.md, user_guide.md,
  command_reference.md, configuration.md, troubleshooting.md
- docs/reference/: architecture.md, matlab_interface.md, api.md,
  module_dependencies.md, workflows.md, result_schema.md, seed_policy.md,
  benchmark_protocol.md, benchmark_mapping.md, diagrams.md,
  project_structure.md, reference_inventory.md, porting_notes.md,
  cec2011_port_plan.md, glossary.md
- docs/algorithms/: gsk.md, agsk.md, apgsk.md, fdb-agsk.md, atmals-gsk.md,
  egsk.md, dt-gsk.md
- docs/development/: developer_guide.md, contributor_guide.md,
  maintenance_guide.md, extension_guide.md, code_reading_guide.md
- docs/research/: researcher_handbook.md, reproducibility.md, performance.md,
  validation_report.md, numerical_examples.md
- docs/prompts/: REVIEW_PROMPT.md, DOCS_DEEP_REVIEW_PROMPT.md,
  documentation_review_prompt.md, INLINE_DOCUMENTATION_REVIEW_PROMPT.md,
  documentation_parity_prompt.md, llm_review_prompt.md
- root LICENSES.md
- root RUNBOOK.md (the beginner runbook)

Documentation build: docs are built by scripts/build_docs.ps1 (PowerShell +
Pandoc 3.8+ for the Markdown pages, with a built-in fallback renderer when
Pandoc is absent or older than 3.8, + Doxygen for the C++ API). The script emits
folder-prefixed FLAT html filenames (so a page keeps a unique name across
folders) and runs a basename-fallback link rewriter so cross-page Markdown links
resolve to the flat html names. The generated site nav groups pages as Getting
Started / Reference / Algorithm Guides / Development / Prompts / Research / C++
API. Generated html lives under docs/html/ and is not source of truth.

Update docs and inline comments so they match the current implementation.
Prioritize:

- README.md
- RUNBOOK.md (the beginner runbook)
- SKILL.md
- docs/index.md
- docs/reference/project_structure.md
- docs/reference/architecture.md
- docs/reference/module_dependencies.md
- docs/reference/benchmark_protocol.md
- docs/reference/benchmark_mapping.md
- docs/reference/seed_policy.md
- docs/reference/result_schema.md
- docs/reference/matlab_interface.md
- docs/reference/api.md
- docs/reference/porting_notes.md
- docs/research/performance.md
- docs/research/reproducibility.md
- docs/research/validation_report.md
- docs/getting-started/command_reference.md
- docs/getting-started/configuration.md
- docs/algorithms/<slug>.md for all seven optimizers, and
  src/optimizers/dt-gsk/README.md (the DT-GSK validation record)
- configs/README.md
- scripts/README.md
- src/README.md and the per-folder src READMEs

Remove or rewrite stale statements. Do not add decorative prose. Keep docs
specific, current, and verifiable. When you change behavior-adjacent docs, keep
them consistent with docs/prompts/documentation_parity_prompt.md.

## Performance Engineering Report

For every performance opportunity, provide: location (file:line); bottleneck
type; current behavior; proposed optimization; expected speedup; implementation
effort; validation effort; scientific risk; whether random-call order or count
changes; whether benchmark values can change.

Rank by:

1. high speedup, zero behavior risk
2. high speedup, low validation cost
3. low speedup but major cleanup benefit
4. behavior-changing ideas, kept out of production unless approved

Cross-check any optimization against docs/research/performance.md, which
documents how to capture baselines with gsk_bench, so claimed speedups are
grounded.

## Required Validation

Run what is feasible locally and report anything skipped with a reason. Use the
exact commands below (PowerShell-friendly; MinGW Makefiles generator).

Language-contract / hygiene checks (confirm the tree is MATLAB and C++ only, with
no other-language sources, notebooks, or stray generated sources; every file
extension listed should belong to MATLAB, C++, PowerShell, CMake, configs, data,
or docs):

    rg --files . | ForEach-Object { [IO.Path]::GetExtension($_) } | Sort-Object -Unique
    rg --files benchmarks | ForEach-Object { [IO.Path]::GetExtension($_) } | Sort-Object -Unique

C++ build and the thirteen ctest suites:

    cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j
    ctest --test-dir build --output-on-failure

Optional native C++ equivalence check (no fast-math; values must not change):

    cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DGSKCEC_NATIVE=ON
    cmake --build build -j
    ctest --test-dir build --output-on-failure

Rebuild the MEX bridge (produces build/mex/gskcec_eval.mexw64):

    powershell -File scripts\build_mex_bridge.ps1

MATLAB smoke tests (run each optimizer + runner + seed-policy + MEX-bridge test):

    matlab -batch "cd('src/tests'); run_matlab_smoke_tests"

Runner dry run via the CLI:

    build\gsk_run.exe --config configs\smoke.yml --root . --dry-run

Documentation build (Pandoc + Doxygen; -Clean for a fresh tree):

    powershell -File scripts\build_docs.ps1 -Clean

Diff hygiene:

    git diff --check

If MATLAB is currently running experiments and locks result files, do not kill
it. Report the locked files and continue with source/doc checks.

## Deliverables

Produce these sections, in order:

1. Executive summary
2. Current repository contract confirmation
3. Reproducibility and seed audit (unified + reference formulas, generator
   selection per policy, fair-start X0, parallel determinism)
4. Reference-result discrepancy report (per optimizer/suite/function/dim)
5. Cleanup report (keep/update/move/remove/ask per file)
6. Architecture review (C++/MATLAB split, MEX bridge, runner boundaries)
7. MATLAB optimizer code review (all seven, with preserved-quirk confirmation and
   termination-contract check)
8. C++/CEC code review (five ports, interface + factory, thirteen ctest suites,
   fixed-vector tolerances, MEX bridge)
9. Verification-logic review (CONSISTENT/DEVIATES, the three thresholds,
   reduced_budget)
10. Runner / launcher / config review
11. Documentation synchronization report (against the five-folder taxonomy +
    prompts and build_docs.ps1)
12. Performance roadmap
13. Validation results (each command above, with pass/fail or skip reason)
14. Remaining risks and open questions
15. Production readiness assessment

Use P0/P1/P2/P3 severity for findings:

- P0: breaks correctness, reproducibility, or benchmark validity
- P1: likely causes material benchmark deviation or failed experiments
- P2: maintainability/performance issue with moderate impact
- P3: polish, documentation, or low-risk cleanup

Lead with concrete findings and file/line references. Do not stop at high-level
observations. Implement safe, well-scoped fixes when the evidence is strong; for
risky scientific changes (anything touching the preservation list, the seed
formulas, the F2 exclusion, the ATMALS-GSK abs exception, or the verification
thresholds), report the recommendation and validation plan WITHOUT applying it
unless the user explicitly approves.
```
