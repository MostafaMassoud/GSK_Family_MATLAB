# Extension Guide

> **Orientation.** This page shows how to *add* to `gsk_family`: a new optimizer,
> a benchmark suite, an output artifact, or a CLI command. It is for contributors
> extending capability rather than fixing existing code. After reading it you can
> create each kind of component, register it in the right place, and know which
> tests and docs to add. It assumes you have read the
> [Developer Guide](developer_guide.md) and the
> [Code Reading Guide](code_reading_guide.md); follow the
> [Contributor Guide](contributor_guide.md) when you submit. The optimizer
> contract is specified in
> [`matlab_interface.md`](../reference/matlab_interface.md), and per-suite
> fidelity rules are in [`porting_notes.md`](../reference/porting_notes.md).

Each section below is a self-contained recipe. Do the numbered steps in order;
the registration step (where the new component becomes visible to the runner or
CLI) is the one that is easy to forget. Remember the slug-vs-identifier split:
public slugs are hyphenated (`atmals-gsk`, `fdb-agsk`) in configs, CLI commands,
result folders, and reference folders, while MATLAB function and file names use
underscores.

## Add An Optimizer

An optimizer is a single MATLAB function `result = <stem>_optimize(problem,
options)` living under `src/optimizers/<slug>/`. The numbered contract below is
the same one `src/optimizers/gsk/gsk_optimize.m` follows; the skeleton after it
is a starting point that honors the structs in
[`matlab_interface.md`](../reference/matlab_interface.md).

1. Create `src/optimizers/<slug>/<stem>_optimize.m` (e.g.
   `src/optimizers/example/example_optimize.m`).
2. Expose `result = <stem>_optimize(problem, options)`.
3. Seed first: call `gsk_set_rng(options)` before drawing any randomness.
4. Read variant options from the `options` struct; defaults must equal the
   reference values.
5. Honor the runner-owned fair start: if `options.initial_population` is set,
   use it as `X0` instead of drawing your own first population, then restore
   `options.rng_state_after_initialization`.
6. Evaluate candidates only through `problem.evaluate` (row-wise NPxD in, NPx1
   out).
7. Keep candidates inside `problem.lb` and `problem.ub` (use the shared
   `gsk_bound_repair` midpoint rule).
8. Stop at `problem.max_nfes` (and at `problem.target_error` only if the
   reference algorithm does).
9. Return the `result` struct with exactly the documented fields.
10. For MATLAB runs nothing needs registering: the runner adds every folder
    under `src/optimizers/` to the path and maps a hyphenated slug to its
    function stem (`my-gsk` -> `my_gsk_optimize`). A new optimizer runs under
    the unified seed schedule and gets the runner's shared X0; `np_init` is
    passed as both `options.np` and `options.np_init`, and `min_pop_size` as
    given. Register it in `src/runners/run_experiment.m` only for
    reference-mode seeding (the seed/RNG switches there) or for the C++ CLI
    (below). [Comparing Algorithms](../research/comparing_algorithms.md) is the
    short version of this recipe for researchers. Every option the new file
    reads (`options.<name>`, `isfield(options,'<name>')`,
    `local_option(options,'<name>',...)`) can then be set from an alias in the
    root `algorithms.ini`; the runner finds the accepted names by reading the
    file. An option of one of the seven must also be added to its list in
    `alias_setting_names` (`src/runners/run_experiment.m`) and to the table in
    the command reference, "Algorithm aliases".
11. Add a smoke test `src/tests/test_<stem>_smoke.m`, and add a reference table
    under `benchmarks/cec_reference_results/` plus a page under `docs/`.

