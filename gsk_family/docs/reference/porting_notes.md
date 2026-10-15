# Porting Notes

> **What this is:** The authoritative implementation record for every port in
> `gsk_family` -- the C++ CEC suites, the MATLAB GSK-family optimizers, the
> toolchain, the ground-truth strategy, and every deliberately preserved
> reference quirk. **For:** maintainers who need to know exactly what was ported,
> how it was validated, and which "bugs" are kept on purpose. **Prerequisites:**
> [project_structure.md](project_structure.md) for the layout; the CEC2011
> dossier is [cec2011_port_plan.md](cec2011_port_plan.md). **After reading:** you
> can change port code without breaking a preserved quirk or a validation gate.

## Source Boundary

The active project is self-contained: committed MATLAB/C++ ports, imported
input data, imported reference-result tables, and the notes in this document
define the maintained behavior. One documented exception: MATLAB's shipped
`ode45.m` family was read to pin
behavioral constants for the CEC2011 P3/P4 port, because the reference
*calls* `ode45` and its exact stepping is part of reference behavior. The
project code is an original implementation of the published Dormand-Prince /
Shampine mathematics, validated against MATLAB ground truth (see CEC2011
below); no MathWorks source was copied. The DT-GSK optimizer was ported from
its reference implementation (MIT license), which was read as the porting
source and run only outside this project for the parity checks; none of its
code is part of the project (see DT-GSK below).

Language contract:

- CEC benchmark implementations inside this project are C++20 (no MATLAB,
  R, MEX or other languages at benchmark runtime).
- GSK-family optimizer implementations are MATLAB under `src/`.
- Implementation code is MATLAB and C++ only (no other languages or generated
  bindings).
- Tooling languages: C++, MATLAB, PowerShell, CMake.

## Toolchain Record

- C++: WinLibs MinGW-w64 GCC 16.1.0 (user-scope winget install
  `BrechtSanders.WinLibs.POSIX.UCRT`), `-std=c++20`; CMake (WinLibs 4.x or
  MATLAB-bundled 3.25 both work) with "MinGW Makefiles"; `-static` link so
  binaries need no compiler DLLs. The MEX bridge built by
  `scripts/build_mex_bridge.ps1` is now also linked `-static` (the MATLAB import
  libraries are passed by full path), so it no longer imports
  `libwinpthread-1.dll` from a posix-thread-model toolchain; its outputs are
  bitwise identical to the previous `-static-libgcc -static-libstdc++` build
  (1323 probe values across all five suites).
- MATLAB: R2025b (`C:\path\to\MATLAB\R2025b`), used for optimizers, runners,
  smoke tests and validation.
- The MATLAB MinGW support package (GCC 8.1) is too old for C++20 and is
  NOT used; the MEX bridge is built with the WinLibs toolchain directly
  (`scripts/build_mex_bridge.ps1`).

## Ground-Truth Strategy

Committed expected-value data under
`benchmarks/cec_suite_cpp/cec_tools/tests/data/` is the regression oracle for the
C++ ports. It includes `points_D<D>.txt`, `cec2017_expected.csv` (600 rows),
`cec2020_expected.csv` (180 rows; the 4 missing combinations are real source
data gaps, see CEC2020), CEC2011 bounds/probes/expected values, and the
CEC2013 self-generated regression baseline. The old external regeneration
archive is not bundled with this project, so regeneration scripts that depend
on a removed local reference folder are intentionally absent.

## CEC2017 (ported)

- Port: `benchmarks/cec_suite_cpp/cec2017/src/cec2017_problem.cpp` (the staged
  `cec17_func.cpp` next to it is the untouched provenance copy, never
  compiled). Public API `gskcec::cec2017::make_problem` in
  `benchmarks/cec_suite_cpp/cec_tools/include/gskcec/benchmark/cec2017.hpp`.
- Validation: all 600 MEX ground-truth rows match at rel-tol 1e-10;
  observed maximum relative deviation 4.8e-15.
