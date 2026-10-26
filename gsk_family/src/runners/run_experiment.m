function run_experiment(varargin)
%RUN_EXPERIMENT MATLAB experiment driver (invoked by gsk_run or directly).
%
%   run_experiment('optimizer','gsk', 'suite','cec2017', ...
%                  'functions',[1 3], 'dimensions',[10], 'runs',3, ...
%                  'base_seed',20240620, 'max_nfes',0, ...
%                  'project_root','D:/...', 'output_dir','D:/.../results/gsk/cec2017', ...
%                  'overwrite',false, 'verbose',true, ...
%                  'seed_policy','unified', 'rand_generator','threefry', ...
%                  'use_parallel',false, 'write_graphs',false)
%
% 'np_init',n (integer >= 12) sets the initial population size of every
% optimizer (options.np for gsk/egsk/atmals-gsk, options.np_init for the
% others); under unified seeding the runner's shared X0 then has n rows. Empty
% (default) keeps each optimizer's own default: 100, or 5*D for DT-GSK. A
% value other than that default is a variant: the reference comparison table
% is skipped. An output_dir written with another NP is refused (use a new
% output_dir or 'overwrite',true).
%
% 'min_pop_size',m (integer >= 11) sets the final population size of the
% population reduction in agsk, apgsk and fdb-agsk (default 12; m must not
% exceed their initial NP) and dt-gsk (default 12, or 25 for D >= 50). gsk,
% egsk and atmals-gsk keep a fixed population and ignore it, so one launcher
% value can serve the whole family. A value other than the default is a
% variant, treated like np_init (comparison table skipped, different-value
% trees refused).
%
% 'optimizer' may also be an alias from algorithms.ini in the repository root
% (one level above project_root; 'aliases_file',path picks another file). An
% alias names a base optimizer and its own settings, e.g. [gsk-np100] with
% base = gsk and np_init = 100. It runs the base's code with those settings;
% its np_init and min_pop_size replace the call's. Its files are named after
% the alias (pass an output_dir of its own; the launchers use
% results/_run_all/<alias>/<suite>), and environment.json records the base
% and the settings. Unknown setting names, protected ones (seed,
% rand_generator, initial_population, rng_state_after_initialization,
% protocol) and min_pop_size for gsk, egsk or atmals-gsk are refused. Changed
% settings make the run a variant (comparison table skipped), and a tree
% written with other alias settings is refused. Seeds are those of the base,
% so aliases and optimizers are compared on the same seeds.
%
% 'verbose',false hides the per-run lines and prints one summary row per
% (function, dimension); useful for long multi-run sweeps.
%
% 'trace_points',n (default 0 = off; else an integer >= 2, e.g. 50) also
% writes gen_logs/BestTrace_<name>_F<f>_D<d>.csv: the best-so-far value of
% every run at n log-spaced budgets from 1 to max_nfes (same layout as the
% checkpoint files), for smooth ERT and ECDF data profiles
% (scripts/plot_performance.m). It reads the runs' own convergence records,
% so the runs and every other file are unchanged.
%
% 'log_trace',true (default false) asks every optimizer for its opt-in
% per-generation dynamics trace (options.log_trace: evaluations, population
% size, population diversity and its own adaptive parameters) and writes
% trace/Dynamics_<name>_F<f>_D<d>.csv, at most 'trace_rows' (200)
% generations per run, for scripts/plot_dynamics.m. Tracing draws no random
% numbers and changes no value, so the runs are exactly those without it.
%
% An existing output_dir is resumed by default. Generated CSVs are appended
% where possible. A completed run id is skipped when its stored seed, cell
% budget (max_nfes) and generator match the active run; otherwise it is re-run
% and appended. Fixed-name files are archived under _archive/<timestamp>/
% before refresh. 'overwrite',true first archives the whole output tree and
% starts clean, reusing no old per-run rows. An output_dir inside
% benchmarks/cec_reference_results is always refused.
%
% Writes the CEC-competition results layout (docs/reference/result_schema.md):
%
%   <output_dir>/summary/   <optimizer>_<suite>_D<dim>.csv  (Function,Best,Median,Mean,Worst,SD)
%                           <optimizer>_<suite>.csv         (all functions; native-dim suites)
%                           per_run.csv                     (full per-run schema, seeds incl.)
%                           environment.json                (run environment + metadata)
%   <output_dir>/curves/    Figure_F<f>_D<d>_Run#<r>.csv    (Eval,BestError,Log10Error; median run)
%                           graphs/Figure_F<f>_D<d>.png     (optional, write_graphs=true)
%   <output_dir>/gen_logs/  CheckpointErrors_<optimizer>_F<f>_D<d>.csv  (Run,Seed,E<nfes>...)
%
% Checkpoints follow the standard CEC fractional schedule
% [0.01 0.02 0.03 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0] x max_nfes.
% Suites with fixed per-function dimensions (CEC2011, CEC2013-LSGO) take
% dimensions = 0 (native) and also get a dimensionless rollup summary. A
% (function, dimension) cell whose benchmark data is unavailable is a SKIP
% recorded in environment.json. Statistics are over errors when the suite has
% known optima, otherwise over raw objectives (statistics_basis).
%
% Seed policies:
%   unified   -> default for direct calls and run_all_cec*.m. Seed =
%                get_cec_seed(base_seed,D,func,run); threefry when the
%                installed MATLAB supports it, else twister. The runner draws
%                one X0 and every optimizer restores the post-X0 RNG state,
%                for strict, fair cross-family comparisons.
%   reference -> reproduces the published tables; each optimizer keeps its
%                historical seed formula and generator.
%   native/derived -> diagnostic hashed schedules that include optimizer and
%                suite identity: reproducible, but not same-seed comparisons.
% DT-GSK always uses the unified seed and threefry and draws its own X0.

% Default base_seed for direct calls and the root run_all_cec*.m launchers:
% a stable, date-like project seed. Changing it starts a new reproducible
% campaign; gsk_run and config files can still pass an explicit seed.
default_base_seed = 20240620;

