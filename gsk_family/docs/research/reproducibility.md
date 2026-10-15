# Reproducibility

> **What this is:** the rules and the step-by-step procedure for making a
> `gsk_family` run repeatable -- same config, same seeds, same artifacts -- plus
> an honest statement of what is and is not bit-exact against the historical
> reference releases.
> **For:** anyone who needs a run to come out the same way twice, or who is
> preparing evidence for a paper or release.
> **Prerequisites:** [Researcher Handbook](researcher_handbook.md) for workflow
> context; [Seed Policy](../reference/seed_policy.md) for the exact seed
> formulas and generator mapping; [the glossary](../reference/glossary.md) for
> terms.
> **After reading:** you will know how to record the MATLAB and C++ environment,
> how the four seed policies work, the settings that pin determinism, the run
> procedure, and the precise bit-exact caveats (including why serial and `parfor`
> runs are identical).

This project treats reproducibility as a first-class deliverable. Every run
records its own seed schedule, environment, and an automatic verification
verdict.

## Environment

Record exactly what software produced a result, so it can be recreated later.
A `gsk_family` result depends on two toolchains: MATLAB for the optimizers and
a C++20 build for the CEC benchmark ports plus the MEX bridge.

Record the MATLAB side:

```matlab
version                         % MATLAB release, e.g. R2025b
ver                             % installed toolboxes (eGSK reference mode needs Optimization Toolbox)
```

Record the C++ build that produced the ported benchmarks and the bridge:

```powershell
gcc --version                   # WinLibs MinGW-w64 GCC 16.1.0, -std=c++20 -static
cmake --version                 # WinLibs 4.x or MATLAB-bundled 3.25
git rev-parse HEAD              # commit hash of the source tree
```