- Preserved reference quirks (do not "fix"):
  1. F6 Schaffer-F7 reads the shifted-unrotated `y` buffer, so inside
     hf04/hf10 it consumes the leading entries of the shuffled vector
     rather than its own sub-block.
  2. F8 step-Rastrigin rounding loop is dead code (operates on stale `y`).
  3. F9 Levy: `f(shift) != bias` by construction (`w = 1+(z-1)/4` offset);
     tests assert the analytic quirk value instead.
  4. Data loader branches at `func >= 20`: F20 requests 10 matrices/shift
     rows but the shipped files hold one - the unused garbage reads are
     not replicated; only the consumed prefix is loaded.
  5. Composition shift files are consumed line-wise (first D of each of 10
     rows of width 100); F29/F30 load `10*D` shuffle indices, use 3 rows.
  6. hf03 bi-Rastrigin sign-flips against the full shift vector's leading
     entries and self-aliases `y` - pointer semantics preserved.
  7. Dead reference functions (`sphere_func`, `dif_powers_func`,
     `dixon_price_func`, `asyfunc`, `oszfunc`) are not ported.
- D=2/D=20 reference data exists partially but is outside the supported
  protocol ({10,30,50,100}).

## CEC2020 (ported)

- Port: `benchmarks/cec_suite_cpp/cec2020/src/cec2020_problem.cpp`; API
  `gskcec::cec2020::make_problem`, public ids 1..10 mapping internally to
  `{1,2,3,7,4,16,6,22,24,25}` (data files are named by INTERNAL id).
- `optimum()` returns the AGSK reference vector
  `{100,1100,700,1900,1700,1600,2100,2200,2400,2500}` - NOT `100*id`.
  Budgets per the AGSK protocol: D5 50k, D10 1M, D15 3M, D20 10M.
- Validation: all 180 MEX rows match; max relative deviation 2.8e-16.
- Data-driven availability: public (1,D5), (1,D15), (8,D5), (8,D15) have
  no `shuffle_data_{1|22}_D{5|15}.txt` in the reference data; constructors
  throw `std::runtime_error` naming the file. Never silently skipped.
- Preserved quirks:
  1. F7 (hf05) at D=5 triggers an out-of-bounds read in the MEX
     (zero-width escaffer6 slice wraps to `z[-1]`); modeled with a 0.0
     guard slot, empirically bit-exact against the recorded MEX values.
  2. F4 (internal 7) loads but never applies its shift/rotation
     (`s_flag=r_flag=0`).
  3. hf01/hf05 give the ceil-remainder to the first group, hf06 to the
     last.

## CEC2013 standard suite (converted from the R package)

- Port: `benchmarks/cec_suite_cpp/cec2013/src/cec2013_problem.cpp` (named
  deliberately - a repo check forbids any path ending `cec2013.cpp`, the
  name a generated binding file would have). All R dependencies removed; ids 1..28; dims
  {2,5,10,20,...,100}; bounds [-100,100]; `optimum()` = reference biases.