p = inputParser;
p.addParameter('optimizer', '', @ischar);
p.addParameter('suite', '', @ischar);
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', 0, @isnumeric);
p.addParameter('runs', 1, @isnumeric);
p.addParameter('base_seed', default_base_seed, @isnumeric);
p.addParameter('max_nfes', 0, @isnumeric);
p.addParameter('project_root', '', @ischar);
p.addParameter('output_dir', '', @ischar);
p.addParameter('overwrite', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('verbose', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('seed_policy', 'unified', @check_seed_policy);
p.addParameter('rand_generator', 'threefry', @(x) any(strcmpi(char(x), {'threefry', 'twister', 'seed', 'state', 'auto', 'default'})));
p.addParameter('use_parallel', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('write_graphs', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('np_init', [], @isnumeric);
p.addParameter('min_pop_size', [], @isnumeric);
p.addParameter('aliases_file', '', @(x) ischar(x) || isstring(x));
p.addParameter('trace_points', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x == fix(x) && x ~= 1);
p.addParameter('log_trace', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('trace_rows', 200, @(x) isnumeric(x) && isscalar(x) && x >= 2 && x == fix(x));
p.parse(varargin{:});
a = p.Results;
a.optimizer = canonical_optimizer_id(a.optimizer);
% An alias from algorithms.ini runs its base optimizer with its own settings:
% from here on a.optimizer is the base (it decides the algorithm, seeds and
% options) and a.name the alias (it names the files and labels the results).
a = resolve_alias(a);
if ~isempty(a.np_init)
    % 12 is the population floor of AGSK, APGSK and FDB-AGSK (min_pop_size),
    % so one value is valid for the whole family.
    assert(isscalar(a.np_init) && isfinite(a.np_init) && a.np_init == fix(a.np_init) && ...
           a.np_init >= 12, 'run_experiment:args', 'np_init must be an integer >= 12');
    a.np_init = double(a.np_init);
end
if ~isempty(a.min_pop_size)
    % The P = 0.05 senior partition of AGSK, APGSK and FDB-AGSK needs NP >= 11.
    assert(isscalar(a.min_pop_size) && isfinite(a.min_pop_size) && ...
           a.min_pop_size == fix(a.min_pop_size) && a.min_pop_size >= 11, ...
           'run_experiment:args', 'min_pop_size must be an integer >= 11');
    a.min_pop_size = double(a.min_pop_size);
    % AGSK, APGSK and FDB-AGSK reject min_pop_size > NP; DT-GSK caps it.
    np_start = ternary(isempty(a.np_init), 100, a.np_init);
    assert(~any(strcmp(a.optimizer, {'agsk', 'apgsk', 'fdb-agsk'})) || a.min_pop_size <= np_start, ...
           'run_experiment:args', 'min_pop_size (%d) must not exceed the initial population size (%d)', ...
           a.min_pop_size, np_start);
end

assert(~isempty(a.optimizer), 'run_experiment:args', 'optimizer is required');
assert(~isempty(a.suite), 'run_experiment:args', 'suite is required');
assert(~isempty(a.functions), 'run_experiment:args', 'functions is required');
assert(~isempty(a.project_root), 'run_experiment:args', 'project_root is required');
assert(~isempty(a.output_dir), 'run_experiment:args', 'output_dir is required');
% Only the unified policy resolves 'auto'/'default' (threefry when available,
% else twister). native/derived pass rand_generator straight to gsk_set_rng,
% which rejects them, so every cell would end as a SKIP.
if any(strcmpi(char(a.seed_policy), {'native', 'derived'})) && ...
        any(strcmpi(char(a.rand_generator), {'auto', 'default'}))
    error('run_experiment:args', ...
        ['rand_generator ''%s'' is resolved only under seed_policy=''unified''; ' ...
         'use threefry, twister, seed, or state with seed_policy=''%s'''], ...
        char(a.rand_generator), char(a.seed_policy));
end
% Generated output must never land in the imported reference tree. Checked on
% every run (not only with overwrite), before any directory is created.
assert_output_dir_outside_reference(a.output_dir, a.project_root);

setup_paths(a.project_root);
if ~strcmpi(a.suite, 'sphere')
    % CEC suites need the project's C++ MEX bridge. A missing bridge is a
    % startup error, not hundreds of skipped cells.
    gskcec_require_mex(a.project_root, 'run_experiment');
end
if logical(a.use_parallel)
    ensure_process_pool();   % process-based pool for the parfor run loop
end
optimize = str2func([optimizer_function_stem(a.optimizer) '_optimize']);

session_tag = datestr(now, 'yyyy-mm-dd_HH.MM.SS');
a.overwrite_archived_to = '';
if logical(a.overwrite)
    archived_to = overwrite_output_tree(a.output_dir, a.project_root, session_tag);
    if ~isempty(archived_to)
        a.overwrite_archived_to = archived_to;
        fprintf(['run_experiment: overwrite=true; archived previous output tree:\n' ...
                 '                %s\n' ...
                 '                -> %s\n'], a.output_dir, archived_to);
    end
end

summary_dir = fullfile(a.output_dir, 'summary');
curves_dir = fullfile(a.output_dir, 'curves');
genlogs_dir = fullfile(a.output_dir, 'gen_logs');
resume_existing = exist(a.output_dir, 'dir') ~= 0;
for d = {summary_dir, curves_dir, genlogs_dir}
    if ~exist(d{1}, 'dir'); mkdir(d{1}); end
end
if resume_existing
    fprintf(['run_experiment: preserving existing output tree and resuming/appending: %s\n' ...
             '                no generated files are deleted; fixed-name artifacts are archived before refresh.\n'], ...
            a.output_dir);
end

% Optional convergence graph PNGs go under curves/graphs. They are
% display-only and can be slow (exportgraphics); the numeric curves/*.csv
% files are always written and are the authoritative plotting data.
graphs_dir = fullfile(curves_dir, 'graphs');
if logical(a.write_graphs) && ~exist(graphs_dir, 'dir'); mkdir(graphs_dir); end
% Each dimension mirrors its console output to its own timestamped log
% (summary/<opt>_<dtag>_log_<stamp>.txt, opened in the dimension loop).
% This backstop turns logging off when the function exits.
diary_backstop = onCleanup(@() diary('off')); %#ok<NASGU>

checkpoint_fracs = [0.01 0.02 0.03 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0];
known_optimum = ~any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));
assert_same_population(summary_dir, a);

% Existing result records make reruns resumable: completed runs are skipped,
% new cells are added, and summary tables are rebuilt from old + new data.
% Each per-run row records its cell budget and effective generator; a
% per_run.csv without those columns is upgraded once (upgrade_legacy_per_run)
% before it is read.
per_run_path = fullfile(summary_dir, 'per_run.csv');
per_run_header = ['optimizer,suite,function,dimension,run,seed,best_fitness,error,' ...
                  'nfes,termination,runtime_seconds,max_nfes,rand_generator'];
upgrade_legacy_per_run(per_run_path, per_run_header, summary_dir, a.project_root, session_tag);
existing_records = load_existing_per_run_records(summary_dir, a.name, a.suite);
stats = load_existing_summary_stats(summary_dir, a.name, a.suite);
if ~isempty(stats)
    fprintf('run_experiment: loaded %d existing summary row(s) for resume/add mode.\n', numel(stats));
end
% Latest seed_schedule.csv seed per (Dim,Function,Run), so a reused run is
% re-recorded when an intermediate session wrote a different seed for it.
schedule_seeds = load_latest_schedule_seeds(fullfile(summary_dir, 'seed_schedule.csv'));

% summary/per_run.csv keeps the full per-run schema (seed, nfes, termination,
% runtime, budget, generator) next to the CEC-style aggregates. Existing files
% are appended, never truncated.
fr = open_csv_for_append(per_run_path, per_run_header);
closer = onCleanup(@() fclose(fr));

% seed_schedule.csv: the (Dim,Function,Run,Seed) actually used, written live.
fs = open_csv_for_append(fullfile(summary_dir, 'seed_schedule.csv'), ...
    'Dim,Function,Run,Seed');
seed_closer = onCleanup(@() fclose(fs)); %#ok<NASGU>

skipped = {};
notes = {};
total = tic;

func_list = a.functions(:)';
% CEC2017 excludes F2 (unstable; omitted from the reference tables). Drop it
% so every optimizer follows the published comparison protocol.
excluded_funcs = [];
if strcmp(a.suite, 'cec2017')
    excluded_funcs = func_list(func_list == 2);
    func_list = func_list(func_list ~= 2);
end
nfuncs = numel(func_list);

% Record the run configuration and protocol up front, for reproducibility
% (run_config.json, phase0_protocol.json in summary/).
write_run_metadata(summary_dir, a, func_list, excluded_funcs, known_optimum, session_tag);

% Sweep one dimension at a time, so each prints its own banner and results
% table (one row per function). Loop order does not change the result files:
% write_summary_files filters by dimension and sorts by function. Each
% dimension's tables are written as soon as it finishes (written_dims), so a
% crash in a later dimension cannot lose them.
written_dims = [];
for dim = a.dimensions(:)'
    % Mirror this dimension's console output to its own timestamped log:
    % summary/<opt>_<dtag>_log_<yyyy-mm-dd_HH.MM.SS>.txt (dtag D<dim> or native)
    if dim == 0; dtag = 'native'; else; dtag = sprintf('D%d', dim); end
    stamp = datestr(now, 'yyyy-mm-dd_HH.MM.SS');
    diary(fullfile(summary_dir, sprintf('%s_%s_log_%s.txt', a.name, dtag, stamp)));
    diary on;
    % Detailed log of every run of every function in this dimension:
    % summary/<opt>_<dtag>_runs_log_<stamp>.txt
    runs_log = open_runs_log(summary_dir, a, dtag, stamp, known_optimum, func_list);
    print_detailed_config(a, known_optimum, func_list, excluded_funcs);

    banner_printed = false;
    dim_done = 0;
    dim_runs_done = 0;
    dim_func_ids = [];
    dim_means = [];
    dim_D = [];      % problem dimension of each reported function
    curve_f = [];    % median-run convergence per function, for the graphs
    curve_d = [];
    curve_x = {};
    curve_y = {};
    dim_resume_messages = {};
    dim_skip_messages = {};
    for fi = 1:nfuncs
        func_id = func_list(fi);
        try
            problem = gskcec_make_problem(a.suite, func_id, dim, a.project_root, a.max_nfes);
            problem_guard = onCleanup(@() free_problem(problem)); %#ok<NASGU>
        catch err
            fprintf('SKIP %s f%d D%d: %s\n', a.suite, func_id, dim, err.message);
            skipped{end + 1} = sprintf('f%d D%d: %s', func_id, dim, err.message); %#ok<AGROW>
            continue;
        end
        D = problem.dim;
        existing_cell_records = records_for_cell(existing_records, D, func_id);
        requested_runs = 1:a.runs;
        [existing_cell_records, stale_runs] = keep_records_matching_current_seed( ...
            existing_cell_records, a, D, func_id, requested_runs, ...
            problem.max_nfes, effective_rand_generator(a));
        if ~isempty(stale_runs)
            dim_resume_messages{end + 1} = sprintf( ... %#ok<AGROW>
                ['RESUME %s f%d D%d: ignoring stale existing run(s) ' ...
                 '(seed, budget or generator differ from this run): %s'], ...
                a.suite, func_id, D, run_list_text(stale_runs));
        end
        existing_runs = unique([existing_cell_records.run]);
        runs_to_do = setdiff(requested_runs, existing_runs);
        % Reused runs belong to the active schedule too: if the latest
        % seed_schedule.csv row for one came from another session's
        % configuration, append the active seed again. The latest row per
        % (Dim,Function,Run) then always describes the current results; it is
        % the row verify_unified_seed_schedule compares.
        for r = setdiff(requested_runs, runs_to_do)
            seed_r = pick_run_seed(a, D, func_id, r);
            key = schedule_key(D, func_id, r);
            if ~isKey(schedule_seeds, key) || ~seeds_equal(schedule_seeds(key), seed_r)
                fprintf(fs, '%d,%d,%d,%s\n', D, func_id, r, seed_to_text(seed_r));
                schedule_seeds(key) = seed_r;
            end
        end
        if isempty(runs_to_do)
            dim_resume_messages{end + 1} = sprintf( ... %#ok<AGROW>
                'RESUME %s f%d D%d: runs 1:%d already present; skipping cell', ...
                a.suite, func_id, D, a.runs);
            [combined_runs, combined_values] = combine_existing_and_new_values( ...
                existing_cell_records, runs_to_do, [], known_optimum, a.runs);
            if ~isempty(combined_values)
                row = stat_row_from_values(func_id, D, combined_values, known_optimum, report_zero_tol(a));
                stats = upsert_stat(stats, row);
                if ~banner_printed
                    print_run_banner(a, D, nfuncs, problem);
                    print_table_header();
                    banner_printed = true;
                end
                print_table_row(func_id, row.best, row.median, row.mean, row.worst, row.sd, 0);
                dim_done = dim_done + 1;
                dim_func_ids(end + 1) = func_id; %#ok<AGROW>
                dim_means(end + 1) = row.mean;  %#ok<AGROW>
                dim_D(end + 1) = D;             %#ok<AGROW>
                % The median over the reported runs changes with the requested
                % run count; keep only that run's curve in curves/.
                med_run_id = median_run_id(combined_runs, combined_values, runs_to_do);
                [n_moved, has_trace] = keep_only_median_curve(curves_dir, graphs_dir, func_id, D, ...
                    med_run_id, combined_values(combined_runs == med_run_id), false, session_tag);
                if ~has_trace
                    dim_resume_messages{end + 1} = missing_curve_message(a.suite, func_id, D, med_run_id); %#ok<AGROW>
                elseif n_moved > 0
                    [cx, cy] = read_curve(curves_dir, func_id, D, med_run_id);   % re-render its graph
                    curve_f(end + 1) = func_id; curve_d(end + 1) = D;      %#ok<AGROW>
                    curve_x{end + 1} = cx;      curve_y{end + 1} = cy;     %#ok<AGROW>
                end
            end
            clear problem_guard
            continue;
        elseif numel(runs_to_do) < a.runs
            dim_resume_messages{end + 1} = sprintf( ... %#ok<AGROW>
                'RESUME %s f%d D%d: %d/%d run(s) present; running missing run(s): %s', ...
                a.suite, func_id, D, numel(existing_runs), a.runs, run_list_text(runs_to_do));
        end
        if ~banner_printed
            print_run_banner(a, D, nfuncs, problem);
            print_table_header();
            banner_printed = true;
        end
        cell_timer = tic;   % wall-clock time for this (function, dimension) row
        % A failed run in this (function, dimension) cell records a SKIP and
        % the sweep goes on: one bad cell must not abort a long
        % multi-optimizer run. The MEX handle is always freed afterwards.
        try
        checkpoints = unique(round(checkpoint_fracs * problem.max_nfes));
        checkpoints = checkpoints(checkpoints >= 1);

        nr_todo = numel(runs_to_do);
        run_errors = zeros(nr_todo, 1);      % final error (or raw objective) per run
        run_seeds = zeros(nr_todo, 1);
        chk_errors = zeros(nr_todo, numel(checkpoints));
        conv_nfes = cell(nr_todo, 1);
        conv_err = cell(nr_todo, 1);
        dyn = cell(nr_todo, 1);         % opt-in dynamics traces (log_trace)
        run_best = zeros(nr_todo, 1);   % full per-run detail for the runs log
        run_errv = zeros(nr_todo, 1);
        run_nfes = zeros(nr_todo, 1);
        run_rt   = zeros(nr_todo, 1);
        run_term = cell(nr_todo, 1);

        % Runs are independent. Each optimizer call is seeded from its
        % scheduled per-run seed; in unified mode that is
        % get_cec_seed(base_seed,D,func,run), the same for every optimizer in
        % the same cell. Wall-clock seeding is not accepted; clock-seeded
        % historical references use deterministic scheduled seeds instead.
        % The loop is serial by default, for reproducibility and robust path
        % handling. Use use_parallel=true (parfor) only after a local smoke
        % test shows the workers can see the runner, helpers, optimizer
        % folders and MEX bridge. Deterministic modes give identical results
        % either way.
        %
        % Each worker builds its OWN problem: the gskcec_eval MEX handle is
        % process-local and cannot be shared from the client, so it is created
        % and freed inside the iteration. File and console output is collected
        % per run and written in run order after the loop, so per_run.csv and
        % seed_schedule.csv are byte-identical to a serial sweep.
        for rr = 1:nr_todo
            run_id = runs_to_do(rr);
            run_seeds(rr) = pick_run_seed(a, D, func_id, run_id);
        end
        prun_rows = cell(nr_todo, 1);
        verb_rows = cell(nr_todo, 1);
        notes_c   = cell(nr_todo, 1);
        % Broadcast only plain data to the workers (not the options struct or
        % the client problem, whose MEX handle is invalid on a worker).
        opt_name = a.optimizer; suite_name = a.suite; proot = a.project_root; np_init = a.np_init;
        min_pop_size = a.min_pop_size;
        run_label = a.name;                 % the alias for an algorithms.ini alias, else opt_name
        alias_settings = a.alias_settings;  % its other settings (plain numbers and logicals)
        log_trace = logical(a.log_trace);   % opt-in per-generation dynamics trace
        mnf = a.max_nfes; nruns = a.runs; verbose = logical(a.verbose);
        optimum_local = problem.optimum;
        rand_gen = effective_rand_generator(a);   % reference/unified may differ from a.rand_generator
        % Unified fair start is stronger than a shared numeric seed. The
        % runner draws X0 once and captures the RNG state right after it. The
        % optimizer takes X0 as its initial population and restores that
        % state before its later random draws, so optimizer-specific
        % initialization code cannot consume different amounts of randomness
        % before the search starts.
        use_unified_x0 = unified_initialization_enabled(a);
        zero_tol_local = report_zero_tol(a);
        if logical(a.use_parallel)
            parfor rr = 1:nr_todo
                setup_paths_once(proot);                              % set up the worker path (once per worker)
                wp = gskcec_make_problem(suite_name, func_id, dim, proot, mnf);
                handle_guard = onCleanup(@() free_problem(wp)); %#ok<NASGU>  free on exit/error
                run_id = runs_to_do(rr);
                scheduled_seed = run_seeds(rr);
                run_opts = optimizer_run_options(opt_name, suite_name, scheduled_seed, rand_gen, ...
                                                 np_init, min_pop_size);
                run_opts = add_alias_settings(run_opts, alias_settings);
                if log_trace; run_opts.log_trace = true; end
                if use_unified_x0
                    [x0, rng_after_x0] = make_unified_initial_population(wp, scheduled_seed, rand_gen, np_init);
                    run_opts.initial_population = x0;
                    run_opts.rng_state_after_initialization = rng_after_x0;
                end
                result = optimize(wp, run_opts);
                seed = result.seed;
                run_seeds(rr) = seed;

                gn = result.convergence.nfes(:);
                gb = result.convergence.best_fitness(:);
                ge = arrayfun(@(b) curve_value(b, optimum_local, opt_name, suite_name), gb);
                conv_nfes{rr} = gn;
                conv_err{rr} = ge;
                chk_errors(rr, :) = checkpoint_errors(min(gn, wp.max_nfes), ge, checkpoints);
                if known_optimum
                    run_errors(rr) = result.error;
                else
                    run_errors(rr) = result.best_fitness;   % statistics over raw objectives
                end
                run_best(rr) = result.best_fitness;   % full per-run detail for the runs log
                % CEC zero cutoff on the per-run error written to per_run.csv
                % and the runs log (project-wide 1e-8, known-optimum suites).
                err_out = result.error;
                if known_optimum && abs(err_out) < zero_tol_local; err_out = 0; end
                run_errv(rr) = err_out;
                run_nfes(rr) = result.nfes;
                run_rt(rr)   = result.runtime_seconds;
                run_term{rr} = result.termination;
                notes_c{rr} = result.notes;
                if log_trace && isfield(result, 'trace'); dyn{rr} = result.trace; end
                prun_rows{rr} = sprintf('%s,%s,%d,%d,%d,%s,%.17g,%.17g,%d,%s,%.6f,%d,%s\n', ...
                        run_label, suite_name, func_id, D, run_id, seed_to_text(seed), ...
                        result.best_fitness, err_out, result.nfes, ...
                        result.termination, result.runtime_seconds, wp.max_nfes, rand_gen);
                if verbose
                    verb_rows{rr} = sprintf('%s %s f%d D%d run %d/%d: best=%.6e error=%.6e nfes=%d (%.1fs)\n', ...
                            run_label, suite_name, func_id, D, run_id, nruns, ...
                            result.best_fitness, result.error, result.nfes, result.runtime_seconds);
                end
            end
        else
            for rr = 1:nr_todo
                setup_paths_once(proot);
                wp = problem;   % serial mode can reuse the cell-level MEX handle safely
                run_id = runs_to_do(rr);
                scheduled_seed = run_seeds(rr);
                run_opts = optimizer_run_options(opt_name, suite_name, scheduled_seed, rand_gen, ...
                                                 np_init, min_pop_size);
                run_opts = add_alias_settings(run_opts, alias_settings);
                if log_trace; run_opts.log_trace = true; end
                if use_unified_x0
                    [x0, rng_after_x0] = make_unified_initial_population(wp, scheduled_seed, rand_gen, np_init);
                    run_opts.initial_population = x0;
                    run_opts.rng_state_after_initialization = rng_after_x0;
                end
                result = optimize(wp, run_opts);
                seed = result.seed;
                run_seeds(rr) = seed;

                gn = result.convergence.nfes(:);
                gb = result.convergence.best_fitness(:);
                ge = arrayfun(@(b) curve_value(b, optimum_local, opt_name, suite_name), gb);
                conv_nfes{rr} = gn;
                conv_err{rr} = ge;
                chk_errors(rr, :) = checkpoint_errors(min(gn, wp.max_nfes), ge, checkpoints);
                if known_optimum
                    run_errors(rr) = result.error;
                else
                    run_errors(rr) = result.best_fitness;
                end
                run_best(rr) = result.best_fitness;
                err_out = result.error;
                if known_optimum && abs(err_out) < zero_tol_local; err_out = 0; end
                run_errv(rr) = err_out;
                run_nfes(rr) = result.nfes;
                run_rt(rr)   = result.runtime_seconds;
                run_term{rr} = result.termination;
                notes_c{rr} = result.notes;
                if log_trace && isfield(result, 'trace'); dyn{rr} = result.trace; end
                prun_rows{rr} = sprintf('%s,%s,%d,%d,%d,%s,%.17g,%.17g,%d,%s,%.6f,%d,%s\n', ...
                        run_label, suite_name, func_id, D, run_id, seed_to_text(seed), ...
                        result.best_fitness, err_out, result.nfes, ...
                        result.termination, result.runtime_seconds, wp.max_nfes, rand_gen);
                if verbose
                    verb_rows{rr} = sprintf('%s %s f%d D%d run %d/%d: best=%.6e error=%.6e nfes=%d (%.1fs)\n', ...
                            run_label, suite_name, func_id, D, run_id, nruns, ...
                            result.best_fitness, result.error, result.nfes, result.runtime_seconds);
                end
            end
        end
        % Write per-run records in run order (same content as a serial run).
        for rr = 1:nr_todo
            run_id = runs_to_do(rr);
            fprintf(fs, '%d,%d,%d,%s\n', D, func_id, run_id, seed_to_text(run_seeds(rr)));
            fprintf(fr, '%s', prun_rows{rr});
            if ~isempty(notes_c{rr}); notes{end + 1} = notes_c{rr}; end %#ok<AGROW>
            if verbose && ~isempty(verb_rows{rr}); fprintf('%s', verb_rows{rr}); end
        end

        write_checkpoint_errors(genlogs_dir, a.name, func_id, D, checkpoints, runs_to_do, run_seeds, chk_errors, session_tag);
        if a.log_trace
            write_dynamics_trace(fullfile(a.output_dir, 'trace'), a.name, func_id, D, runs_to_do, ...
                                 dyn, a.trace_rows, session_tag);
        end
        if a.trace_points > 0
            % Optional dense trace for ERT/ECDF: best-so-far value at
            % trace_points log-spaced budgets, from the runs' own convergence
            % records (no change to the runs or to CheckpointErrors_*.csv).
            tpts = trace_budgets(problem.max_nfes, a.trace_points);
            trace = zeros(nr_todo, numel(tpts));
            for rr = 1:nr_todo
                trace(rr, :) = checkpoint_errors(min(conv_nfes{rr}, problem.max_nfes), conv_err{rr}, tpts);
            end
            write_checkpoint_errors(genlogs_dir, a.name, func_id, D, tpts, runs_to_do, run_seeds, trace, ...
                                    session_tag, 'BestTrace');
        end
        append_function_runs(runs_log, func_id, D, known_optimum, runs_to_do, ...
                             run_seeds, run_best, run_errv, run_nfes, run_term, run_rt, problem, report_zero_tol(a));
        [combined_runs, combined_values] = combine_existing_and_new_values( ...
            existing_cell_records, runs_to_do, run_errors, known_optimum, a.runs);
        [med_run_id, med_new_idx] = median_run_id(combined_runs, combined_values, runs_to_do);
        % One median-run curve per cell: earlier sessions' curves whose run is
        % no longer the median are archived, never left beside this one.
        [~, has_trace] = keep_only_median_curve(curves_dir, graphs_dir, func_id, D, ...
            med_run_id, combined_values(combined_runs == med_run_id), med_new_idx > 0, session_tag);
        if med_new_idx > 0
            write_curve(curves_dir, func_id, D, med_run_id, conv_nfes{med_new_idx}, conv_err{med_new_idx}, session_tag);
            curve_f(end + 1) = func_id;                    %#ok<AGROW>
            curve_d(end + 1) = D;                          %#ok<AGROW>
            curve_x{end + 1} = conv_nfes{med_new_idx};      %#ok<AGROW>
            curve_y{end + 1} = conv_err{med_new_idx};       %#ok<AGROW>
        elseif has_trace
            % The median is an earlier run whose stored trace is still current.
            [cx, cy] = read_curve(curves_dir, func_id, D, med_run_id);
            curve_f(end + 1) = func_id; curve_d(end + 1) = D;      %#ok<AGROW>
            curve_x{end + 1} = cx;      curve_y{end + 1} = cy;     %#ok<AGROW>
        else
            dim_resume_messages{end + 1} = missing_curve_message(a.suite, func_id, D, med_run_id); %#ok<AGROW>
        end

        row = stat_row_from_values(func_id, D, combined_values, known_optimum, report_zero_tol(a));
        cell_best = row.best; cell_median = row.median; cell_mean = row.mean;
        cell_worst = row.worst; cell_sd = row.sd;
        stats = upsert_stat(stats, row);
        % One table row per (function, dimension), always printed, so a long
        % sweep shows progress even with 'verbose',false.
        print_table_row(func_id, cell_best, cell_median, cell_mean, cell_worst, cell_sd, toc(cell_timer));
        dim_done = dim_done + 1;
        dim_runs_done = dim_runs_done + nr_todo;
        dim_func_ids(end + 1) = func_id; %#ok<AGROW>
        dim_means(end + 1) = cell_mean;  %#ok<AGROW>
        dim_D(end + 1) = D;              %#ok<AGROW>
        catch err
            print_table_skip_row(func_id);
            dim_skip_messages{end + 1} = sprintf('SKIP %s f%d D%d (run failed): %s', ...
                a.suite, func_id, D, err.message); %#ok<AGROW>
            skipped{end + 1} = sprintf('f%d D%d (run failed): %s', func_id, D, err.message); %#ok<AGROW>
        end

        clear problem_guard
    end

    if banner_printed
        print_table_footer();
        fprintf('\n[OK] Updated %d function(s); wrote %d new run(s)\n', ...
                dim_done, dim_runs_done);
        print_skip_messages(dim_skip_messages);
        print_resume_messages(dim_resume_messages);
        % The comparison table and graphs are display-only: a failure there
        % (e.g. an unusual reference-table format) must never abort the sweep.
        try
            print_comparison_table(a, dim, dim_func_ids, dim_means);
        catch cmp_err
            fprintf('(comparison table skipped: %s)\n', cmp_err.message);
        end
        try
            fprintf('\nPost-processing artifacts for %s %s %s...\n', upper(a.name), upper(a.suite), dtag);
            if logical(a.write_graphs)
                ng = make_convergence_graphs(graphs_dir, a, curve_f, curve_d, curve_x, curve_y, session_tag);
                fprintf('Saved %d convergence graph(s) to %s\n', ng, graphs_dir);
            else
                fprintf('Graph PNG rendering skipped (write_graphs=false). Numeric curves/*.csv and gen_logs/*.csv were still written.\n');
            end
        catch gph_err
            fprintf('(graphs skipped: %s)\n', gph_err.message);
        end
    elseif ~isempty(dim_resume_messages)
        print_resume_messages(dim_resume_messages);
    end
    if ~isempty(dim_D)
        write_summary_files(summary_dir, a.name, a.suite, stats, known_optimum, session_tag, unique(dim_D));
        written_dims = union(written_dims, dim_D);
    end
    close_runs_log(runs_log);
    diary off;   % close this dimension's log
end

fprintf('\nFinalizing result files...\n');
fprintf('  [1/2] Writing summary CSV files...\n');
% Write the tables of dimensions not written above (e.g. only loaded from an
% earlier session); the rollup too if no dimension was written above.
if isempty(stats)
    remaining_dims = [];
else
    remaining_dims = setdiff(unique([stats.dim]), written_dims);
end
write_summary_files(summary_dir, a.name, a.suite, stats, known_optimum, session_tag, ...
                    remaining_dims, isempty(written_dims));
fprintf('  [2/2] Writing environment metadata...\n');
write_environment(summary_dir, a, stats, skipped, notes, known_optimum, checkpoint_fracs, toc(total), session_tag);
fprintf('Finalizing result files: done.\n');

fprintf('run_experiment: wrote %s\n', a.output_dir);
if ~isempty(skipped)
    % Make a partial run unmistakable: each skipped cell (unavailable data or
    % a failed run) is a missing row in the summary tables. Details are
    % printed above and stored in environment.json (skipped_cells).
    warning('run_experiment:skippedCells', ...
            '%d (function,dimension) cell(s) were SKIPPED - results are PARTIAL. See environment.json.', ...
            numel(skipped));
end
end

% ---- resume / append helpers ------------------------------------------------

function fid = open_csv_for_append(path, header)
%OPEN_CSV_FOR_APPEND Append to an existing generated CSV without truncating it.
% Writes the header only to a new or empty file; raises run_experiment:io if
% the file cannot be opened.
write_header = true;
if isfile(path)
    info = dir(path);
    write_header = isempty(info) || info.bytes == 0;
end
fid = fopen(path, 'a');
assert(fid > 0, 'run_experiment:io', 'cannot open %s', path);
if write_header
    fprintf(fid, '%s\n', header);
end
end

function ok = archive_existing_file(path, session_tag)
%ARCHIVE_EXISTING_FILE Copy a fixed-name artifact before refreshing it.
% The copy goes to <folder>/_archive/<session_tag>/ (name_<n> if taken).
% ok is false only when an existing file could not be copied (a
% run_experiment:archive warning is issued).
ok = true;
if ~isfile(path)
    return;
end
[folder, name, ext] = fileparts(path);
archive_dir = fullfile(folder, '_archive', session_tag);
if ~exist(archive_dir, 'dir'); mkdir(archive_dir); end
target = fullfile(archive_dir, [name ext]);
n = 1;
while isfile(target)
    target = fullfile(archive_dir, sprintf('%s_%d%s', name, n, ext));
    n = n + 1;
end
try
    copyfile(path, target);
catch err
    ok = false;
    warning('run_experiment:archive', ...
            'Could not archive %s before refresh (%s). Existing file remains in place until write.', ...
            path, err.message);
end
end

function upgrade_legacy_per_run(path, header, summary_dir, project_root, session_tag)
%UPGRADE_LEGACY_PER_RUN Add the trailing max_nfes,rand_generator columns once.
% Resume reuses a per_run.csv row only when its seed, cell budget and
% effective generator all match the active run
% (keep_records_matching_current_seed). A file whose header is a prefix of
% the current one lacks those two columns. It is archived, its header is
% replaced, and each row gets the two fields from the tree's run_config.json
% (the configuration of the session that last wrote the tree), with the
% budget resolved per cell as that session did (gskcec_make_problem). Rows
% that cannot be resolved get blank fields, so they are re-run, not reused.
% Existing field values are copied unchanged. Raises run_experiment:io if the
% archive copy or the rewrite fails.
if ~isfile(path); return; end
fid = fopen(path, 'r');
if fid < 0; return; end
raw = fread(fid, Inf, '*char')';
fclose(fid);
lines = regexp(raw, '\r?\n', 'split');
first = strtrim(lines{1});
if isempty(first) || ~startsWith(header, [first ',']); return; end   % current or unknown header
legacy_cols = numel(strsplit(first, ','));
[override, generator] = previous_tree_config(summary_dir);
budgets = containers.Map('KeyType', 'char', 'ValueType', 'double');
for i = 2:numel(lines)
    f = strsplit(lines{i}, ',', 'CollapseDelimiters', false);
    if isempty(strtrim(lines{i})) || numel(f) ~= legacy_cols; continue; end
    key = strjoin(f(2:4), '|');   % suite|function|dimension
    if ~isKey(budgets, key)
        budgets(key) = legacy_cell_budget(f{2}, str2double(f{3}), str2double(f{4}), project_root, override);
    end
    if isfinite(budgets(key)) && ~isempty(generator)
        lines{i} = sprintf('%s,%d,%s', lines{i}, budgets(key), generator);
    else
        lines{i} = [lines{i} ',,'];
    end
end
lines{1} = header;
assert(archive_existing_file(path, session_tag), 'run_experiment:io', ...
       'cannot archive %s before adding the max_nfes,rand_generator columns', path);
fid = fopen(path, 'w');
assert(fid > 0, 'run_experiment:io', 'cannot open %s', path);
fprintf(fid, '%s', strjoin(lines, newline));
fclose(fid);
fprintf(['run_experiment: per_run.csv upgraded with max_nfes,rand_generator columns ' ...
         '(previous file archived under summary/_archive/%s/).\n'], session_tag);
end

function assert_same_population(summary_dir, a)
%ASSERT_SAME_POPULATION Refuse to resume a tree written with another population size.
% per_run.csv rows do not record np_init or min_pop_size, so resume would
% reuse runs made with different population sizes. The tree's run_config.json
% (latest session) gives the values it was written with; a missing field or
% file means the optimizer's default. A value equal to the default (np_init =
% 100 except for DT-GSK, min_pop_size = 12 except for DT-GSK) matches a
% default tree. A tree without per_run.csv has nothing to reuse.
if ~isfile(fullfile(summary_dir, 'per_run.csv'))
    return;
end
path = fullfile(summary_dir, 'run_config.json');
prev_np = [];
prev_min = [];
prev_alias = '';
if isfile(path)
    try
        cfg = jsondecode(fileread(path));
        if isfield(cfg, 'np_init') && isnumeric(cfg.np_init)
            prev_np = double(cfg.np_init);
        end
        if isfield(cfg, 'min_pop_size') && isnumeric(cfg.min_pop_size)
            prev_min = double(cfg.min_pop_size);
        end
        if isfield(cfg, 'alias_settings') && ischar(cfg.alias_settings)
            prev_alias = cfg.alias_settings;
        end
    catch
    end
end
% An algorithms.ini alias whose settings were edited since the tree was
% written would mix two configurations in one tree.
if ~strcmp(prev_alias, a.alias_text)
    error('run_experiment:args', ...
          ['%s was written with alias settings "%s"; %s now has "%s". ' ...
           'Use a new alias name, a new output_dir or ''overwrite'',true.'], summary_dir, ...
          prev_alias, a.name, a.alias_text);
end
if ~strcmp(np_init_text(a.optimizer, prev_np), np_init_text(a.optimizer, a.np_init))
    error('run_experiment:args', ...
          ['%s was written with np_init = %s; this call uses np_init = %s. ' ...
           'Use a new output_dir or ''overwrite'',true.'], summary_dir, ...
          np_init_text(a.optimizer, prev_np), np_init_text(a.optimizer, a.np_init));
end
if ~strcmp(min_pop_text(a.optimizer, prev_min), min_pop_text(a.optimizer, a.min_pop_size))
    error('run_experiment:args', ...
          ['%s was written with min_pop_size = %s; this call uses min_pop_size = %s. ' ...
           'Use a new output_dir or ''overwrite'',true.'], summary_dir, ...
          min_pop_text(a.optimizer, prev_min), min_pop_text(a.optimizer, a.min_pop_size));
end
end

function s = min_pop_text(optimizer, min_pop_size)
%MIN_POP_TEXT Final population size label; equal labels mean equal runs.
if ~uses_min_pop_size(optimizer)
    s = 'not used';
elseif isempty(min_pop_size) || (min_pop_size == 12 && ~strcmp(optimizer, 'dt-gsk'))
    if strcmp(optimizer, 'dt-gsk'); s = '12, or 25 for D >= 50 (default)'; else; s = '12 (default)'; end
else
    s = sprintf('%d', min_pop_size);
end
end

function tf = uses_min_pop_size(optimizer)
%USES_MIN_POP_SIZE Optimizers whose population reduction reads min_pop_size.
tf = any(strcmp(optimizer, {'agsk', 'apgsk', 'fdb-agsk', 'dt-gsk'}));
end

function tf = is_family_optimizer(optimizer)
%IS_FAMILY_OPTIMIZER True for the seven GSK-family optimizers shipped here.
tf = any(strcmp(optimizer, {'gsk', 'agsk', 'apgsk', 'fdb-agsk', 'atmals-gsk', 'egsk', 'dt-gsk'}));
end

function a = resolve_alias(a)
%RESOLVE_ALIAS Turn an algorithms.ini alias into its base optimizer and settings.
% Sets a.name (the alias, or the optimizer itself), a.alias_settings (struct of
% settings passed to the optimizer, without np_init/min_pop_size, which go to
% a.np_init/a.min_pop_size and replace the call's values), a.alias_text (all
% settings as one line, '' for a plain optimizer) and a.alias_file. A name
% that is one of the seven, or a folder under src/optimizers, is a plain
% optimizer; anything else must be an alias.
a.name = a.optimizer;
a.alias_settings = struct();
a.alias_text = '';
a.alias_file = '';
root = char(a.project_root);
if isempty(a.optimizer) || isempty(root)
    return;   % missing arguments are reported later
end
file = char(a.aliases_file);
if isempty(file)
    file = fullfile(fileparts(regexprep(root, '[\\/]+$', '')), 'algorithms.ini');
end
if is_real_optimizer(a.optimizer, root)
    % A plain optimizer. An [alias] of the same name would be ignored, so it
    % is an error; any other problem in the file does not stop this run.
    try
        clash = isKey(read_algorithm_aliases(file), a.optimizer);
    catch
        clash = false;
    end
    if clash
        error('run_experiment:args', ['%s: [%s] has the name of an optimizer; give the alias ' ...
              'a new name (e.g. [%s-np100]) and set base = %s'], file, a.optimizer, a.optimizer, a.optimizer);
    end
    return;
end
aliases = read_algorithm_aliases(file);
if ~isKey(aliases, a.optimizer)
    error('run_experiment:args', ['unknown optimizer ''%s'': it is not one of the seven, not a ' ...
          'folder under src/optimizers, and not an [alias] in %s'], a.optimizer, file);
end
al = aliases(a.optimizer);
base = al.base;
if ~is_real_optimizer(base, root)
    error('run_experiment:args', ['%s: [%s] has base = %s, which is not one of the seven or a ' ...
          'folder under src/optimizers (an alias cannot be the base of another alias)'], ...
          file, al.name, base);
end
s = al.settings;
if isfield(s, 'np')   % the name GSK, eGSK and ATMALS-GSK use internally
    if isfield(s, 'np_init')
        error('run_experiment:args', '%s: [%s] sets both np and np_init; keep np_init', file, al.name);
    end
    s.np_init = s.np; s = rmfield(s, 'np');
end
if isfield(s, 'np_init'); a.np_init = s.np_init; s = rmfield(s, 'np_init'); end
if isfield(s, 'min_pop_size')
    if any(strcmp(base, {'gsk', 'egsk', 'atmals-gsk'}))
        error('run_experiment:args', ['%s: [%s] sets min_pop_size, but %s keeps a fixed ' ...
              'population (only np_init applies)'], file, al.name, base);
    end
    a.min_pop_size = s.min_pop_size; s = rmfield(s, 'min_pop_size');
end
protected = {'seed', 'rand_generator', 'initial_population', 'rng_state_after_initialization', 'protocol', 'log_trace'};
allowed = alias_setting_names(base, root);
for f = fieldnames(s)'
    k = f{1};
    if any(strcmp(k, protected))
        error('run_experiment:args', ['%s: [%s] sets %s, which the runner controls ' ...
              '(seed, random generator, starting population, CEC protocol)'], file, al.name, k);
    end
    if ~any(strcmp(k, allowed))
        error('run_experiment:args', '%s: [%s] unknown setting %s for %s. Accepted: %s', ...
              file, al.name, k, base, strjoin([{'np_init'}, pop_names(base), allowed], ', '));
    end
end
a.optimizer = base;
a.name = al.name;
a.alias_settings = s;
a.alias_text = al.text;
a.alias_file = file;
fprintf('run_experiment: %s is an alias of %s from %s (%s)\n', a.name, base, file, ...
        ternary(isempty(al.text), 'no settings changed', al.text));
end

function tf = is_real_optimizer(name, root)
%IS_REAL_OPTIMIZER One of the seven, or a folder under src/optimizers.
tf = is_family_optimizer(name) || exist(fullfile(root, 'src', 'optimizers', name), 'dir') == 7;
end

function c = pop_names(base)
% Population settings an alias may set besides np_init.
if any(strcmp(base, {'gsk', 'egsk', 'atmals-gsk'})); c = {}; else; c = {'min_pop_size'}; end
end

function names = alias_setting_names(base, root)
%ALIAS_SETTING_NAMES Settings (other than np_init/min_pop_size) an alias may set.
% The seven list the options their code reads (see each optimizer's help
% text). For a user-added optimizer they are the names its main file reads
% from options (options.<name>, isfield(options,'<name>'),
% local_option(options,'<name>',...)).
switch base
    case 'gsk';        names = {'kf', 'kr', 'k', 'p'};
    case 'agsk';       names = {};
    case 'apgsk';      names = {};
    case 'fdb-agsk';   names = {'fdb_case'};
    case 'atmals-gsk'; names = {'kf_pool', 'kr_pool', 'k_pool', 'p_pool', 'pls_pool'};
    case 'egsk';       names = {'kf1', 'kf2', 'kr', 'k', 'use_fmincon'};
    case 'dt-gsk';     names = {};
    otherwise
        file = fullfile(root, 'src', 'optimizers', base, [strrep(base, '-', '_') '_optimize.m']);
        names = {};
        if isfile(file)
            txt = fileread(file);
            t1 = regexp(txt, 'options\.([A-Za-z]\w*)', 'tokens');
            t2 = regexp(txt, '(?:local_option|isfield)\(\s*options\s*,\s*''([A-Za-z]\w*)''', 'tokens');
            names = unique(lower([cellfun(@(c) c{1}, t1, 'UniformOutput', false), ...
                                  cellfun(@(c) c{1}, t2, 'UniformOutput', false)]));
        end
        names = setdiff(names, {'np', 'np_init', 'min_pop_size', 'seed', 'rand_generator', ...
                                'initial_population', 'rng_state_after_initialization', 'protocol', 'log_trace'});
end
end

function opts = add_alias_settings(opts, settings)
%ADD_ALIAS_SETTINGS Copy an alias's settings into one run's options struct.
for f = fieldnames(settings)'
    opts.(f{1}) = settings.(f{1});
end
end

function v = setting_or(settings, name, default)
% settings.(name) when set, else default.
if isfield(settings, name); v = settings.(name); else; v = default; end
end

function s = np_init_text(optimizer, np_init)
%NP_INIT_TEXT Initial population size label; equal labels mean equal runs.
if isempty(np_init) || (np_init == 100 && ~strcmp(optimizer, 'dt-gsk'))
    if strcmp(optimizer, 'dt-gsk'); s = '5*D (default)'; else; s = '100 (default)'; end
else
    s = sprintf('%d', np_init);
end
end

function tf = population_is_default(a, dim)
%POPULATION_IS_DEFAULT True when the run uses the optimizer's published
% population sizes: initial NP 100 (5*D for DT-GSK) and final NP 12 (DT-GSK:
% 12, or 25 for D >= 50). For DT-GSK, dim = 0 (native dimensions) with an
% override counts as not default.
is_dt = strcmp(a.optimizer, 'dt-gsk');
np_ok = isempty(a.np_init) || (~is_dt && a.np_init == 100) || ...
        (is_dt && dim > 0 && a.np_init == 5 * dim);
min_ok = isempty(a.min_pop_size) || ~uses_min_pop_size(a.optimizer) || ...
         (~is_dt && a.min_pop_size == 12) || ...
         (is_dt && dim > 0 && a.min_pop_size == ternary(dim >= 50, 25, 12));
tf = np_ok && min_ok;
end

function [override, generator] = previous_tree_config(summary_dir)
%PREVIOUS_TREE_CONFIG max_nfes override and effective generator recorded in the
% tree's run_config.json by the previous session (NaN / '' when unavailable).
override = NaN;
generator = '';
path = fullfile(summary_dir, 'run_config.json');
if ~isfile(path); return; end
try
    cfg = jsondecode(fileread(path));
    if isfield(cfg, 'max_nfes_override') && isnumeric(cfg.max_nfes_override)
        if isempty(cfg.max_nfes_override)
            override = 0;   % empty override = suite default budget
        elseif isscalar(cfg.max_nfes_override)
            override = double(cfg.max_nfes_override);
        end
    end
    if isfield(cfg, 'rand_generator') && ischar(cfg.rand_generator)
        generator = cfg.rand_generator;
    end
catch
end
end

function budget = legacy_cell_budget(suite, func_id, D, project_root, override)
%LEGACY_CELL_BUDGET Cell budget under a recorded max_nfes override (NaN if unknown).
budget = NaN;
if ~isfinite(override) || ~all(isfinite([func_id D])); return; end
if override > 0
    budget = override;
    return;
end
try
    p = gskcec_make_problem(suite, func_id, D, project_root, override);
    budget = p.max_nfes;
    free_problem(p);
catch
end
end

function m = load_latest_schedule_seeds(path)
%LOAD_LATEST_SCHEDULE_SEEDS Latest seed_schedule.csv seed per (Dim,Function,Run).
m = containers.Map('KeyType', 'char', 'ValueType', 'double');
if ~isfile(path); return; end
fid = fopen(path, 'r');
if fid < 0; return; end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fgetl(fid);   % header
data = textscan(fid, '%f%f%f%f', 'Delimiter', ',', 'CollectOutput', true);
rows = data{1};
for i = 1:size(rows, 1)
    if all(isfinite(rows(i, :)))
        m(schedule_key(rows(i, 1), rows(i, 2), rows(i, 3))) = rows(i, 4);
    end
end
end

function key = schedule_key(D, func_id, run)
key = sprintf('%d,%d,%d', D, func_id, run);
end

function archived_to = overwrite_output_tree(output_dir, project_root, session_tag)
%OVERWRITE_OUTPUT_TREE Move an existing run tree aside before a clean run.
% Overwrite deletes nothing: the old tree moves to
% <parent>/_overwrite_archive/<leaf>_<session_tag>[_<n>] and the output path
% starts fresh. Returns '' when output_dir does not exist. Refuses the
% project root and the reference tree (run_experiment:overwriteUnsafe);
% raises run_experiment:overwriteArchive if the move fails.
archived_to = '';
if ~exist(output_dir, 'dir')
    return;
end

out_abs = canonical_path(output_dir);
project_abs = canonical_path(project_root);
reference_abs = canonical_path(fullfile(project_root, 'benchmarks', 'cec_reference_results'));

assert(~same_path(out_abs, project_abs), ...
       'run_experiment:overwriteUnsafe', ...
       'Refusing to overwrite the project root: %s', out_abs);
assert(~is_path_within_or_equal(out_abs, reference_abs), ...
       'run_experiment:overwriteUnsafe', ...
       'Refusing to overwrite imported reference results: %s', out_abs);

[parent, leaf] = fileparts(out_abs);
assert(~isempty(parent) && ~isempty(leaf), ...
       'run_experiment:overwriteUnsafe', ...
       'Refusing to overwrite unsafe output path: %s', out_abs);

archive_root = fullfile(parent, '_overwrite_archive');
if ~exist(archive_root, 'dir'); mkdir(archive_root); end
archived_to = fullfile(archive_root, sprintf('%s_%s', leaf, session_tag));
n = 1;
while exist(archived_to, 'dir')
    archived_to = fullfile(archive_root, sprintf('%s_%s_%d', leaf, session_tag, n));
    n = n + 1;
end

[ok, msg] = movefile(out_abs, archived_to);
assert(ok, 'run_experiment:overwriteArchive', ...
       'Could not archive existing output tree %s -> %s (%s).', ...
       out_abs, archived_to, msg);
end

function assert_output_dir_outside_reference(output_dir, project_root)
%ASSERT_OUTPUT_DIR_OUTSIDE_REFERENCE Refuse an output_dir inside (or equal to)
% the imported reference tree benchmarks/cec_reference_results
% (run_experiment:outputUnsafe). Its tables are read-only evidence, and
% generated files there would break the C++ reference loader for every later
% verify/compare.
out_abs = canonical_path(output_dir);
reference_abs = canonical_path(fullfile(project_root, 'benchmarks', 'cec_reference_results'));
assert(~is_path_within_or_equal(out_abs, reference_abs), 'run_experiment:outputUnsafe', ...
       'Refusing to write generated results inside imported reference results: %s', out_abs);
end

function p = canonical_path(path)
% Canonical absolute path (the input as char if resolution fails). Relative
% paths resolve against MATLAB's pwd; java.io.File alone would use the JVM
% start directory, which differs after a cd.
p = char(string(path));
try
    f = java.io.File(p);
    if ~f.isAbsolute(); f = java.io.File(fullfile(pwd, p)); end
    p = char(f.getCanonicalPath());
catch
end
end

function tf = same_path(a, b)
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end
end

function tf = is_path_within_or_equal(child, parent)
if ispc
    child = lower(child);
    parent = lower(parent);
end
tf = strcmp(child, parent) || startsWith(child, [parent filesep]);
end

function records = empty_run_records()
records = struct('dim', {}, 'func', {}, 'run', {}, 'seed', {}, 'best', {}, 'error', {}, ...
                 'nfes', {}, 'max_nfes', {}, 'rand_generator', {});
end

function records = load_existing_per_run_records(summary_dir, optimizer, suite)
%LOAD_EXISTING_PER_RUN_RECORDS Read existing per-run rows for resume checks.
records = empty_run_records();
path = fullfile(summary_dir, 'per_run.csv');
if ~isfile(path); return; end
fid = fopen(path, 'r');
if fid < 0; return; end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
header = fgetl(fid); %#ok<NASGU>
while true
    line = fgetl(fid);
    if ~ischar(line); break; end
    if isempty(strtrim(line)); continue; end
    f = strsplit(line, ',', 'CollapseDelimiters', false);
    if numel(f) < 8; continue; end
    if ~strcmp(f{1}, optimizer) || ~strcmp(f{2}, suite); continue; end
    % Rows without the trailing max_nfes,rand_generator fields (old files
    % that could not be upgraded) stay readable; an unknown budget or
    % generator never matches, so such a run is re-run, not reused.
    rec = struct('dim', str2double(f{4}), ...
                 'func', str2double(f{3}), ...
                 'run', str2double(f{5}), ...
                 'seed', str2double(f{6}), ...
                 'best', str2double(f{7}), ...
                 'error', str2double(f{8}), ...
                 'nfes', NaN, 'max_nfes', NaN, 'rand_generator', '');
    if numel(f) >= 9; rec.nfes = str2double(f{9}); end
    if numel(f) >= 13
        rec.max_nfes = str2double(f{12});
        rec.rand_generator = strtrim(f{13});
    end
    if all(isfinite([rec.dim rec.func rec.run])) && (isfinite(rec.best) || isfinite(rec.error))
        records(end + 1) = rec; %#ok<AGROW>
    end
end
end

function out = records_for_cell(records, D, func_id)
if isempty(records)
    out = empty_run_records();
    return;
end
mask = [records.dim] == D & [records.func] == func_id;
out = records(mask);
end

function [kept, stale_runs] = keep_records_matching_current_seed(records, a, D, func_id, requested_runs, max_nfes, rand_gen)
%KEEP_RECORDS_MATCHING_CURRENT_SEED Reuse only rows matching today's schedule.
%
% A stored row counts as a completed run only when its seed equals
% pick_run_seed for the active configuration. Otherwise, after a change of
% seed policy or base_seed, a resumed run could skip run k just because some
% row exists. Results are append-only: stale rows stay in per_run.csv as
% history, their run ids are returned in stale_runs, and the run appends
% fresh rows for them.
%
% The seed formula has no budget or generator term, so the stored max_nfes
% and rand_generator must also equal this cell's budget (max_nfes) and the
% effective generator (rand_gen). Otherwise a reduced-budget smoke run, or a
% twister run resumed under threefry, would count as a completed run of the
% new configuration.
kept = empty_run_records();
stale_runs = [];
if isempty(records)
    return;
end
for i = 1:numel(records)
    r = records(i).run;
    if ~any(requested_runs == r)
        continue;
    end
    expected_seed = pick_run_seed(a, D, func_id, r);
    if seeds_equal(records(i).seed, expected_seed) && records(i).max_nfes == max_nfes && ...
            strcmpi(records(i).rand_generator, rand_gen)
        kept(end + 1) = records(i); %#ok<AGROW>
    else
        stale_runs(end + 1) = r; %#ok<AGROW>
    end
end
% A run that also has a matching row is reused, so it is not reported stale.
stale_runs = setdiff(unique(stale_runs), [kept.run]);
end

function tf = seeds_equal(a, b)
tf = isfinite(a) && isfinite(b) && abs(a - b) <= eps(max(1, abs(b))) * 8;
end

function [runs, values] = combine_existing_and_new_values(existing_records, runs_to_do, new_values, known_optimum, max_runs)
%COMBINE_EXISTING_AND_NEW_VALUES Values used for summary stats after resume.
runs = [];
values = [];
if ~isempty(existing_records)
    existing_run_ids = [existing_records.run];
    for r = 1:max_runs
        if any(runs_to_do == r)
            continue;
        end
        idx = find(existing_run_ids == r, 1, 'last');
        if isempty(idx)
            continue;
        end
        runs(end + 1, 1) = r; %#ok<AGROW>
        if known_optimum
            values(end + 1, 1) = existing_records(idx).error; %#ok<AGROW>
        else
            values(end + 1, 1) = existing_records(idx).best; %#ok<AGROW>
        end
    end
end
runs = [runs; runs_to_do(:)];
values = [values; new_values(:)];
[runs, order] = sort(runs);
values = values(order);
end

function [run_id, new_idx] = median_run_id(runs, values, runs_to_do)
%MEDIAN_RUN_ID Run nearest the combined median; new_idx is 0 if it is old.
m = median(values);
[~, idx] = min(abs(values - m));
run_id = runs(idx);
new_idx = find(runs_to_do == run_id, 1);
if isempty(new_idx); new_idx = 0; end
end

function stats = load_existing_summary_stats(summary_dir, optimizer, suite)
%LOAD_EXISTING_SUMMARY_STATS Existing per-dimension summaries for add mode.
stats = struct('func', {}, 'dim', {}, 'best', {}, 'median', {}, 'mean', {}, 'worst', {}, 'sd', {});
files = dir(fullfile(summary_dir, sprintf('%s_%s_D*.csv', optimizer, suite)));
for k = 1:numel(files)
    path = fullfile(files(k).folder, files(k).name);
    tok = regexp(files(k).name, '_D(\d+)\.csv$', 'tokens', 'once');
    if isempty(tok); continue; end
    D = str2double(tok{1});
    fid = fopen(path, 'r');
    if fid < 0; continue; end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    header = fgetl(fid); %#ok<NASGU>
    while true
        line = fgetl(fid);
        if ~ischar(line); break; end
        if isempty(strtrim(line)); continue; end
        f = strsplit(line, ',');
        if numel(f) < 6; continue; end
        row = struct('func', str2double(f{1}), 'dim', D, ...
                     'best', str2double(f{2}), 'median', str2double(f{3}), ...
                     'mean', str2double(f{4}), 'worst', str2double(f{5}), ...
                     'sd', str2double(f{6}));
        if isfinite(row.func)
            stats = upsert_stat(stats, row);
        end
    end
end
end

function stats = upsert_stat(stats, row)
if isempty(stats)
    stats = row;
    return;
end
mask = [stats.func] == row.func & [stats.dim] == row.dim;
if any(mask)
    stats(find(mask, 1, 'last')) = row;
else
    stats(end + 1) = row; %#ok<AGROW>
end
end

function row = stat_row_from_values(func_id, D, values, known_optimum, zero_tol)
cell_best = min(values); cell_median = median(values);
cell_mean = mean(values); cell_worst = max(values); cell_sd = std(values);
if known_optimum
    % CEC zero cutoff: a statistic with |x| < zero_tol (1e-8) is reported as
    % 0. Per-run values are stored at round-trip precision (%.17g in
    % per_run.csv, %.16e in the runs log), so a resumed summary matches an
    % uninterrupted run; the cutoff affects only the summary stats.
    zc = @(x) x * (abs(x) >= zero_tol);
    cell_best = zc(cell_best); cell_median = zc(cell_median);
    cell_mean = zc(cell_mean); cell_worst = zc(cell_worst); cell_sd = zc(cell_sd);
end
row = struct('func', func_id, 'dim', D, ...
             'best', cell_best, 'median', cell_median, ...
             'mean', cell_mean, 'worst', cell_worst, ...
             'sd', cell_sd);
end

% ---- per-cell artifact writers ---------------------------------------------

function write_checkpoint_errors(genlogs_dir, optimizer, func_id, D, checkpoints, run_ids, seeds, chk, session_tag, prefix)
% <prefix>_<optimizer>_F<f>_D<d>.csv: one row per run, columns
% Run,Seed,E<budget>..., the best-so-far error at each budget. The prefix is
% CheckpointErrors (the CEC checkpoints, default) or BestTrace (the optional
% trace_points budgets). Appends when the header matches; otherwise
% archives the file and rewrites.
if nargin < 10; prefix = 'CheckpointErrors'; end
path = fullfile(genlogs_dir, sprintf('%s_%s_F%d_D%d.csv', prefix, optimizer, func_id, D));
expected_header = sprintf('Run,Seed%s', sprintf(',E%d', checkpoints));
write_header = true;
mode = 'w';
if isfile(path)
    fid0 = fopen(path, 'r');
    first = '';
    if fid0 > 0
        first = strtrim(fgetl(fid0));
        fclose(fid0);
    end
    if strcmp(first, expected_header)
        write_header = false;
        mode = 'a';
    else
        archive_existing_file(path, session_tag);
    end
end
f = fopen(path, mode);
assert(f > 0, 'run_experiment:io', 'cannot open %s', path);
if write_header
    fprintf(f, '%s\n', expected_header);
end
for r = 1:size(chk, 1)
    fprintf(f, '%d,%s', run_ids(r), seed_to_text(seeds(r)));
    fprintf(f, ',%.16g', chk(r, :));
    fprintf(f, '\n');
end
fclose(f);
end

function fid = open_runs_log(summary_dir, a, dtag, stamp, known_optimum, func_list)
%OPEN_RUNS_LOG Open the detailed per-dimension runs log and write its header.
% File: summary/<opt>_<dtag>_runs_log_<stamp>.txt. Returns -1 on failure
% (logging is then off).
path = fullfile(summary_dir, sprintf('%s_%s_runs_log_%s.txt', a.name, dtag, stamp));
fid = fopen(path, 'w');
if fid < 0; return; end
bar = repmat('=', 1, 110);
fprintf(fid, '%s\n', bar);
fprintf(fid, 'DETAILED PER-RUN LOG   %s   %s   %s\n', upper(a.name), upper(a.suite), dtag);
fprintf(fid, 'runs per function : %d\n', a.runs);
fprintf(fid, 'functions         : %s\n', mat2str(func_list(:)'));
if known_optimum
    fprintf(fid, 'statistics basis  : error vs known optimum\n');
else
    fprintf(fid, 'statistics basis  : raw objective (no known optimum)\n');
end
fprintf(fid, 'generated         : %s\n', stamp);
fprintf(fid, '%s\n', bar);
end

function append_function_runs(fid, func_id, D, known_optimum, run_ids, seeds, best, errv, nfes, term, rt, problem, zero_tol)
%APPEND_FUNCTION_RUNS Append one function's per-run block to the runs log.
% Lists each run of this session, then the statistics of those runs (zero
% cutoff applied when the optimum is known). No-op when fid < 0.
if fid < 0; return; end
nr = numel(seeds);
fprintf(fid, '\n');
if isnan(problem.optimum)
    fprintf(fid, '----- F%d  %s  (%d runs)  [no known optimum] -----\n', func_id, dtag_for(D), nr);
else
    fprintf(fid, '----- F%d  %s  (%d runs)  optimum=%.10g  target_error=%g -----\n', ...
            func_id, dtag_for(D), nr, problem.optimum, problem.target_error);
end
fprintf(fid, '%-5s  %-12s  %-23s  %-23s  %-12s  %-22s  %-11s\n', ...
        'Run', 'Seed', 'Best_Fitness', 'Error', 'NFEs', 'Termination', 'Runtime_s');
for r = 1:nr
    fprintf(fid, '%-5d  %-12s  %-23.16e  %-23.16e  %-12d  %-22s  %-11.4f\n', ...
            run_ids(r), seed_to_text(seeds(r)), best(r), errv(r), nfes(r), term{r}, rt(r));
end
if known_optimum; stat = errv; lbl = 'error'; else; stat = best; lbl = 'objective'; end
sb = min(stat); sm = median(stat); su = mean(stat); sw = max(stat); ss = std(stat);
if known_optimum
    % CEC zero cutoff, as in the summary table and reference protocol.
    zc = @(x) x * (abs(x) >= zero_tol);
    sb = zc(sb); sm = zc(sm); su = zc(su); sw = zc(sw); ss = zc(ss);
end
fprintf(fid, 'stats(%s): best=%.16e  median=%.16e  mean=%.16e  worst=%.16e  sd=%.16e\n', ...
        lbl, sb, sm, su, sw, ss);
end

function s = dtag_for(D)
%DTAG_FOR Dimension label 'D<D>'; native-dim suites pass the actual problem D.
s = sprintf('D%d', D);
end

function close_runs_log(fid)
%CLOSE_RUNS_LOG Close the per-dimension runs log (no-op if it never opened).
if fid >= 0; fclose(fid); end
end

function write_curve(curves_dir, func_id, D, run, nfes, err, session_tag)
% Figure_F<f>_D<d>_Run#<r>.csv: the chosen run's convergence trace
% (Eval,BestError,Log10Error). An existing file is archived first.
path = fullfile(curves_dir, sprintf('Figure_F%d_D%d_Run#%d.csv', func_id, D, run));
archive_existing_file(path, session_tag);
f = fopen(path, 'w');
assert(f > 0, 'run_experiment:io', 'cannot open %s', path);
fprintf(f, 'Eval,BestError,Log10Error\n');
for i = 1:numel(nfes)
    if err(i) > 0
        fprintf(f, '%d,%.16e,%.16e\n', nfes(i), err(i), log10(err(i)));
    else
        fprintf(f, '%d,%.16e,\n', nfes(i), err(i));   % log10 undefined for <= 0
    end
end
fclose(f);
end

function [n_moved, has_trace] = keep_only_median_curve(curves_dir, graphs_dir, func_id, D, keep_run, keep_value, will_write, session_tag)
%KEEP_ONLY_MEDIAN_CURVE Leave at most one median-run curve per cell.
% After a resume the median is re-chosen over old + new runs, so curves from
% earlier sessions for other run ids are moved (archive copy, then delete) to
% curves/_archive/<session_tag>/. A stored curve for the median run id is
% kept only if it ends at that run's final value (keep_value); a curve from a
% stale row of the same run id (other seed, budget or generator) is moved
% too. n_moved counts the moved curves. has_trace says whether the median
% run's curve exists or is about to be written (will_write). When a curve was
% moved or the trace is missing, the cell's graph PNG came from another run
% and is archived the same way; it is re-rendered from the median trace when
% write_graphs is on.
n_moved = 0;
L = dir(fullfile(curves_dir, sprintf('Figure_F%d_D%d_Run#*.csv', func_id, D)));
for k = 1:numel(L)
    tok = regexp(L(k).name, '_Run#(\d+)\.csv$', 'tokens', 'once');
    if isempty(tok) || str2double(tok{1}) == keep_run; continue; end
    n_moved = n_moved + move_to_archive(fullfile(L(k).folder, L(k).name), session_tag);
end
keep_path = fullfile(curves_dir, sprintf('Figure_F%d_D%d_Run#%d.csv', func_id, D, keep_run));
has_trace = will_write || isfile(keep_path);
if ~will_write && has_trace
    [~, y] = read_curve(curves_dir, func_id, D, keep_run);
    % Final curve value vs the run's statistic: the tolerance covers the 1e-8
    % zero cut and older per_run.csv rows rounded to 11 digits (not %.17g).
    if isempty(y) || ~(abs(y(end) - keep_value) <= max(1e-8, 1e-9 * abs(keep_value)))
        n_moved = n_moved + move_to_archive(keep_path, session_tag);
        has_trace = false;
    end
end
if n_moved > 0 || ~has_trace
    move_to_archive(fullfile(graphs_dir, sprintf('Figure_F%d_D%d.png', func_id, D)), session_tag);
end
end

function moved = move_to_archive(path, session_tag)
%MOVE_TO_ARCHIVE Archive a superseded file, then remove it from the active tree.
moved = false;
if ~isfile(path); return; end
if archive_existing_file(path, session_tag)
    delete(path);
    moved = true;
end
end

function [x, y] = read_curve(curves_dir, func_id, D, run)
%READ_CURVE Stored curve (Eval, BestError) of an earlier run; empty if absent.
x = [];
y = [];
fid = fopen(fullfile(curves_dir, sprintf('Figure_F%d_D%d_Run#%d.csv', func_id, D, run)), 'r');
if fid < 0; return; end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fgetl(fid);   % header
data = textscan(fid, '%f%f%*[^\n]', 'Delimiter', ',');
x = data{1};
y = data{2};
end

function s = missing_curve_message(suite, func_id, D, run)
s = sprintf(['RESUME %s f%d D%d: median run %d was reused from an earlier session ' ...
             'whose curve was not stored; no curve/graph for this cell'], suite, func_id, D, run);
end

function write_summary_files(summary_dir, optimizer, suite, stats, known_optimum, session_tag, dims, rollup)
% Write the per-dimension summary tables (Function,Best,Median,Mean,Worst,SD)
% for dims (default: every dimension in stats). When rollup is true
% (default), also write the dimensionless rollup <optimizer>_<suite>.csv for
% native-dim suites (CEC2011, CEC2013-LSGO).
if isempty(stats); return; end
if nargin < 7; dims = unique([stats.dim]); end
if nargin < 8; rollup = true; end
for d = dims(:)'
    sel = stats([stats.dim] == d);
    if isempty(sel); continue; end
    write_summary_table(fullfile(summary_dir, sprintf('%s_%s_D%d.csv', optimizer, suite, d)), sel, session_tag);
end
if rollup && ~known_optimum
    write_summary_table(fullfile(summary_dir, sprintf('%s_%s.csv', optimizer, suite)), stats, session_tag);
end
end

function write_summary_table(path, rows, session_tag)
% Write rows sorted by function; an existing file is archived first.
[~, order] = sort([rows.func]);
rows = rows(order);
archive_existing_file(path, session_tag);
f = fopen(path, 'w');
assert(f > 0, 'run_experiment:io', 'cannot open %s', path);
fprintf(f, 'Function,Best,Median,Mean,Worst,SD\n');
for i = 1:numel(rows)
    fprintf(f, '%d,%.10E,%.10E,%.10E,%.10E,%.10E\n', rows(i).func, rows(i).best, ...
            rows(i).median, rows(i).mean, rows(i).worst, rows(i).sd);
end
fclose(f);
end

function write_environment(summary_dir, a, stats, skipped, notes, known_optimum, fracs, runtime, session_tag)
% Write summary/environment.json: settings, seed scheme, platform, git commit,
% runtime, skipped cells and optimizer notes. The old file is archived first.
env = struct();
env.optimizer = a.name;
env.base_optimizer = a.optimizer;   % differs from optimizer for an algorithms.ini alias
env.alias_settings = a.alias_text;  % its settings ('' = none or not an alias)
env.aliases_file = a.alias_file;    % the file it came from ('' = not an alias)
env.suite = a.suite;
env.functions = a.functions(:)';
env.dimensions_requested = a.dimensions(:)';
env.dimensions_run = unique([stats.dim]);
env.runs = a.runs;
env.base_seed = a.base_seed;
env.overwrite = logical(a.overwrite);
env.overwrite_archived_to = a.overwrite_archived_to;
env.use_parallel = logical(a.use_parallel);
env.write_graphs = logical(a.write_graphs);
env.rand_generator = char(effective_rand_generator(a));
% Report the scheme of the active policy. seed_scheme_string is the single
% source of truth, so environment.json agrees with run_config.json and the
% seeds actually used. Its text starts with its own label ('unified: ...');
% drop that so the field reads '<seed_policy>: <scheme>' without a doubled
% prefix.
env.seed_policy = [char(a.seed_policy) ': ' ...
                   regexprep(seed_scheme_string(a), '^[^:]+:\s*', '', 'once')];
env.initial_population_policy = initial_population_policy_string(a);
env.max_nfes_override = a.max_nfes;
% Population overrides ([] = default; min_pop_size [] where the optimizer
% ignores it). gsk_validate --verify treats a set value as a reduced protocol.
env.np_init = a.np_init;
env.min_pop_size = ternary(uses_min_pop_size(a.optimizer), a.min_pop_size, []);
env.statistics_basis = ternary(known_optimum, 'error_vs_optimum', 'raw_objective');
env.report_zero_tol = report_zero_tol(a);
env.optimizer_options = optimizer_options_metadata(a.optimizer, a.suite);
env.checkpoint_fractions = fracs;
env.trace_points = a.trace_points;   % 0 = no BestTrace_*.csv
env.log_trace = logical(a.log_trace);   % true = trace/Dynamics_*.csv written
env.data_root = fullfile(a.project_root, 'benchmarks', 'cec_suite_cpp', a.suite, 'input_data');
env.reference_root = fullfile(a.project_root, 'benchmarks', 'cec_reference_results');
env.output_dir = a.output_dir;
env.matlab_version = version;
env.cpu_cores = feature('numcores');
env.computer = computer;
env.platform = char(java.lang.System.getProperty('os.name'));
env.git_commit = git_commit_or_empty(a.project_root);
env.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
env.runtime_seconds_total = runtime;
env.skipped_cells = skipped;
env.optimizer_notes = unique(notes);
env.command = build_command_string(a);
path = fullfile(summary_dir, 'environment.json');
archive_existing_file(path, session_tag);
fid = fopen(path, 'w');
assert(fid > 0, 'run_experiment:io', 'cannot open environment.json');
fprintf(fid, '%s\n', jsonencode(env, 'PrettyPrint', true));
fclose(fid);
end

% ---- helpers ----------------------------------------------------------------

function v = curve_value(best_fitness, optimum, optimizer, suite)
% The plotted/checkpointed quantity: error vs optimum when known, else the
% raw objective. ATMALS-GSK on CEC2017 uses abs(best - optimum), as its
% reference driver does.
if isnan(optimum)
    v = best_fitness;
elseif uses_atmals_cec2017_reference_reporting(optimizer, suite)
    v = abs(best_fitness - optimum);
else
    v = best_fitness - optimum;
end
end

function opts = optimizer_run_options(optimizer, suite, seed, rand_gen, np_init, min_pop_size)
%OPTIMIZER_RUN_OPTIONS Build the per-run optimizer options (seed, generator).
% Does not touch the seed schedule. ATMALS-GSK has two historical drivers;
% pick the matching protocol for its two published suites (CEC2011, CEC2017).
% eGSK runs with use_fmincon = true. A non-empty np_init (checked at argument
% parsing) is passed under each optimizer's own option name; a non-empty
% min_pop_size only to the optimizers that read it. A user-added optimizer
% (not one of the seven) gets np_init as both options.np and options.np_init,
% and min_pop_size as given, so a copy of any family member reads them.
opts = struct('seed', seed, 'rand_generator', rand_gen);
user_added = ~is_family_optimizer(optimizer);
if ~isempty(np_init)
    if any(strcmp(optimizer, {'gsk', 'egsk', 'atmals-gsk'}))
        opts.np = np_init;
    elseif user_added
        opts.np = np_init;
        opts.np_init = np_init;
    else
        opts.np_init = np_init;
    end
end
if ~isempty(min_pop_size) && (uses_min_pop_size(optimizer) || user_added)
    opts.min_pop_size = min_pop_size;
end
% A user-added optimizer also gets the protocol, so a copy of ATMALS-GSK
% keeps its CEC2011 driver; an optimizer that does not read it ignores it.
if strcmp(optimizer, 'atmals-gsk') || user_added
    if strcmp(suite, 'cec2011')
        opts.protocol = 'cec2011';
    elseif strcmp(suite, 'cec2017')
        opts.protocol = 'cec2017';
    end
elseif strcmp(optimizer, 'egsk')
    opts.use_fmincon = true;
end
end

function tf = unified_initialization_enabled(a)
%UNIFIED_INITIALIZATION_ENABLED Strict fair-start mode for cross-family runs.
% Only unified mode supplies a runner-owned X0. Reference/native/derived keep
% each optimizer's original initialization draw order, so published-table
% reproduction and RNG diagnostics are unchanged. DT-GSK initializes from its
% own 'init' stream, so no runner X0 is drawn for it.
tf = strcmpi(char(a.seed_policy), 'unified') && ~is_unified_only(a.optimizer);
end

function [x0, rng_after_x0] = make_unified_initial_population(problem, seed, rng_generator, np_init)
%MAKE_UNIFIED_INITIAL_POPULATION Draw the fair shared X0 for one CEC run.
%
% Seeds the global RNG with (seed, rng_generator), draws X0 (NP x D) within
% the problem bounds and returns it with the RNG state right after the draw.
% The seed is the same for every optimizer at a given (D,function,run); each
% optimizer restores rng_after_x0, so its later draws start from the same
% point.
%
% NP = 100 is the runner/interface default of every GSK-family optimizer that
% takes a runner X0; a non-empty np_init (the runner's 'np_init') replaces it,
% and the optimizers are given the same NP. DT-GSK is the exception: it samples
% its own initial population and ignores X0, so this helper is not called for
% it (with the same NP, its own draw equals this X0). The seed formula must
% stay independent of NP.
np = 100;
if ~isempty(np_init)
    np = np_init;
end
rng(seed, rng_generator);
x0 = gsk_init_population(np, problem.lb, problem.ub);
rng_after_x0 = rng;
end

function meta = optimizer_options_metadata(optimizer, suite)
%OPTIMIZER_OPTIONS_METADATA Options the runner adds beyond seed/generator.
meta = struct();
if strcmp(optimizer, 'atmals-gsk') || ~is_family_optimizer(optimizer)
    if strcmp(suite, 'cec2011')
        meta.protocol = 'cec2011';
    elseif strcmp(suite, 'cec2017')
        meta.protocol = 'cec2017';
    end
elseif strcmp(optimizer, 'egsk')
    meta.use_fmincon = true;
end
end

function tf = uses_atmals_cec2017_reference_reporting(optimizer, suite)
%USES_ATMALS_CEC2017_REFERENCE_REPORTING The ATMALS-GSK CEC2017 driver reports
% abs(best - optimum). The zero cutoff is still the project-wide 1e-8.
tf = strcmp(optimizer, 'atmals-gsk') && strcmp(suite, 'cec2017');
end

function zt = report_zero_tol(a)
%REPORT_ZERO_TOL Reporting-only zero cutoff; does not affect seeds or search.
zt = 1e-8;
end

function e = checkpoint_errors(conv_nfes, conv_err, checkpoints)
% Best-so-far value at each checkpoint: the recorded value at the last
% generation with nfes <= checkpoint (the trace is monotone best-so-far).
% Before the first record, use the first value. Callers clip conv_nfes at
% max_nfes, so a final counter past the budget (FDB-AGSK/eGSK max_nfes+1, the
% eGSK IP overshoot) folds into the last checkpoint and E<max_nfes> equals
% the per-run final error. The curves and optimizer counters are unchanged.
e = zeros(1, numel(checkpoints));
for c = 1:numel(checkpoints)
    idx = find(conv_nfes <= checkpoints(c), 1, 'last');
    if isempty(idx); idx = 1; end
    e(c) = conv_err(idx);
end
end

function write_dynamics_trace(trace_dir, name, func_id, D, run_ids, dyn, max_rows, session_tag)
% trace/Dynamics_<name>_F<f>_D<d>.csv: the opt-in per-generation trace of
% every new run (Run, Gen, then the optimizer's trace columns: nfes, np,
% diversity and its own parameters), thinned to at most max_rows evenly
% spaced generations per run (the first and the last kept). Appends when the
% header matches; otherwise archives the file and rewrites it.
have = find(~cellfun('isempty', dyn));
if isempty(have); return; end
if ~exist(trace_dir, 'dir'); mkdir(trace_dir); end
names = dyn{have(1)}.names;
header = strjoin([{'Run', 'Gen'}, names], ',');
path = fullfile(trace_dir, sprintf('Dynamics_%s_F%d_D%d.csv', name, func_id, D));
mode = 'w';
if isfile(path)
    fid0 = fopen(path, 'r'); first = strtrim(fgetl(fid0)); fclose(fid0);
    if strcmp(first, header); mode = 'a'; else; archive_existing_file(path, session_tag); end
end
f = fopen(path, mode);
assert(f > 0, 'run_experiment:io', 'cannot open %s', path);
if strcmp(mode, 'w'); fprintf(f, '%s\n', header); end
for r = have(:)'
    rows = dyn{r}.rows;
    g = unique(round(linspace(1, size(rows, 1), min(size(rows, 1), max_rows))));
    for k = g
        fprintf(f, '%d,%d', run_ids(r), k - 1);
        fprintf(f, ',%.10g', rows(k, :));
        fprintf(f, '\n');
    end
end
fclose(f);
end

function b = trace_budgets(max_nfes, n)
% n log-spaced budgets from 1 to max_nfes (rounded, unique) for the
% optional BestTrace_*.csv files.
b = unique(round(logspace(0, log10(max_nfes), n)));
end

function idx = median_run_index(values)
% Index of the run nearest the median final value (the representative curve).
m = median(values);
[~, idx] = min(abs(values - m));
end

function out = ternary(cond, a, b)
if cond; out = a; else; out = b; end
end

function seed = pick_run_seed(a, D, func, run)
%PICK_RUN_SEED Per-run seed for the selected policy (details: docs/reference/seed_policy.md).
%   'reference' : per-optimizer reproduction --
%                   gsk, egsk, atmals-gsk  -> base_seed + 9973*func + (run-1)
%                   agsk, apgsk, fdb-agsk  -> dim*func*run
%                   other                  -> get_cec_seed(base_seed, dim, func, run)
%   'unified'   : get_cec_seed(base_seed, dim, func, run), independent of optimizer.
%   other       : derive_run_seed hash (native/derived diagnostics).
%   Unified-only optimizers (dt-gsk) use get_cec_seed under EVERY policy.
%
% Never add optimizer name or index, population size, max_nfes, suite name or
% alg_code to the unified branch. Those belong only to reference reproduction
% (where historical drivers differed) or to the hashed diagnostic policy in
% derive_run_seed.
if is_unified_only(a.optimizer)
    seed = get_cec_seed(a.base_seed, D, func, run);
    return;
end
switch lower(char(a.seed_policy))
    case 'reference'
        switch a.optimizer
            case {'gsk'}
                seed = a.base_seed + 9973 * func + (run - 1);
            case {'agsk', 'apgsk', 'fdb-agsk'}
                seed = D * func * run;
            case {'egsk'}
                seed = a.base_seed + 9973 * func + (run - 1);
            case {'atmals-gsk'}
                seed = a.base_seed + 9973 * func + (run - 1);
            otherwise
                seed = get_cec_seed(a.base_seed, D, func, run);
        end
    case 'unified'
        seed = get_cec_seed(a.base_seed, D, func, run);
    otherwise
        seed = derive_run_seed(a.base_seed, a.optimizer, a.suite, D, func, run);
end
end

function g = effective_rand_generator(a)
%EFFECTIVE_RAND_GENERATOR RNG family used by the optimizer.
%   reference      -> each optimizer's documented reference family
%   unified        -> the resolved CEC generator (threefry when available,
%                     else twister), for fair cross-family studies
%   native/derived -> a.rand_generator as given, for diagnostics
% Unified-only optimizers (dt-gsk) always use threefry.
if is_unified_only(a.optimizer)
    g = 'threefry';
    return;
end
switch lower(char(a.seed_policy))
    case 'reference'
        opt = lower(char(a.optimizer));
        if any(strcmp(opt, {'agsk', 'apgsk', 'fdb-agsk', 'egsk', 'atmals-gsk'}))
            g = 'seed';
        else
            g = 'twister';
        end
    case 'unified'
        g = resolve_unified_rng_generator(char(a.rand_generator));
    otherwise
        g = char(a.rand_generator);
end
end

function tf = is_unified_only(optimizer)
%IS_UNIFIED_ONLY Optimizers whose reference protocol IS the unified schedule.
% DT-GSK (on the reference implementation's list of unified-only optimizers)
% gets get_cec_seed + threefry under every seed_policy, because its reference
% campaign was produced that way. From the run seed it creates 9 Threefry
% streams: 'init' uses the seed itself; each of the 8 others, at its fixed
% position k in a 13-position layout, gets mod(seed + 1000003*(k+1),
% 2147483646) + 1, so the layout fixes every child seed. It draws its own
% initial population (documented fair-start exception).
tf = strcmp(optimizer, 'dt-gsk');
end

function g = resolve_unified_rng_generator(requested)
%RESOLVE_UNIFIED_RNG_GENERATOR Actual generator for unified CEC mode.
% The unified protocol allows only schedule-independent MATLAB generators.
% threefry/auto/default (or empty) probe MATLAB support and fall back to
% twister (choose_cec_rng_generator). Legacy seed/state requests are treated
% the same way: they are compatibility diagnostics, not fair CEC generators.
requested = lower(strtrim(requested));
if isempty(requested) || any(strcmp(requested, {'auto', 'default', 'threefry'}))
    g = choose_cec_rng_generator();
elseif strcmp(requested, 'twister')
    g = 'twister';
else
    g = choose_cec_rng_generator();
end
end

function setup_paths(project_root)
% Add the toolkit's source, optimizer and build/mex folders to the path.
addpath(fullfile(project_root, 'src', 'common'));
addpath(fullfile(project_root, 'src', 'runners'));
addpath(fullfile(project_root, 'src', 'experiments'));
opt_root = fullfile(project_root, 'src', 'optimizers');
d = dir(opt_root);
for k = 1:numel(d)
    if d(k).isdir && d(k).name(1) ~= '.'
        addpath(fullfile(opt_root, d(k).name));
    end
end
mex_dir = fullfile(project_root, 'build', 'mex');
if exist(mex_dir, 'dir'); addpath(mex_dir); end
end

function free_problem(p)
%FREE_PROBLEM Release a problem's MEX handle (no-op for the pure-MATLAB
% sphere test problem, which has no handle).
if isfield(p, 'mex_handle'); gskcec_eval('free', p.mex_handle); end
end

function ensure_process_pool()
%ENSURE_PROCESS_POOL Make sure a PROCESS-based parallel pool backs the parfor
% run loop. The gskcec_eval MEX keeps a process-local, non-thread-safe handle
% registry: a thread-based pool would race on it (and cannot addpath), while
% a process pool gives each worker its own MEX instance. An open thread pool
% is replaced. Without the Parallel Computing Toolbox, or if pool creation
% fails, nothing is started and the parfor runs serially.
if ~license('test', 'Distrib_Computing_Toolbox'); return; end
pool = gcp('nocreate');
if ~isempty(pool) && ~isa(pool, 'parallel.ProcessPool')
    delete(pool);            % replace a thread-based pool
    pool = [];
end
if ~isempty(pool); return; end   % a usable process pool already exists
% Size the pool to the physical core count. The default 'Processes' profile is
% often capped lower (e.g. 6 on a 16-core host), so raise NumWorkers on the
% in-memory cluster object only (no saveProfile; the saved profile is
% untouched). Fall back to the profile default, then to a serial parfor.
n = feature('numcores');
try
    c = parcluster('Processes');
    if c.NumWorkers < n; c.NumWorkers = n; end
    parpool(c, n);
    return;
catch
end
try
    parpool('Processes');
catch
    % Pool unavailable -> the parfor degrades to a serial loop (still correct).
end
end

function setup_paths_once(project_root)
%SETUP_PATHS_ONCE Run setup_paths once per process lifetime.
% A persistent flag skips the addpath work on later parfor iterations.
persistent configured
if isempty(configured)
    setup_paths(project_root);
    configured = true;
end
end

function cmd = build_command_string(a)
% Equivalent run_experiment call for environment.json, with the effective
% rand_generator.
cmd = sprintf(['run_experiment(''optimizer'',''%s'',''suite'',''%s'',''functions'',%s,' ...
               '''dimensions'',%s,''runs'',%d,''base_seed'',%d,''max_nfes'',%d,' ...
               '''project_root'',''%s'',''output_dir'',''%s'',''overwrite'',%s,' ...
               '''verbose'',%s,''seed_policy'',''%s'',''rand_generator'',''%s'',' ...
               '''use_parallel'',%s,''write_graphs'',%s)'], ...
              a.name, a.suite, mat2str(a.functions(:)'), mat2str(a.dimensions(:)'), ...
              a.runs, a.base_seed, a.max_nfes, a.project_root, a.output_dir, ...
              string(logical(a.overwrite)), string(logical(a.verbose)), char(a.seed_policy), ...
              char(effective_rand_generator(a)), string(logical(a.use_parallel)), ...
              string(logical(a.write_graphs)));
end

function commit = git_commit_or_empty(project_root)
% HEAD commit of project_root, or '' when git is unavailable or fails.
commit = '';
try
    [status, out] = system(sprintf('git -C "%s" rev-parse HEAD', project_root));
    if status == 0; commit = strtrim(out); end
catch
end
end

% ---- console formatting (banner + per-dimension results table) -------------

function print_detailed_config(a, known_optimum, func_list, excluded)
bar = repmat('=', 1, 72);
fprintf('\n%s\nDETAILED CONFIGURATION\n%s\n', bar, bar);
fprintf('%-16s: %s\n', 'optimizer', a.optimizer);
fprintf('%-16s: %s\n', 'suite', upper(a.suite));
fprintf('%-16s: %s\n', 'funcs_to_run', mat2str(func_list));
if ~isempty(excluded)
    fprintf('%-16s: %s\n', 'excluded', mat2str(excluded));
end
fprintf('%-16s: %s\n', 'dimensions', mat2str(a.dimensions(:)'));
fprintf('%-16s: %d\n', 'runs', a.runs);
fprintf('%-16s: %d\n', 'base_seed', a.base_seed);
fprintf('%-16s: %s\n', 'seed_policy', char(a.seed_policy));
fprintf('%-16s: %s\n', 'rand_generator', char(effective_rand_generator(a)));
fprintf('%-16s: %s\n', 'overwrite', char(string(logical(a.overwrite))));
opt_meta = optimizer_options_metadata(a.optimizer, a.suite);
if isfield(opt_meta, 'protocol')
    fprintf('%-16s: %s\n', 'protocol', opt_meta.protocol);
end
fprintf('%-16s: %s\n', 'use_parallel', char(string(logical(a.use_parallel))));
fprintf('%-16s: %s\n', 'write_graphs', char(string(logical(a.write_graphs))));
if a.max_nfes > 0
    fprintf('%-16s: %d (override)\n', 'max_nfes', a.max_nfes);
else
    fprintf('%-16s: %s\n', 'max_nfes', 'suite default (e.g. 10000*D for cec2017)');
end
fprintf('%-16s: %s\n', 'statistics', ternary(known_optimum, 'error vs known optimum', 'raw objective'));
fprintf('%-16s: %s\n', 'project_root', a.project_root);
fprintf('%-16s: %s\n', 'output_dir', a.output_dir);
fprintf('%s\n', bar);
end

function print_run_banner(a, D, nfuncs, problem)
% Fixed-width banner box summarising the run for this dimension.
W = 56;
rule = ['+' repmat('-', 1, W + 2) '+'];
native = any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));   % per-problem dims/bounds
if isnan(problem.target_error)
    terr = 'n/a';
else
    terr = sprintf('%.0e', problem.target_error);
end
if native; dlabel = 'native'; else; dlabel = sprintf('%d', D); end
fprintf('\n%s\n', rule);
fprintf('| %-*s |\n', W, sprintf('%s - %s - D=%s', a.name, upper(a.suite), dlabel));
fprintf('%s\n', rule);
fprintf('| %-*s |\n', W, sprintf('%d functions x %d runs | Budget: %s NFEs', ...
        nfuncs, a.runs, with_commas(problem.max_nfes)));
params = optimizer_banner_params(a.optimizer);
if ~isempty(params)
    fprintf('| %-*s |\n', W, params);
end
if native
    fprintf('| %-*s |\n', W, sprintf('Bounds: per-problem   Target: %s', terr));
else
    fprintf('| %-*s |\n', W, sprintf('Bounds: (%.1f, %.1f)   Target error: %s', ...
            min(problem.lb), max(problem.ub), terr));
end
fprintf('%s\n', rule);
end

function print_table_header()
[func_w, val_w, time_w] = results_table_widths();
rule = results_table_rule();
fprintf('\n%s\n', rule);
fprintf('|%s|%s|%s|%s|%s|%s|%s|\n', ...
    center('Func', func_w), center('Best', val_w), center('Median', val_w), ...
    center('Mean', val_w), center('Worst', val_w), center('SD', val_w), ...
    center('Time/s', time_w));
fprintf('%s\n', rule);
end

function print_table_row(func_id, best, med, mn, wrst, sd, t)
[func_w, ~, ~] = results_table_widths();
fprintf('|%s|%s|%s|%s|%s|%s|%s|\n', ...
        center(sprintf('F%02d', func_id), func_w), ...
        results_value_cell(best), results_value_cell(med), ...
        results_value_cell(mn), results_value_cell(wrst), ...
        results_value_cell(sd), results_time_cell(t));
end

function print_table_skip_row(func_id)
[func_w, val_w, time_w] = results_table_widths();
fprintf('|%s|%s|%s|%s|%s|%s|%s|\n', center(sprintf('F%02d', func_id), func_w), ...
        center('SKIPPED', val_w), center('--', val_w), center('--', val_w), ...
        center('--', val_w), center('--', val_w), center('--', time_w));
end

function print_table_footer()
fprintf('%s\n', results_table_rule());
end

function [func_w, val_w, time_w] = results_table_widths()
% Console table column widths; value cells fit negative CEC2011 raw objectives.
func_w = 8;
val_w = 14;   % two margins + a 10-character %.2E field
time_w = 13;  % two margins + an 8-character %.1f field + "s"
end

function rule = results_table_rule()
[func_w, val_w, time_w] = results_table_widths();
rule = ['+' repmat('-', 1, func_w) '+'];
for k = 1:5
    rule = [rule repmat('-', 1, val_w) '+']; %#ok<AGROW>
end
rule = [rule repmat('-', 1, time_w) '+'];
end

function s = results_value_cell(x)
s = sprintf('  %10.2E  ', x);
end

function s = results_time_cell(t)
s = sprintf('  %8.1fs  ', t);
end

function print_resume_messages(messages)
% Print resume notes; "already present" cells are grouped per (suite, D, runs).
if isempty(messages); return; end
fprintf('\nResume notes:\n');
groups = struct('key', {}, 'suite', {}, 'dim', {}, 'runs', {}, 'funcs', {});
other = {};
for i = 1:numel(messages)
    tok = regexp(messages{i}, '^RESUME (\S+) f(\d+) D(\d+): runs 1:(\d+) already present; skipping cell$', ...
        'tokens', 'once');
    if isempty(tok)
        other{end + 1} = messages{i}; %#ok<AGROW>
        continue;
    end
    key = sprintf('%s|%s|%s', tok{1}, tok{3}, tok{4});
    idx = find(strcmp({groups.key}, key), 1);
    if isempty(idx)
        groups(end + 1) = struct('key', key, 'suite', tok{1}, ...
            'dim', str2double(tok{3}), 'runs', str2double(tok{4}), ...
            'funcs', str2double(tok{2})); %#ok<AGROW>
    else
        groups(idx).funcs(end + 1) = str2double(tok{2});
    end
end
for i = 1:numel(groups)
    funcs = sort(groups(i).funcs);
    fprintf('  - RESUME %s D%d: %d function(s) already complete (runs 1:%d): %s\n', ...
        groups(i).suite, groups(i).dim, numel(funcs), groups(i).runs, mat2str(funcs));
end
for i = 1:numel(other)
    fprintf('  - %s\n', other{i});
end
end

function print_skip_messages(messages)
if isempty(messages); return; end
fprintf('\nSkipped cells:\n');
for i = 1:numel(messages)
    fprintf('  - %s\n', messages{i});
end
end

function s = run_list_text(runs)
% Compact run list for console messages, e.g. [1:3 7 10:12]; more than 20
% runs also get a count.
runs = unique(runs(:)');
if isempty(runs)
    s = '[]';
    return;
end
parts = {};
start_run = runs(1);
prev_run = runs(1);
for i = 2:numel(runs)
    if runs(i) == prev_run + 1
        prev_run = runs(i);
    else
        parts{end + 1} = run_range_text(start_run, prev_run); %#ok<AGROW>
        start_run = runs(i);
        prev_run = runs(i);
    end
end
parts{end + 1} = run_range_text(start_run, prev_run);
s = ['[' strjoin(parts, ' ') ']'];
if numel(runs) > 20
    s = sprintf('%s (%d runs)', s, numel(runs));
end
end

function s = run_range_text(a, b)
if a == b
    s = sprintf('%d', a);
else
    s = sprintf('%d:%d', a, b);
end
end

function s = with_commas(n)
% Group an integer with thousands separators: 1000000 -> '1,000,000'.
s = sprintf('%d', round(n));
s = regexprep(s, '\d(?=(\d{3})+$)', '$0,');
end

function s = seed_to_text(seed)
% Seed as text for CSV/log output: integer seeds exactly (%.0f), others %.15g.
if isfinite(seed) && abs(seed - round(seed)) <= eps(max(1, abs(seed))) * 8
    s = sprintf('%.0f', seed);
else
    s = sprintf('%.15g', seed);
end
end

function s = optimizer_banner_params(name)
% Short hyperparameter line for the banner: only values the run actually uses
% (the optimizer's reference defaults).
switch name
    case 'gsk'
        s = 'Pop=100  KF=0.5 KR=0.9 K=10 P=0.1';
    case 'dt-gsk'
        s = 'Pop=5*D  pub profile (dimension-tiered)';
    otherwise
        s = '';   % adaptive variants set parameters at run time; left blank
end
end

function r = ref_name(optimizer)
% Folder/file stem of the published reference tables (currently the same as
% the optimizer id).
switch optimizer
    case 'atmals-gsk'; r = 'atmals-gsk';
    case 'fdb-agsk';   r = 'fdb-agsk';
    otherwise;         r = optimizer;
end
end

function m = load_reference_means(project_root, optimizer, suite, dim)
% containers.Map of function id -> published reference Mean; empty when no
% reference table exists. Native-dim suites (dim == 0) read <opt>_<suite>.csv,
% or merge the per-dimension tables when only those exist (e.g. DT-GSK
% CEC2013-LSGO ships _D1000 and _D905). Other suites read
% <opt>_<suite>_D<dim>.csv. Unreadable tables are skipped.
m = containers.Map('KeyType', 'double', 'ValueType', 'double');
rn = ref_name(optimizer);
base = fullfile(project_root, 'benchmarks', 'cec_reference_results', suite, rn);
if dim == 0
    paths = {fullfile(base, sprintf('%s_%s.csv', rn, suite))};
    if ~isfile(paths{1})
        files = dir(fullfile(base, sprintf('%s_%s_D*.csv', rn, suite)));
        paths = fullfile({files.folder}, {files.name});
    end
else
    paths = {fullfile(base, sprintf('%s_%s_D%d.csv', rn, suite, dim))};
    if ~isfile(paths{1})   % some suites zero-pad the dimension (e.g. CEC2020 D05)
        paths = {fullfile(base, sprintf('%s_%s_D%02d.csv', rn, suite, dim))};
    end
end
for k = 1:numel(paths)
    if ~isfile(paths{k}); continue; end
    try
        T = readtable(paths{k});
    catch
        continue;
    end
    for i = 1:height(T)
        % Function ids may be written 1, F1 or f1; Mean may be blank or N/A.
        fid = parse_ref_number(T.Function, i, true);
        mv  = parse_ref_number(T.Mean, i, false);
        if ~isnan(fid) && ~isnan(mv)
            m(fid) = mv;
        end
    end
end
end

function v = parse_ref_number(col, i, digits_only)
%PARSE_REF_NUMBER One cell of a reference column as a double, tolerating
% numeric values, 'F1'-style ids, and blank/N/A statistics.
if isnumeric(col)
    v = double(col(i));
    return;
end
s = col(i);
if iscell(s); s = s{1}; end
s = strtrim(char(s));
if digits_only
    s = regexprep(s, '[^0-9]', '');   % 'F1' -> '1'
end
if isempty(s); v = NaN; else; v = str2double(s); end
end

function id = canonical_optimizer_id(name)
%CANONICAL_OPTIMIZER_ID Public optimizer slugs use hyphens.
% Lower-cases and trims the name and maps atmals_gsk, fdb_agsk and dt_gsk to
% their hyphenated ids. MATLAB function names keep the underscores
% (optimizer_function_stem).
id = lower(strtrim(char(name)));
switch id
    case 'atmals_gsk'
        id = 'atmals-gsk';
    case 'fdb_agsk'
        id = 'fdb-agsk';
    case 'dt_gsk'
        id = 'dt-gsk';
end
end

function tf = check_seed_policy(x)
%CHECK_SEED_POLICY inputParser validator: one of the four documented policies,
% matched case-insensitively (the value is kept as given). Anything else
% raises run_experiment:args, so a typo cannot fall through to the hashed
% native/derived schedule.
tf = (ischar(x) || (isstring(x) && isscalar(x))) && ...
     any(strcmpi(char(x), {'reference', 'unified', 'native', 'derived'}));
if ~tf
    if (ischar(x) && isrow(x)) || (isstring(x) && isscalar(x)); got = char(x); else; got = class(x); end
    error('run_experiment:args', ...
          'seed_policy must be reference, unified, native, or derived (got ''%s'')', got);
end
end

function stem = optimizer_function_stem(optimizer)
%OPTIMIZER_FUNCTION_STEM MATLAB-callable optimizer function stem.
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

function out = center(s, w)
% Center a string in a width-w field (no truncation if it is longer).
s = char(s);
n = numel(s);
if n >= w; out = s; return; end
total = w - n;
left = floor(total / 2);
out = [repmat(' ', 1, left) s repmat(' ', 1, total - left)];
end

function print_comparison_table(a, dim, func_ids, run_means)
% Compare this run's per-function Mean with the published reference for the
% same optimizer, suite and dimension, and print a verdict per function
% (^ improved, = same, v worse).
if ~population_is_default(a, dim)
    fprintf(['\n(np_init = %s, min_pop_size = %s is not the published %s setting -- ' ...
             'reference comparison skipped)\n'], np_init_text(a.optimizer, a.np_init), ...
            min_pop_text(a.optimizer, a.min_pop_size), a.optimizer);
    return;
end
if ~isempty(fieldnames(a.alias_settings))
    fprintf(['\n(%s changes %s settings (%s) -- not the published setting, ' ...
             'reference comparison skipped)\n'], a.name, a.optimizer, a.alias_text);
    return;
end
ref = load_reference_means(a.project_root, a.optimizer, a.suite, dim);
if ref.Count == 0
    fprintf('\n(no reference table for %s %s D%d -- comparison skipped)\n', a.optimizer, a.suite, dim);
    return;
end
zt = report_zero_tol(a); % errors below this are treated as zero
known = ~any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));
near_solved = 1.0;  % both error means below this -> "solved" (its % is just noise)
box = ['+' repmat('=', 1, 78) '+'];
if dim == 0; dlabel = 'native dims'; else; dlabel = sprintf('D=%d', dim); end
title = sprintf('Mean Error Comparison: Reference %s vs %s_%s (%s)', ...
                upper(a.optimizer), a.name, a.suite, dlabel);
fprintf('\n%s\n|%s|\n%s\n', box, center(title, 78), box);
if known
    fprintf('  Zero threshold: %g;  near-solved (both < %g) shown as ~ and counted =\n\n', zt, near_solved);
else
    fprintf('  Zero threshold: %g (values within this of zero are treated as zero)\n\n', zt);
end

wF = 8; wR = 26; wN = 14; wD = 14; wP = 14; wS = 10;   % wR fits 'Reference ATMALS-GSK Mean'
sep = ['+' repmat('-',1,wF) '+' repmat('-',1,wR) '+' repmat('-',1,wN) '+' ...
       repmat('-',1,wD) '+' repmat('-',1,wP) '+' repmat('-',1,wS) '+'];
fprintf('%s\n', sep);
fprintf('|%s|%s|%s|%s|%s|%s|\n', center('Func', wF), ...
        center(sprintf('Reference %s Mean', upper(a.optimizer)), wR), ...
        center(sprintf('%s Mean', a.name), wN), center('Delta(New-Old)', wD), ...
        center('% Improve', wP), center('Status', wS));
fprintf('%s\n', sep);

nimp = 0; nsame = 0; nworse = 0;
for i = 1:numel(func_ids)
    f = func_ids(i);
    if ~isKey(ref, f); continue; end   % e.g. F2 has no published reference
    ar = ref(f);          % reference mean (displayed as-is)
    br = run_means(i);     % this run's mean (displayed as-is)
    tar = ar; if abs(tar) < zt; tar = 0; end   % thresholded copies drive the
    tbr = br; if abs(tbr) < zt; tbr = 0; end   % verdict; abs() so CEC2011
    delta = br - ar;                            % negative objectives work
    if abs(delta) < zt; delta = 0; end          % display tiny New-Old noise as exact zero
    tdelta = tbr - tar;
    if abs(tdelta) < zt; tdelta = 0; end        % verdict uses the same Delta(New-Old) tolerance
    if tdelta == 0
        status = '='; nsame = nsame + 1;
        if tar == 0; pct = '-'; else; pct = '0.0%'; end
    elseif known && abs(ar) < near_solved && abs(br) < near_solved
        % both essentially solved -> the percentage would be meaningless noise
        status = '='; nsame = nsame + 1; pct = '~';
    elseif tdelta < 0
        status = '^'; nimp = nimp + 1;
        if tar ~= 0; pct = sprintf('+%.1f%%', (tar - tbr) / abs(tar) * 100); else; pct = '-'; end
    else
        status = 'v'; nworse = nworse + 1;
        if tar ~= 0; pct = sprintf('%.1f%%', (tar - tbr) / abs(tar) * 100); else; pct = '-'; end
    end
    fprintf('|%s|%s|%s|%s|%s|%s|\n', center(sprintf('F%02d', f), wF), ...
            center(sprintf('%.2E', ar), wR), center(sprintf('%.2E', br), wN), ...
            center(sprintf('%.2E', delta), wD), center(pct, wP), center(status, wS));
end
fprintf('%s\n', sep);
fprintf('\n  Summary: ^ Improved: %d  = Same: %d  v Worse: %d\n', nimp, nsame, nworse);
end

function n = make_convergence_graphs(graphs_dir, a, funcs, dims, xs, ys, session_tag)
%MAKE_CONVERGENCE_GRAPHS One PNG per function (median-run convergence) under
% curves/graphs. A light theme (white background, dark text, light major
% grid) is set explicitly, so the dark MATLAB desktop theme never leaks in.
% Log y-axis when no value is negative, else linear (CEC2011 raw objectives
% can be negative). Renders off-screen; returns the number of PNGs written.
fg   = [0.15 0.15 0.15];     % dark grey for axes/text
blue = [0.00 0.447 0.741];   % clear line colour
n = 0;
total = numel(funcs);
label = sprintf('Rendering convergence graphs (%s %s)', upper(a.name), upper(a.suite));
if total == 0
    fprintf('  %s: none queued\n', label);
    return;
end
fprintf('  %s: %d graph(s) queued\n', label, total);
timer = tic;
for i = 1:numel(funcs)
    x = xs{i}(:);
    y = ys{i}(:);
    suffix = sprintf('F%d D%d', funcs(i), dims(i));
    progress_bar(label, i - 1, total, suffix);
    if isempty(x)
        progress_bar(label, i, total, suffix);
        continue;
    end
    mIdx = unique(round(linspace(1, numel(x), min(14, numel(x)))));  % marker spots
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 780 470]);
    ax  = axes('Parent', fig);
    if any(y < 0)
        % raw objectives (e.g. CEC2011, can be negative) -> linear axis
        h = plot(ax, x, y, '-o', 'Color', blue, 'LineWidth', 1.6, ...
                 'MarkerSize', 5, 'MarkerFaceColor', blue, 'MarkerIndices', mIdx);
        ylabel(ax, 'Best objective (median run)', 'Color', fg);
    else
        % errors -> log axis; floor tiny/zero values so the axis stays finite
        h = semilogy(ax, x, max(y, 1e-12), '-o', 'Color', blue, 'LineWidth', 1.6, ...
                     'MarkerSize', 5, 'MarkerFaceColor', blue, 'MarkerIndices', mIdx);
        ylabel(ax, 'Best error (median run)', 'Color', fg);
    end
    grid(ax, 'on');
    set(ax, 'Color', 'w', 'XColor', fg, 'YColor', fg, ...
            'GridColor', [0.6 0.6 0.6], 'GridAlpha', 0.4, ...
            'XMinorGrid', 'off', 'YMinorGrid', 'off', ...
            'FontSize', 11, 'Box', 'on', 'LineWidth', 0.75);
    xlabel(ax, 'Function evaluations', 'Color', fg);
    title(ax, sprintf('F%d', funcs(i)), 'Color', [0.1 0.1 0.1], 'FontSize', 12);
    legend(ax, h, upper(a.name), 'Location', 'northeast', ...
           'TextColor', fg, 'Color', 'w', 'EdgeColor', [0.7 0.7 0.7]);
    try
        graph_path = fullfile(graphs_dir, sprintf('Figure_F%d_D%d.png', funcs(i), dims(i)));
        archive_existing_file(graph_path, session_tag);
        exportgraphics(fig, graph_path, ...
                       'Resolution', 150, 'BackgroundColor', 'white');
        n = n + 1;
    catch
        % a plotting/printing failure must never abort the sweep
    end
    close(fig);
    progress_bar(label, i, total, suffix);
end
fprintf('  %s completed in %.1fs\n', label, toc(timer));
end

function progress_bar(label, current, total, suffix)
%PROGRESS_BAR Compact command-window progress for post-processing phases.
% A carriage return redraws the line in interactive runs; the final update
% ends with a newline so diary/log files stay parseable.
if total <= 0
    return;
end
bar_w = 28;
current = max(0, min(current, total));
filled = floor(bar_w * current / total);
bar = [repmat('#', 1, filled) repmat('-', 1, bar_w - filled)];
pct = floor(100 * current / total);
if nargin < 4
    suffix = '';
end
suffix = char(suffix);
fprintf('\r  %s [%s] %3d%% (%d/%d) %-12s', label, bar, pct, current, total, suffix);
if current >= total
    fprintf('\n');
end
try
    drawnow limitrate
catch
    drawnow
end
end

function write_run_metadata(summary_dir, a, func_list, excluded_funcs, known_optimum, session_tag)
%WRITE_RUN_METADATA Write run_config.json and phase0_protocol.json.
% Reproducibility records, companions to environment.json and
% seed_schedule.csv; existing files are archived first.
scheme = seed_scheme_string(a);
% Strides of the seed formula actually used, recorded for checks (mirrors
% pick_run_seed).
base_field = 'base_seed';
stride_field = 'stride_run';
policy_for_strides = lower(char(a.seed_policy));
if is_unified_only(a.optimizer)
    policy_for_strides = 'unified';   % dt-gsk uses get_cec_seed under every policy
end
switch policy_for_strides
    case 'reference'
        switch a.optimizer
            case {'gsk', 'egsk', 'atmals-gsk'}
                run_stride = 1; dim_stride = 0; func_stride = 9973;
                seed_formula = 'base_seed + 9973*func + (run-1)';
            case {'agsk', 'apgsk', 'fdb-agsk'}
                % multiplicative D*func*run: no additive strides, base_seed unused
                run_stride = NaN; dim_stride = NaN; func_stride = NaN;   % null in JSON
                seed_formula = 'dim*func*run';
                base_field = ''; stride_field = '';
            otherwise   % pick_run_seed falls back to get_cec_seed
                run_stride = 1000037; dim_stride = 1000003; func_stride = 1000033;
                seed_formula = 'get_cec_seed(base_seed, dim, func, run)';
        end
    case 'unified'
        run_stride = 1000037; dim_stride = 1000003; func_stride = 1000033;
        seed_formula = 'get_cec_seed(base_seed, dim, func, run)';
    otherwise   % native / derived -> derive_run_seed
        run_stride = 10000379; dim_stride = 10000019;
        func_stride = 10000169;
        seed_formula = 'derive_run_seed(base_seed, optimizer, suite, dim, func, run)';
end

cfg = struct();
cfg.alg_name = a.name;
cfg.base_optimizer = a.optimizer;   % differs from alg_name for an algorithms.ini alias
cfg.alias_settings = a.alias_text;  % its settings ('' = none or not an alias)
cfg.suite = upper(a.suite);
cfg.base_seed = a.base_seed;
cfg.seed_policy = char(a.seed_policy);
cfg.seed_scheme = scheme;
cfg.seed_formula = seed_formula;
cfg.rand_generator = char(effective_rand_generator(a));
cfg.initial_population_policy = initial_population_policy_string(a);
cfg.overwrite = logical(a.overwrite);
cfg.overwrite_archived_to = a.overwrite_archived_to;
cfg.stride_run = run_stride;
cfg.dim_stride = dim_stride;
cfg.func_stride = func_stride;
cfg.runs = a.runs;
cfg.dims = a.dimensions(:)';
cfg.funcs = a.functions(:)';
cfg.exclude_funcs = excluded_funcs(:)';
cfg.funcs_to_run = func_list;
cfg.max_nfes_override = a.max_nfes;
cfg.statistics_basis = ternary(known_optimum, 'error_vs_optimum', 'raw_objective');
cfg.report_zero_tol = report_zero_tol(a);
cfg.verbose = logical(a.verbose);
cfg.use_parallel = logical(a.use_parallel);
cfg.write_graphs = logical(a.write_graphs);
cfg.optimizer_options = optimizer_options_metadata(a.optimizer, a.suite);
cfg.np_init = a.np_init;   % initial NP override (empty = optimizer default)
% final NP override; empty = default, and empty for optimizers that ignore it
cfg.min_pop_size = ternary(uses_min_pop_size(a.optimizer), a.min_pop_size, []);
if strcmp(a.optimizer, 'gsk')
    % GSK parameters this run actually used: the reference defaults, or an
    % alias's own values
    s = a.alias_settings;
    cfg.pop_size = ternary(isempty(a.np_init), 100, a.np_init);
    cfg.KF = setting_or(s, 'kf', 0.5); cfg.KR = setting_or(s, 'kr', 0.9);
    cfg.K = setting_or(s, 'k', 10); cfg.P = setting_or(s, 'p', 0.1);
elseif strcmp(a.optimizer, 'dt-gsk')
    % dimension-tiered 'pub' profile (dt_gsk_config); NP_init = 5*D unless
    % np_init replaces it
    cfg.profile = 'pub';
end
write_json(fullfile(summary_dir, 'run_config.json'), cfg, session_tag);

proto = struct();
proto.base_seed = a.base_seed;
proto.stride_run = run_stride;
proto.dim_stride = dim_stride;
proto.func_stride = func_stride;
proto.runs = a.runs;
proto.dims = a.dimensions(:)';
proto.suite = upper(a.suite);
proto.excluded = excluded_funcs(:)';
proto.funcs_to_run = func_list;   % the same set is run at every dimension here
proto.seed_policy = struct('scheme', scheme, 'formula', seed_formula, 'run_id_origin', 1, ...
                           'base_seed_field', base_field, 'stride_field', stride_field);
proto.rand_generator = char(effective_rand_generator(a));
proto.initial_population_policy = initial_population_policy_string(a);
proto.overwrite = logical(a.overwrite);
proto.overwrite_archived_to = a.overwrite_archived_to;
proto.write_graphs = logical(a.write_graphs);
proto.optimizer_options = optimizer_options_metadata(a.optimizer, a.suite);
proto.smoke = false;
write_json(fullfile(summary_dir, 'phase0_protocol.json'), proto, session_tag);
end

function s = seed_scheme_string(a)
% Readable description of the active seed schedule, recorded in
% environment.json, run_config.json and phase0_protocol.json. Keep in sync
% with pick_run_seed and effective_rand_generator.
if is_unified_only(a.optimizer)
    s = ['unified: seed = mod(uint64(base_seed)' ...
         ' + uint64(1000003)*uint64(dim) + uint64(1000033)*uint64(func)' ...
         ' + uint64(1000037)*uint64(run), uint64(2147483646)) + 1; ' a.optimizer ...
         ' is unified-only, so this schedule and threefry are forced under every seed_policy;' ...
         ' 9 Threefry streams derived from the run seed (fixed positions of a 13-position layout);' ...
         ' X0 drawn by the optimizer'];
    return;
end
switch lower(char(a.seed_policy))
    case 'reference'
        % Only the active optimizer's historical formula and generator.
        switch a.optimizer
            case {'gsk', 'egsk', 'atmals-gsk'}
                formula = 'seed = base_seed + 9973*func + (run-1)';
            case {'agsk', 'apgsk', 'fdb-agsk'}
                formula = 'seed = dim*func*run (base_seed unused)';
            otherwise
                formula = 'seed = get_cec_seed(base_seed, dim, func, run) (fallback)';
        end
        generator = char(effective_rand_generator(a));
        if strcmp(generator, 'seed'); generator = 'legacy seed (mcg16807)'; end
        s = sprintf('reference: %s; %s reference generator: %s', formula, a.optimizer, generator);
    case 'unified'
        s = ['unified: seed = mod(uint64(base_seed) + uint64(1000003)*uint64(dim)' ...
             ' + uint64(1000033)*uint64(func) + uint64(1000037)*uint64(run),' ...
             ' uint64(2147483646)) + 1; optimizer-independent fair cross-family schedule;' ...
             ' generator resolved to threefry when available, otherwise twister;' ...
             ' X0 drawn once in the runner'];
    otherwise   % native / derived
        s = ['derived/native: seed = mod(base_seed + 1000003*opt_code + 1000033*suite_code' ...
             ' + 10000019*dim + 10000169*func + 10000379*run, 2^31-2) + 1' ...
             ' (opt_code=sum(double(optimizer)), suite_code=sum(double(suite))); ' ...
             'generator follows rand_generator'];
end
end

function s = initial_population_policy_string(a)
%INITIAL_POPULATION_POLICY_STRING Metadata for reference vs unified starts.
if is_unified_only(a.optimizer)
    if isempty(a.np_init)
        np_text = 'NP = 5*D';
    else
        np_text = sprintf('NP = %d (np_init override, not the pub profile)', a.np_init);
    end
    s = ['optimizer self-initializes ' np_text ' from its own init substream; ' ...
         'runner X0 not used (documented DT-GSK fair-start exception)'];
elseif unified_initialization_enabled(a)
    s = ['runner-generated shared X0 from get_cec_seed(base_seed,dim,func,run); ' ...
         'post-initialization rng state restored inside optimizer'];
else
    s = 'optimizer draws its own reference/native initial population';
end
if ~isempty(a.np_init) && ~is_unified_only(a.optimizer)
    s = sprintf('%s; NP = %d (np_init)', s, a.np_init);
end
end

function write_json(path, s, session_tag)
archive_existing_file(path, session_tag);
fid = fopen(path, 'w');
if fid < 0; return; end
fprintf(fid, '%s\n', jsonencode(s, 'PrettyPrint', true));
fclose(fid);
end