Steps 3 and 5 assume the reference uses MATLAB's global RNG and ordinary
uniform initialization. A reference that defines its own random streams and
initialization keeps them, with the runner adjusted instead; DT-GSK is the
worked example ([Port From A Non-MATLAB Reference](#port-from-a-non-matlab-reference)).

### Skeleton

The `optimize` contract is the same one baseline GSK follows. The stub below
shows the seeding, fair-start, option-reading, and `result` construction
patterns. Fill the loop with the real search and keep every field name as
written.

```matlab
function result = example_optimize(problem, options)
%EXAMPLE_OPTIMIZE Example GSK-family optimizer (replace with the real search).
%   result = EXAMPLE_OPTIMIZE(problem, options) honors the contract in
%   docs/reference/matlab_interface.md.

gsk_set_rng(options);                         % step 3: seed before any rand

np  = get_option(options, 'np', 100);         % step 4: reference default
dim = problem.dim;
max_nfes = problem.max_nfes;

% Step 5: runner-owned fair start (unified mode only). When the runner supplies
% X0, use it and restore the post-initialization RNG state; otherwise draw your
% own initial population in the reference location.
if isfield(options, 'initial_population') && ~isempty(options.initial_population)
    X = options.initial_population;
    gsk_restore_rng_after_initialization(options);
else
    X = gsk_init_population(np, problem.lb, problem.ub);
end

start = tic;
fit  = problem.evaluate(X);                   % step 6: NPxD in, NPx1 out
nfes = size(X, 1);
[best_fitness, ib] = min(fit);
best_x = X(ib, :);
conv_nfes = nfes;
conv_best = best_fitness;

% Search loop: build candidates inside problem.lb/problem.ub, evaluate only
% through problem.evaluate, update best_x/best_fitness, and stop at max_nfes.
while nfes < max_nfes
    % ... reference update producing children U (NPxD) ...
    U  = gsk_bound_repair(U, problem.lb, problem.ub);   % step 7
    fu = problem.evaluate(U);
    take = min(size(U, 1), max_nfes - nfes);            % budget-crossing
    nfes = nfes + take;
    [cb, jc] = min(fu(1:take));
    if cb < best_fitness
        best_fitness = cb;
        best_x = U(jc, :);
    end
    conv_nfes(end+1, 1) = nfes;                          %#ok<AGROW>
    conv_best(end+1, 1) = best_fitness;                  %#ok<AGROW>
end

if isnan(problem.optimum)
    err = NaN;
else
    err = best_fitness - problem.optimum;               % target zeroing applied
end

result = struct( ...
    'optimizer',       'example', ...
    'suite',           problem.suite, ...
    'func_id',         problem.func_id, ...
    'dim',             dim, ...
    'seed',            options.seed, ...
    'best_x',          best_x, ...
    'best_fitness',    best_fitness, ...
    'error',           err, ...
    'nfes',            nfes, ...
    'termination',     'max_evaluations', ...
    'convergence',     struct('nfes', conv_nfes, 'best_fitness', conv_best), ...
    'runtime_seconds', toc(start), ...
    'params',          struct('np', np), ...
    'notes',           '');
end
```

The runner builds the function handle from the slug in
`src/runners/run_experiment.m`
(`optimize = str2func([optimizer_function_stem(a.optimizer) '_optimize'])`).
The local function `optimizer_function_stem` replaces hyphens with
underscores for any slug it does not list, so a new slug needs no `case`
there:

```matlab
function stem = optimizer_function_stem(optimizer)
switch optimizer
    case 'atmals-gsk'
        stem = 'atmals_gsk';
    case 'fdb-agsk'
        stem = 'fdb_agsk';
    case 'dt-gsk'
        stem = 'dt_gsk';
    otherwise
        % A user-added optimizer: 'my-gsk' -> my_gsk_optimize.
        stem = strrep(optimizer, '-', '_');
end
end
```

A new adaptive variant that needs reference-compatible seeding also gets a
`case` in the reference seed switch (`pick_run_seed` in
`src/runners/run_experiment.m`) and in the reference-RNG selection
(`effective_rand_generator`). Keep the reference-mode metadata in step: the
same optimizer lists drive `seed_scheme_string` and the strides /
`seed_formula` written by `write_run_metadata`. The C++ side advertises optimizers
independently; add the slug to `gsk_list` so `gsk_list --optimizers` lists it,
and to `kOptimizers` in `gsk_run.cpp` so `gsk_run` accepts it. The comparison
code needs no change: it reads the slug from the summary file name, which is the
reference folder name.

## Port From A Non-MATLAB Reference

DT-GSK (`src/optimizers/dt-gsk/`) is the example of an optimizer whose
reference is not a MATLAB release: it was ported from the DT-GSK reference
implementation v2.46 (MIT license). With no MATLAB original to diff
against, the unmodified reference code serves as the oracle. The route it took,
recorded in `src/optimizers/dt-gsk/README.md`:

1. **Pin the reference.** Work from a read-only checkout at a tagged release
   and record the version and commits (DT-GSK:
   `benchmarks/cec_reference_results/cec2017/dt-gsk/PROVENANCE.md`). Check the
   license is compatible with this project's GPL-3.0-or-later (MIT is) and
   record it in `LICENSES.md`.
2. **Port line by line first.** Translate module by module, keeping the draw
   order and the order of floating-point operations (DT-GSK keeps the
   reference's sequential and pairwise sums and its stable sorts).
3. **Verify against the oracle on identical random numbers.** Run the port and
   the unmodified reference on the same random numbers and compare
   generations, evaluations, per-stream draw counts and convergence traces, on
   every configuration branch (DT-GSK: all four dimension tiers). Expect
   agreement to round-off until a last-bit difference flips a discrete
   decision (exact ties, one-ulp improvements). The oracle harness and the
   foreign code stay outside this repository; none of it is committed.
4. **Reproduce the reference's own golden values** and keep them in the smoke
   test (DT-GSK: seed 12345, 3,000 evaluations, reproduced to `1e-13`;
   `src/tests/test_dt_gsk_smoke.m` checks the sphere cells).
5. **Compact only afterwards.** A refactored version must reproduce the
   line-by-line port bit for bit (DT-GSK: best point, fitness, `nfes` and full
   trace on 25 full-budget runs across every tier, plus 42 problems aimed at
   rare branches).
6. **Document RNG differences.** MATLAB's Threefry generator produces the same
   64-bit words as the reference implementation's generator, but the two
   convert them to doubles differently (at most
   `2^-53` per uniform draw), so live campaigns are compared statistically, not
   bit for bit.
7. **Mirror the reference protocol in the runner** rather than forcing the
   family's conventions onto the port. DT-GSK's campaigns used the unified seed
   with its own initialization, so `run_experiment` treats it as unified-only
   (`is_unified_only`: `get_cec_seed` and `threefry` under every
   `seed_policy`, no runner `X0`) and records the fair-start exception in the
   metadata.
8. **Import the reference's results** under
   `benchmarks/cec_reference_results/<suite>/<slug>/` (aggregate tables, plus
   per-run evidence in an `evidence/` subfolder, which the table loader
   ignores), then compare a full campaign run by run with
   `scripts/compare_reference_runs.m`.

## Add A Benchmark Suite

A suite is a C++ port implementing the `BenchmarkProblem` interface plus a
factory entry. Add both, wire the input data, then prove the port with
fixed-vector ground-truth tests. See
[`porting_notes.md`](../reference/porting_notes.md) for the fidelity bar each
existing suite meets, and
[architecture](../reference/architecture.md) for the benchmark layer.

1. Implement the port under `benchmarks/cec_suite_cpp/<suite>/src/<suite>_problem.cpp`,
   satisfying the interface in
   `benchmarks/cec_suite_cpp/cec_tools/include/gskcec/benchmark/benchmark.hpp`:
   `evaluate(x)`, `bounds()`, `optimum()`, `dimension()`. Load all data from an
   explicit `data_root` (no current-directory dependence); throw exceptions that
   name the offending suite/function/dimension/file.
2. Expose a `gskcec::<suite>::make_problem(...)` and wire it into the generic
   factory: add a suite branch in
   `benchmarks/cec_suite_cpp/cec_tools/src/benchmark/factory.cpp::make_problem`
   (the existing branches are at `factory.cpp:41`-`68`) and add the suite to
   `suite_info`/`list_suites` in the same file so `gsk_list --benchmarks` shows
   its functions and dimensions.
3. Add input data under `benchmarks/cec_suite_cpp/<suite>/input_data/`.
4. Add fixed-vector ground-truth data under
   `benchmarks/cec_suite_cpp/cec_tools/tests/data/` and a unit test under
   `benchmarks/cec_suite_cpp/cec_tools/tests/unit/` that compares the port against
   it (bounds, dimensions, function ids, and probe values), plus a
   `gsk_validate --suite <suite> --smoke` path.
5. Expose the suite to the MATLAB side in
   `src/runners/gskcec_make_problem.m` (budget, target, and the `gskcec_eval`
   wiring); the `sphere` test suite stays pure MATLAB.
6. Rebuild the C++ tree and run `ctest --test-dir build --output-on-failure`,
   then rebuild the MEX bridge before running any MATLAB experiment on the new
   suite.

Keep `cec2013` and `cec2013lsgo` distinct; do not introduce a path ending in
`cec2013.cpp` (a repo check forbids that generated-binding file name).

## Add An Output Artifact

An artifact is a file the runner writes per experiment (for example a CSV or a
JSON summary). Add the writer, document its schema, and test by parsing it back.
Existing artifacts and their byte-format conventions are in
[`result_schema.md`](../reference/result_schema.md).

1. Add the writer to `src/runners/run_experiment.m`, keeping output under the
   CEC-competition layout `results/<optimizer>/<suite>/{summary,curves,gen_logs}`.
2. Document the new file or column in
   [`result_schema.md`](../reference/result_schema.md).
3. Add a test that parses the artifact back rather than only checking that the
   file exists.
4. Keep generated output under `results/` only - never write into
   `benchmarks/cec_reference_results`, and preserve the existing resume/archive
   behavior (completed runs skipped, refreshed summaries archived under
   `_archive/<timestamp>/`).

## Add A CLI Command

A CLI command is a small C++ tool that links the `gskcec` library and lives
beside the existing tools. The current commands - `gsk_list`, `gsk_validate`,
`gsk_run`, and `gsk_bench` - are under
`benchmarks/cec_suite_cpp/cec_tools/src/cli/` and delegate all real work to the
lower C++ layers (and, for `gsk_run`, to MATLAB in `-batch` mode). Follow that
pattern.

1. Create a new tool under
   `benchmarks/cec_suite_cpp/cec_tools/src/cli/<command>.cpp`, linking the `gskcec`
   library (the factory, config parser, and comparison live there).
2. Add the executable target to `CMakeLists.txt` next to the existing CLI
   targets.
3. Keep the CLI thin: parsing and orchestration in the tool, real logic in the
   `benchmark`/`experiment` library or (for experiment runs) in
   `src/runners/run_experiment.m`. Locate MATLAB via `--matlab`, the
   `GSKCEC_MATLAB` environment variable, or `PATH` - never a hard-coded install
   path.
4. Rebuild the C++ tree, add a unit test under
   `benchmarks/cec_suite_cpp/cec_tools/tests/`, run `ctest`, and update the
   [Command Reference](../getting-started/command_reference.md).