- Validation layers (no R installed): (1) analytic f1 sphere check;
  (2) optimum-at-shift `|f(o)-bias| <= 1e-6` for ALL 28 functions x 12
  dims (Schwefel-bearing functions show ~1e-10 residuals from the
  reference's truncated constants - documented, not "fixed");
  (3) self-generated regression baseline
  `benchmarks/cec_suite_cpp/cec_tools/tests/data/cec2013_regression.csv` (420 rows,
  marked as NOT external ground truth) guards future refactors at 1e-12;
  also exposed as `gsk_validate --suite cec2013 --against saved_vectors`.
- Preserved quirks: `asyfunc` writes only for positive inputs (stale
  values pass through otherwise); f19 grie_rosen is effectively unrotated
  (reference overwrites the rotation with `y+1`); `dif_powers` exponent
  uses integer division; composition shift rows for D<100 are slices of
  the flattened 10x100 table, not per-line prefixes; dead `x_bound`/`EPS`
  dropped.

## CEC2013LSGO (adapted in place)

- The copied suite sources under `benchmarks/cec_suite_cpp/cec2013lsgo/src/`
  (the C++ test suite of the cec2013lsgo package) were adapted:
  `eval_func.cpp/.h` DELETED (verified binding glue of that package); the
  `demo.cpp`/`demo2.cpp` reference programs
  (never compiled; `demo2` referenced the deleted `eval_func.h`) were removed,
  leaving only the compiled `Benchmarks.cpp`, `F1`-`F15` and the problem
  adapter; classes moved into `namespace gskcec::cec2013lsgo`;
  legacy relative `cdatafiles` lookup replaced by an explicit data dir;
  `exit()`/printf error paths replaced by exceptions; eval-counter/CSV
  milestone harness, RNG/data generators and unused overloads removed;
  loading is eager (constructor) so `make_problem` fails fast.
- Adapter: `cec2013lsgo_problem.cpp` implements
  `gskcec::cec2013lsgo::make_problem(id, data_root)`; native dimension
  1000 (905 for overlapping F13/F14); `optimum() = 0`.
- Fidelity proof: the untouched reference compiled side-by-side agrees
  bit-exactly (17 significant digits) at probe points for all 15
  functions.
- Quirks: F9 bounds are [-100,100] in the code although the tech report
  says [-5,5] - the code wins; F12 Rosenbrock has `f(xopt)=D-1` with the
  optimum at `xopt+1`; F14 has no single point achieving 0 by
  construction.

## CEC2011 (ported from MATLAB)

- Plan/dossier: `docs/reference/cec2011_port_plan.md` (all 22 problems, dispatch
  chains, data, quirks, work packages). Dossier correction: the P2
  Lennard-Jones mid probe yields `Inf - Inf = NaN -> 0` (not bare +Inf).
- Committed text assets: `c_bifunc_data.txt`, `messengerfull_problem.txt`,
  `cassini2_problem.txt` under `benchmarks/cec_suite_cpp/cec2011/input_data/`;
  `matlab.mat` is kept for provenance only: nothing in the project loads it. The committed test data also includes bounds for all 22
  problems and 3 probes per problem in
  `benchmarks/cec_suite_cpp/cec_tools/tests/data/cec2011_bounds.txt`,
  `cec2011_points_F<id>.txt`, `cec2011_expected.csv`.
- Suite-level rules implemented once: the reference NaN->0 fitness rule
  (`Calc_Fitx_2011.m` lines 57-61) is applied as the final step of every
  problem (`cec2011_detail.hpp::apply_reference_nan_rule`); `optimum()` is
  NaN everywhere (no published optima); the 4-decimal rounding applies to
  problems 11-20 only (inside their wrappers, half-away-from-zero).
- Structure: public dispatch `cec2011_problem.cpp`; work packages
  `cec2011_problems_a.cpp` (P1-8,10), `cec2011_problems_b.cpp` (P9,11-20),
  `cec2011_problems_c.cpp` (P21-22).
- `gskcec::Bounds` was relaxed to `lower <= upper` because P12 fixes unit
  10 at Pmin == Pmax == 55 (24 zero-width ranges).
- WP-A (P1-8, P10) results: 151/151 checks; probe agreement at 1e-12 with
  max observed deviation 2.2e-16 (P4); P3 bit-identical. The ode45
  replica reproduces R2025b stepping exactly (initial-step heuristic,
  error controller, final-step stretch, refine=4 dense output); P4's
  objective sums over the refine=4 output rows as in the reference.
  Preserved quirks: P5/P6 Tersoff `rd3^3` law-of-cosines typo; P7
  empty-range entries; P8 slack regularization `B(1,1)=1e7`, +30
  constant, +1000 over-selection penalty, x>0 domain assumption surfaced
  as `std::domain_error`; P10 local low-precision `pi` in the scan/array
  factor, nulls evaluated raw in radians, dead directivity term not
  computed (write-only global in the reference).
- WP-B (P9, P11-20) results: 177/177 checks; ALL probes bit-identical to
  the MATLAB reference (max deviation 0 at gate 1e-12); P18 == P20
  asserted exactly. P9 bounds are PORTED (full define_boundaries case-9
  chain incl. BT table), bitwise-equal to the MATLAB export; the dense
  inverse is Gauss-Jordan with partial pivoting (documented vs MATLAB
  LAPACK `inv`), bit-identical at the probes. Preserved quirks (marked
  [PRESERVE] in code): 4-decimal rounding for 11-20 only; Power_Loss
  rounded in fn_DED_5/fn_ELD_* but NOT fn_DED_10; per-family penalty
  weights (1e5 vs 1e3 ramp; 1e3 vs 1e5 balance); ELD_6 B1 asymmetry
  (+0.2/-0.2); ELD_140 reversed [Pmin Pmax c b a] column order, zero-fill
  splices, and the missing sum() on the lower-bound capacity term
  (scalar broadcast counted 140x); HT family hydro capacity penalty
  added twice with the thermal one computed-but-dropped, valve-point
  commented out, zero power-balance recomputed literally, case 3's
  0.0*POZ making P18 == P20; B-loss matrices stored as raw source values
  scaled by 1e-5 at build to match MATLAB's op sequence. Data tables were
  extracted mechanically from the .m sources during development (the
  transient extraction scripting was removed from the tree) and verified float-by-float by re-parsing the
  .cpp against the .m matrices, then bit-identical probe agreement.
- WP-C (P21-22, Messenger/Cassini MGA-DSM) results: 42/42 checks; f21
  worst probe relative error 1.9e-13, f22 1.7e-13 vs MATLAB ground truth
  (gated at the achieved level, not the 1e-12 base, because the
  Lambert/ephemeris trig chain accumulates a few ulp - documented in the
  test). Bounds bit-equal to the MATLAB export, independently confirming
  the P22 element-9 lower bound = 400 quirk (define_boundaries canonical,
  not getlimit_cassini2's 800). The mga_dsm core was transcribed per the
  dossier line map: pleph_an analytic ephemerides, propagateKEP with the
  DD frame-rotation hack, IC2par/par2IC with hyperbola branches, Izzo
  lambertI (N=0 log-secant, no iteration cap), swingby legs, arrival DV
  per objective type. Preserved quirks: the three coexisting solar
  constants kept in their own scopes (1.32712428e11 main, the unused
  1.327124400180000e11 in pleph_an, 1.327124280000000e11 in conversion);
  the problem struct loaded once at construction (reference reloads the
  .mat per evaluation - perf bug, numerically identical); J = DVtot for
  P21 (orbit insertion) vs DVtot + VINF for P22 (total DV rndv).

## Imported Reference Loader

- `load_reference_file` treats empty cells, `-`, `nan`, `n/a` and `na` as
  missing statistics (`std::nullopt`), never parse errors. The AGSK
  CEC2020 D=5 table reports `N/A` for functions 6-7 (the source paper did
  not evaluate them); with that fix the loader ingested every table then
  imported (recorded at the time as 35 files / 894 rows). Regression covered
  by `reference_results_tests.cpp`.
- Later imports, including the DT-GSK tables of all five suites (30 files /
  297 rows), bring `gsk_list --references` to 165 files / 1411 rows. Only CSV/TXT
  files directly under `cec*/<optimizer>/` are loaded, so nested folders such as
  `curves/`, `gen_logs/`, and `cec2017/dt-gsk/evidence/` are ignored.

## GSK-Family MATLAB Optimizers (implemented under src/)

Interface contract: `docs/reference/matlab_interface.md` (problem struct, options,
result struct, row-wise NPxD populations, deterministic seeding through
`src/common/gsk_set_rng.m` at entry; DT-GSK instead derives its own Threefry
substreams from `options.seed`).

- Baseline GSK (`src/optimizers/gsk/gsk_optimize.m`, from
  `GSK_Enhanced.m` cross-checked with `GSK.m`): `G_Max =
  fix(max_nfes/np)` counted over the full budget; the final generation is
  fully evaluated but only the first `max_nfes - nfes` children update
  counter/best (reference crossing semantics); GSK never stops early on
  the 1e-8 target - end-of-run zeroing only (termination is always
  `max_evaluations`).
- AGSK (`agsk_optimize.m`): KW phase-1 while `nfes < 0.1*max_nfes` with
  per-generation reset to `[0.85 0.05 0.05 0.05]`; junior schedule is
  nfes-ratio based; per-individual K drawn once at init and trimmed on
  reduction; target stop checked per generation (strict <) after resize.
- APGSK (`apgsk_optimize.m`, separate implementation): interface default
  NP = 100 (the CEC2017 competition NP; reproduces the CEC2017 tables). The
  reference release's CEC2020-style NP = 200*D (D>5) else 250 is opt-in via
  `options.np_init`, and a supplied X0 must then have at least that many rows.
  KR always pooled; one scalar `rand` consumed every adaptive
  generation - positive `KF_pool` iff `rand>=0.3 && nfes>0.5*max_nfes`,
  else the negative pool (reference variable `KF_poool`, renamed
  `kf_pool_negative` with the original cited); stochastic junior schedule
  exponent 0.5/2 with `round()`; init-drawn K kept for RNG-stream
  fidelity though unused.
- Shared helpers (`src/common/`): the reference `Gained_Shared_*_R1R2R3`
  names preserved; junior R3 uses the `floor(rand*N)+1` stream form (the
  GSK_Enhanced `randi` form is distribution-equal but stream-different -
  documented); senior partition parameterized by P with
  `round(N*P)`/`round(N*(1-P))`; reduction survivors proven equal to the
  reference's one-at-a-time worst-removal (ties removed highest index
  first).
- Fidelity: a temporary out-of-repo harness ran sed-extracted verbatim
  reference bodies against the ports on identical seeds - bit-identical
  best/nfes/error across 15 runs (GSK 3, AGSK 6, APGSK 6), including
  budget-crossing and early-stop cases.
- ATMALS-GSK (`atmals_gsk_optimize.m` + `atmals_prob_update.m`,
  `atmals_roulette_select.m`, `atmals_gaussmf.m`): `options.protocol`
  selects the cec2017 or cec2011 reference variant (G_Max `fix()` vs not;
  Mean_Fit = best-half mean of `abs(f-optimum)` vs raw fitness; LS clip
  exact-bounds vs +/-eps; senior partition form; cec2011-only D==1
  branch). Preserved quirks: RP update uses the LS range constants
  (RP_Max=5 never consumed); randperm drawn but LS modifies rows 1..NLS;
  adaptive P selected but never consumed; ProbUpdate's gaussmf center is
  the pool INDEX; alpha-memory weights the oldest row heaviest.
  `atmals_gaussmf` replaces the Fuzzy Logic Toolbox dependency
  (mathematically identical).
- eGSK (`egsk_optimize.m`, `egsk_gained_shared_senior.m`,
  `egsk_ip_refine.m`): late stage at `g >= 0.75*G_Max` every generation;
  KF1 triangular membership per row, KF2 from scalar anchors
  `fitness(min(Rvec))` (min over index vectors - quirk); clamps
  `KF(KF>=1)=0; KF(KF<=0)=0` as written; population-level selection twist
  with ties favoring the base population; IP refinement when
  `bsf > optimum+1e-8` and `std([a2 b2 c2])*1e-2 <= 1`, `fmincon` SQP
  budget `ceil(0.002*Max_FES)` (verified working on R2025b), required by
  default for reference-mode eGSK. Its junior helper matched the
  common one (cosmetic comma); its senior helper differs (no-P
  `round(NP*0.1)/round(NP*0.9)` form) and stays local.
- FDB-AGSK (`fdb_agsk_optimize.m` + `fdb_score_best.m`,
  `fdb_score_roulette.m`, `fdb_score_ranking.m`): case injections
  verified from the files - Case1 senior R2 = FDB argmax; Case2 senior R3
  from the TAIL (round(NP*0.95)+1..NP) of the FDB_Func2 descending
  ranking; Case3 junior R2=RFDB + R3=FDB; Case4 junior R1=RFDB + R3=FDB;
  Case5 junior R3=FDB. Default `fdb_case=1` (first/canonical case in the
  reference set; all five available). Reference harness NP=40*D,
  min_pop=12. Running FDB-AGSK on CEC suites is a framework-level
  extension (the reference cases ran a sphere problem). Documented
  deviation: the initial best solution VECTOR is recorded (the reference
  stored only its fitness) - bookkeeping only, trajectory unchanged.
- Sanctioned modernizations of the six MATLAB-source ports above (the ONLY
  deviations; DT-GSK's are listed in its own entry below): centralized
  `gsk_set_rng(options)` replaces uncontrolled session seeding; runner
  reference mode uses deterministic scheduled seeds instead of wall-clock
  seeding where historical releases used `rand('seed', sum(100*clock))`;
  NaN-optimum guards for suites without known optima; `result` bookkeeping
  fields.
- DT-GSK (`dt_gsk_optimize.m` + `dt_gsk_config.m`, `dt_gsk_graph.m`), the
  seventh optimizer and the only one ported from a non-MATLAB source.
  - Source: the DT-GSK reference implementation v2.46 (MIT license),
    <https://github.com/MostafaMassoud/DT-GSK> (tag `v2.46`, commit
    `64c70bb54125c9361b821939802ee4810fb7af50`); paper Masoud, Roshdy,
    Mohamed, "DT-GSK: Dimension-Tiered Adaptive Configuration Selection and
    Deterministic Refinement for Gaining-Sharing Knowledge-Based Optimization
    Algorithm", *Algorithms* (MDPI), 2026 (accepted, in production; DOI
    pending). MIT is compatible with the project's GPL-3.0-or-later; the
    MATLAB port is part of this project (`LICENSES.md`). DT-GSK is
    Dimension-Tiered GSK; the interaction-structure memory (SGSM) is one of its
    components, not its name.
  - Structure: exactly three code files. `dt_gsk_optimize.m` is the whole
    optimizer (initialization; the generation loop with NLPSR population
    reduction, ACE parameter selection, linkage crossover, DE/rand/1 entry,
    greedy selection, ARGP, BSE escapes and restarts, coordinate local search,
    final polish and deep-stall restart; the result struct), with small
    helpers as local functions. `dt_gsk_config.m` holds every setting of the
    published `pub` profile, grouped by dimension tier (`D < 20`,
    `20 <= D < 50`, `D >= 50`, `D >= 100`). `dt_gsk_graph.m` is the SGSM
    interaction graph (a handle class) used from `D = 50`. The tier table is
    in `src/optimizers/dt-gsk/README.md`; the algorithm is explained in
    `docs/algorithms/dt-gsk.md`.
  - Behavior: `NP = 5*D` initial population with nonlinear reduction toward
    `n_min` (12; 25 from `D = 50`); always the full budget (`termination =
    'max_evaluations'`, evaluation batches clipped to the remaining budget,
    so `nfes == max_nfes`); `error = best - optimum`, zeroed below
    `target_error`, `NaN` without an optimum. Draw order and the order of the
    floating-point operations (sequential and pairwise sums, stable sorts,
    the `argmin` NaN rule) follow the reference; dimension indices
    are 1-based. Seeding is unified-only with named Threefry substreams and
    the optimizer samples its own population, ignoring a runner `X0` (the
    documented fair-start exception; `docs/reference/seed_policy.md`).
  - Sanctioned differences (the only intended ones): (1) the error is the
    IEEE subtraction `best_fitness - optimum`, the project-wide rule, where
    the reference subtracts the two values in decimal arithmetic on their
    shortest printed forms and rounds back to double (its `compute_error`);
    the two can differ by about one ulp of `best_fitness` (identical when the optimum is 0, as on CEC2013LSGO);
    (2) MATLAB's `RandStream('threefry')` and the reference's Threefry replica
    give the same 64-bit words but round them to doubles slightly
    differently (MATLAB keeps up to one more bit below 0.5), so live runs
    differ by at most `2^-53` per uniform draw; integer, permutation and mask
    draws coincide.
  - Validation: a line-by-line port was verified against the unmodified
    reference implementation on identical random numbers in all four tiers
    and reproduces the reference's golden values to `1e-13`; the committed
    three-file version reproduces that port bit for bit on 25 full-budget runs
    plus 42 rare-branch problems. The full record, and the results of the CEC2017
    campaign against the imported reference
    (`benchmarks/cec_reference_results/cec2017/dt-gsk/`), are in
    `src/optimizers/dt-gsk/README.md`.
  - Scope / not ported: only the `pub` profile. Options that no `pub` tier
    selects (LHS/oversampled initialization, Nelder-Mead/subspace local
    search, event-triggered local search, state-driven DE policy, hysteresis
    module gate, coverage-weighted ACE, per-half ARGP memories, linkage
    reliability probes), research hooks, and telemetry/generation logs are
    left out (listed in the `dt_gsk_optimize.m` header). DT-GSK uses none of
    the `src/common/` helpers.