Each run writes `summary/environment.json` below the run directory. It captures
`optimizer`, `suite`, functions, dimensions, runs, `base_seed`, `seed_policy`,
`rand_generator`, `initial_population_policy`, `use_parallel`,
`max_nfes_override`, `statistics_basis`, `checkpoint_fractions`,
`matlab_version`, `cpu_cores`, `computer`, `platform`, `git_commit`,
`timestamp`, and the exact MATLAB `command` (`run_experiment.m`). Keep this file
-- together with the launcher call or config, it is the core provenance for the
run. The C++ compiler and build type are properties of the build tree
(`build/CMakeCache.txt`); the MEX bridge in use is recorded by its path under
`build/mex/`. See [Result Schema](../reference/result_schema.md#summaryenvironmentjson)
for the full field list.

## Seeds

Seeds decide the random draws, so fixing them is what makes a run repeatable.
The campaign anchor is `base_seed = 20240620`, centralized in
`run_experiment.m` (`default_base_seed`); it is a fixed date-like value, never
generated from the clock.

There are four policies. The default depends on the entry point:

| Seed policy | Use it to | Result | Default for |
|---|---|---|---|
| `unified` | Compare optimizers fairly. | Same seed for every optimizer at the same `(dim, func, run)`; fair-start population and post-init RNG state shared across the family. | `run_experiment` and `run_all_cec*.m` launchers |
| `reference` | Reproduce published CEC tables. | Per-optimizer seeding plus a per-optimizer generator fixed as a project choice (GSK `twister`; the others the legacy `seed` stream; this does not replay the archived AGSK/APGSK `twister` drivers). | `gsk_run` CLI, `configs/*.yml`, `scripts/run_all.ps1` |
| `native` / `derived` | Diagnostic hashed schedules. | Decorrelated per-run seeds that also fold in optimizer and suite names; not a fair cross-optimizer schedule. | direct `run_experiment(...)` opt-in only |

`native` and `derived` are aliases of the same hashed rule.

**DT-GSK is unified-only.** Its reference campaigns were produced on the unified
schedule, so `run_experiment` (`is_unified_only`) gives DT-GSK the unified seed
and `threefry` under every policy above, mirroring the reference
implementation's `UNIFIED_ONLY_OPTIMIZERS`. DT-GSK derives named Threefry substreams from the
run seed and samples its own `NP = 5*D` initial population; the runner draws
no `X0` for it, a supplied `options.initial_population` is ignored, and the run
metadata records
`initial_population_policy = optimizer self-initializes NP = 5*D ...` and
`profile: "pub"` (`run_config.json`). This is the one documented fair-start
exception: DT-GSK shares the family's seeds, not its initial population.

The seed helpers live in:

```text
src/runners/get_cec_seed.m        % unified formula
src/runners/derive_run_seed.m     % native / derived hashed rule
src/runners/run_experiment.m      % chooses the policy, draws X0, records seeds
```

The `unified` seed is optimizer-independent
(`src/runners/get_cec_seed.m:35-39`):

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

For `(base_seed=20240620, dim=30, func=7, run=12)` this is exactly `69241386`,
the same value for GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, and DT-GSK. See
[Numerical Examples](numerical_examples.md#unified-seed-and-fair-start) for the
hand-checkable derivation, and [Seed Policy](../reference/seed_policy.md) for the
reference formulas (`gsk`/`egsk`/`atmals-gsk` = `base_seed + 9973*func + (run-1)`;
`agsk`/`apgsk`/`fdb-agsk` = `D*func*run`) and the generator mapping.

Every per-run seed is recorded in `summary/seed_schedule.csv`,
`summary/per_run.csv`, and the `Seed` column of `gen_logs/`;
`summary/run_config.json`, `summary/phase0_protocol.json`, and
`summary/environment.json` record `base_seed`, the policy, the seed scheme, and
the seed formula (not per-cell seeds). Wall-clock seeding is not a supported
mode anywhere in the project.

## Deterministic Settings

Pin every source of variation explicitly rather than relying on a default that
could change.

- Use a fixed `base_seed` (default `20240620`).
- Use an explicit `seed_policy`.
- Use an explicit `rand_generator`. `gsk_set_rng.m` selects the generator and,
  via `RandStream`, controls `rand`, `randi`, **and** `randperm` together, so the
  whole optimizer trajectory is deterministic. In `unified` mode the runner
  resolves `threefry` when the installed MATLAB supports it and falls back to
  `twister` otherwise; the resolved generator is recorded in `environment.json`.
- Use an explicit `max_evaluations` (`max_nfes`) for reduced experiments.
- Use `overwrite: true` only when you intend to regenerate evidence from a clean
  active tree; the previous tree is archived under `_overwrite_archive/`.
  Otherwise the runner resumes and appends, reusing only `per_run.csv` rows whose
  stored seed, budget (`max_nfes`) and generator match the active run.
- Keep generated output outside `benchmarks/cec_reference_results/` so runs never
  overwrite the imported reference tables (`run_experiment` refuses such an
  `output_dir` with `run_experiment:outputUnsafe`).
- Keep `use_parallel = false` for the reproducibility baseline. Serial is the
  default in `run_experiment`, and `gsk_run` plus `scripts/run_all.ps1` pass
  serial explicitly.

## Experiment Procedure

Run the pipeline in confidence-building order: prove the ports are exact, prove
a small run works, then commit to the full campaign, then validate and archive.

1. **Build the C++ tooling and the MEX bridge.** A missing or stale bridge fails
   before any partial result folder is written.

   ```powershell
   cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
   cmake --build build -j
   scripts\build_mex_bridge.ps1
   ```

2. **Run `ctest`** to confirm the 13 C++ suites pass (the ports are checked
   exactly against fixed-vector ground truth; the 13th checks CLI exit codes).

   ```powershell
   ctest --test-dir build --output-on-failure
   ```

3. **Run the MATLAB smoke tests** (13 tests) so the optimizers, runner, and
   bridge cross-check are green before you generate evidence.

   ```powershell
   matlab -batch "run('gsk_family/src/tests/run_matlab_smoke_tests.m')"
   ```

4. **Run a smoke configuration** -- a reduced budget that exercises the whole
   pipeline quickly.

   ```powershell
   gsk_run --config configs\smoke.yml
   ```

5. **Run the intended campaign** at the real budget and run count. The root
   launchers default to `unified` + `threefry`:

   ```matlab
   run_all_cec2017     % the optimizers in its CONFIG block, fair cross-family schedule
   ```

6. **Validate generated summaries against the imported reference tables** when
   applicable (use a temporary output root so you do not touch campaign results):

   ```powershell
   gsk_validate --compare results\_run_all\gsk\cec2017 benchmarks\cec_reference_results
   ```

   Where the reference ships per-run evidence (today the DT-GSK CEC2017
   `evidence/per_run.csv`), also compare run by run in MATLAB, from the project
   root with `scripts` on the path (Statistics and Machine Learning Toolbox; see
   [Command Reference 3.7](../getting-started/command_reference.md#37-dt-gsk)):

   ```matlab
   compare_reference_runs('results/_run_all/dt-gsk/cec2017', ...
       'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv')
   ```

7. **Archive** the launcher call or config, `environment.json`, `per_run.csv`,
   the summary CSVs, the `curves/` and `gen_logs/` artifacts, and
   `verification.json`.

To check that repeated runs land identically, run the same campaign twice (or
once serial and once parallel) and byte-compare the deterministic numeric
artifacts. See
[Numerical Examples](numerical_examples.md#parallel-determinism) for why parallel
and serial runs produce identical output.

## Bit-Exact Caveats

This is the honest scope of the project. Read it before claiming equivalence to
the historical source.

The project separates two senses of "correct", and they have different
guarantees:

- **CEC benchmark ports are checked exactly.** The C++20 ports are validated
  against fixed-vector ground truth: `ctest` runs 13 suites (the 13th,
  `gskcec_cli_exit_codes`, checks CLI exit codes); CEC2017 matches at
  rel-tol `1e-10` with maximum observed deviation about `4.8e-15`, CEC2013 saved
  vectors at `1e-12`, and CEC2020 at maximum deviation about `2.8e-16`. Within
  the supported protocol these ports are effectively bit-exact reproductions.
- **Optimizers are checked statistically.** Each `gsk_run` auto-writes
  `summary/verification.json` with a `CONSISTENT` or `DEVIATES` verdict against
  the same optimizer's published table. This is a consistency and schema check,
  not a universal claim of bit-exact replay of every published number. See the
  [Validation Report](validation_report.md) for what the verdict checks.

Two toolbox-bound caveats:

- **eGSK local search** uses MATLAB `fmincon` (SQP) for the IP refinement stage,
  required by default in reference mode. Strict reproducibility of eGSK final
  accuracy therefore depends on the MATLAB and Optimization Toolbox version.
  Without the toolbox, the default call raises `egsk:fminconUnavailable`; passing
  `use_fmincon=false` is an explicit non-reference diagnostic recorded in
  `result.notes`.
- **ATMALS-GSK and eGSK** were originally wall-clock seeded in their source
  releases. This project keeps reference runs deterministic by using the
  scheduled seed with the effective reference RNG, so those runs are repeatable
  even though the original releases were not.

One cross-implementation caveat:

- **DT-GSK** is a port of an external reference implementation, and its
  imported tables were produced by that implementation. MATLAB's Threefry
  generator produces the same 64-bit words as the reference implementation's
  generator but converts them to doubles slightly differently (at most `2^-53`
  per uniform draw; integer, permutation and mask draws coincide), so a live
  MATLAB run is not bit-identical to the reference run with the same seed. A
  line-by-line port was verified against the unmodified reference
  implementation on identical random numbers in all four dimension tiers, and
  the compact shipped version reproduces that port bit for bit; agreement with
  the imported campaigns is therefore judged statistically. The validation record
  and the CEC2017 campaign results are recorded in
  [src/optimizers/dt-gsk/README.md](../../src/optimizers/dt-gsk/README.md).

### Serial and parallel parity

Serial and parallel (`parfor`) runs are bit-identical. The reason is structural,
not luck:

- The per-run seed is a pure function of `(base_seed, dim, func, run)`. It never
  uses worker identity, task IDs, `parfor` scheduling order, the current time, or
  shuffle-based seeding (`src/runners/get_cec_seed.m`). Serial and `parfor` tasks
  call the same seed helper.
- In `unified` mode the runner draws `X0` once with that seed, captures the
  post-initialization RNG state, and every optimizer restores it before its first
  algorithmic random decision. The draw order is fixed regardless of backend.
  DT-GSK instead builds its own Threefry substreams from the run seed and never
  touches the global RNG, which is backend-independent as well.

So the only thing parallelism changes is task completion order, and the runner
restores input order before writing any CSV. `src/tests/test_seed_policy.m`
checks this end to end when the Parallel Computing Toolbox is available: on its
own 2-worker process pool it runs `run_experiment` serially and with
`use_parallel=true` and requires byte-identical `seed_schedule.csv`, summary,
`CheckpointErrors` and median curve, plus equal `per_run.csv` rows apart from
the `runtime_seconds` column (it prints a skip message without the toolbox).
Setting `use_parallel = true` is
safe for results but should be smoke-tested first so every worker can see
`src/runners/run_experiment.m`, `src/common`, the optimizer folders, and the MEX
bridge.