## Runners, Bridge, CLI (Phases 14-16)

- MATLAB runner `src/runners/run_experiment.m` executes one optimizer on
  one suite (functions x dimensions x runs), writing the CEC-competition
  layout `results/<optimizer>/<suite>/{summary,curves,gen_logs}` per
  `docs/reference/result_schema.md` (per-dimension summary tables, `per_run.csv`,
  `environment.json`; median-run `curves/`; checkpoint `gen_logs/`);
  unavailable (function,dimension) cells are explicit SKIPs recorded in
  `environment.json`; summary statistics are computed over errors when
  optima exist, else raw objectives (`statistics_basis` in
  `environment.json`).
- Seed policies are deliberately separate: C++ tooling
  (`gskcec/core/random.hpp`, `std::mt19937_64`) and MATLAB
  (`docs/reference/seed_policy.md`, implemented in `src/runners/run_experiment.m`);
  reference modes record every run seed. Unified MATLAB mode uses
  `get_cec_seed(base_seed,dim,func,run)` with the optimizer-independent formula
  `mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1`,
  supplies runner-generated `X0`, and restores the post-initialization RNG state.
  DT-GSK is unified-only: it gets that seed and `threefry` under every policy
  and no runner `X0` (it self-initializes).
  Wall-clock seeding is not a supported current mode.
- Budgets/targets (`src/runners/gskcec_make_problem.m`): cec2017/cec2013
  10000*D and target 1e-8; cec2020 AGSK budgets and 1e-8; cec2011 150000,
  no target; cec2013lsgo 3e6, no target; overridable via
  `max_evaluations`. They are suite budgets, the same for every optimizer
  (DT-GSK included).
- MEX bridge `gskcec_eval` (`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/`,
  built by `scripts/build_mex_bridge.ps1` with the WinLibs toolchain into
  `build/mex/`): OPTIONAL component so MATLAB optimizers evaluate the
  exact ported C++ benchmarks; the benchmark library itself stays
  MEX-free. Candidate matrices cross the bridge in the classic D x NP
  orientation.
- CLI: `gsk_list` (suites with functions/dims, optimizers, reference
  inventory), `gsk_validate` (`--references`, `--suite <s> --smoke`,
  `--suite cec2013 --against saved_vectors`, `--compare results refs
  [--out csv]`), `gsk_run` (config or flags; validates against the
  factory then drives MATLAB -batch; `--dry-run` prints the invocations;
  MATLAB located via `--matlab`, `GSKCEC_MATLAB`, or PATH - no hard-coded
  install paths). Config files are a strict flat YAML subset; unknown
  keys are rejected with line numbers.
- The test-only `sphere` suite in `gskcec_make_problem` keeps optimizer
  and runner tests MEX-free.

## Acceptance Status

All phases complete and verified on 2026-06-13:

- Clean CMake build (WinLibs GCC 16.1, `-std=c++20 -static`); all 12 ctest
  suites pass (core, reference-results, experiment, cec2011 wpa/wpb/wpc +
  integration, cec2013, cec2013lsgo, cec2017, cec2020, and the gsk_bench smoke).
  A 13th suite, the `gskcec_cli_exit_codes` CLI exit-code test, was added later;
  all 13 now pass.
- `gsk_list --optimizers` lists all six; `--benchmarks` lists all five
  suites with functions/dimensions; `--references` loads 35 files / 894
  rows. (Since DT-GSK was added it lists seven optimizers, and
  `--references` loads 165 files / 1411 rows.)
- `gsk_validate --suite <s> --smoke` passes for all five suites (CEC2020
  reports its 4 data-gap cells as explicit SKIPs); `--suite cec2013
  --against saved_vectors` matches at 0 deviation; `--references` passes.
- MEX bridge built (`scripts/build_mex_bridge.ps1`) and cross-checked from
  MATLAB against the original-MEX ground truth at **0** deviation
  (`src/tests/test_mex_bridge.m`).
- End-to-end `gsk_run --config configs/smoke.yml` runs MATLAB GSK on the
  ported CEC2017 benchmark through the bridge and writes the
  `summary/curves/gen_logs` tree in the documented schema; `gsk_validate --compare`
  loads them and reports win/tie/loss vs the imported references.
- MATLAB smoke suite (`run_matlab_smoke_tests`) green: common helpers, all
  six optimizers, the runner, and the bridge cross-check. DT-GSK
  (`test_dt_gsk_smoke.m`) and the runner resume and fair-start tests were
  added later; the suite now has 13 tests.
- Language-contract checks (no source files in other languages, no
  `cec2013.cpp`, no `.m`/`.R`/`.c` under `cec_suite_cpp`, no top-level
  include/tests/matlab) return nothing.

No open blockers.

## Standing Mandates Applied (2026-06-13)

The three cross-cutting mandates from the prompts' Section 1.1/3.1 were applied:

- **(c) Always verify against references.** `gsk_run` now automatically
  compares each run to the same optimizer's imported table and writes a
  `CONSISTENT`/`DEVIATES` verdict to `verification.json` (hard-failure checks:
  non-finite stats, error below the negative floor on known-optimum suites,
  and gross >1e6x deviation at full protocol; win/tie/loss informational;
  reduced-budget aware). Exposed standalone as `gsk_validate --verify`,
  opt-out via `--no-verify`. Unit + end-to-end tested; documented in
  `docs/reference/result_schema.md`.
- **(b) Simple, clear folders.** The tree was reviewed and kept intentionally
  shallow: imported reference tables live in `benchmarks/cec_reference_results`,
  while CEC ports, input data, and nested C++ tools live in
  `benchmarks/cec_suite_cpp`. The stale ISM-GSK content in the imported
  `cec_reference_results/README.md` was corrected; `configs/` and `scripts/` gained
  READMEs; `docs/reference/project_structure.md` gained a CEC folder-distinction table and a
  "where does a new file go?" decision guide; a `.gitignore` keeps the tracked
  tree clean (build/, results/).
- **(a) Clean code anyone can read.** Existing headers/help blocks already
  cite their reference source with provenance and link the contracts; a guided
  `docs/development/code_reading_guide.md` was added so a newcomer can navigate the code.
  Systematic readability refactors (numerically-equivalent only) are scheduled
  for publication-phase P3 under the same-seed / ground-truth gate.
