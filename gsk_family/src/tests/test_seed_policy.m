function test_seed_policy()
%TEST_SEED_POLICY Check the reference and unified seed policies of the runner.
%
% Runs on the sphere suite (no MEX) and checks: the get_cec_seed formula;
% that choose_cec_rng_generator restores the RNG state; that unified seeds
% are the same for every optimizer; seed_policy / rand_generator validation;
% reference-mode seed metadata; DT-GSK's fixed unified seeding;
% verify_unified_seed_schedule; a policy round trip; and, with the Parallel
% Computing Toolbox, that parfor gives the same results as a serial run.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));

base_seed = 20240620;
D = 10;
func_id = 1;
expected_unified = get_cec_seed(base_seed, D, func_id, 1);
example_seed = get_cec_seed(base_seed, 30, 7, 12);
assert(example_seed == 69241386, 'get_cec_seed formula changed for D30/F7/run12');

before_rng = rng;
selected_generator = choose_cec_rng_generator();
after_rng = rng;
assert(any(strcmp(selected_generator, {'threefry', 'twister'})), ...
    'unified RNG generator must resolve to threefry or twister');
assert(isequaln(before_rng, after_rng), 'choose_cec_rng_generator must restore RNG state');

out_root = fullfile(tempdir, sprintf('gskcec_seed_policy_%d', feature('getpid')));
out_gsk = fullfile(out_root, 'gsk', 'sphere');
out_agsk = fullfile(out_root, 'agsk', 'sphere');
if exist(out_root, 'dir'); rmdir(out_root, 's'); end
cleanup = onCleanup(@() cleanup_dirs(out_root));

run_experiment('optimizer', 'gsk', 'suite', 'sphere', 'functions', func_id, ...
               'dimensions', D, 'runs', 1, 'max_nfes', 1200, ...
               'project_root', project_root, 'output_dir', out_gsk, ...
               'seed_policy', 'unified', 'rand_generator', 'threefry', 'verbose', false);
run_experiment('optimizer', 'agsk', 'suite', 'sphere', 'functions', func_id, ...
               'dimensions', D, 'runs', 1, 'max_nfes', 1200, ...
               'project_root', project_root, 'output_dir', out_agsk, ...
               'seed_policy', 'unified', 'rand_generator', 'threefry', 'verbose', false);

seed_gsk = read_first_seed(out_gsk);
seed_agsk = read_first_seed(out_agsk);
assert(seed_gsk == expected_unified, 'unexpected GSK unified seed');
assert(seed_agsk == expected_unified, 'unified seed must be optimizer-independent');
verify_unified_seed_schedule(out_root, {'gsk', 'agsk'}, 'sphere');

env_gsk = jsondecode(fileread(fullfile(out_gsk, 'summary', 'environment.json')));
env_agsk = jsondecode(fileread(fullfile(out_agsk, 'summary', 'environment.json')));
assert(strcmp(env_gsk.rand_generator, selected_generator), 'unexpected unified generator for GSK');
assert(strcmp(env_agsk.rand_generator, selected_generator), 'unexpected unified generator for AGSK');
assert(contains(env_gsk.seed_policy, 'unified:'), 'environment should record unified policy');
assert(~contains(env_gsk.seed_policy, 'unified: unified:'), 'environment seed_policy label duplicated');

% ---- seed_policy / rand_generator validation -----------------------------
% seed_policy must be one of the four documented policies, matched
% case-insensitively; a typo must not silently run the hashed derived schedule.
small = {'suite', 'sphere', 'functions', 1, 'dimensions', 2, 'runs', 1, ...
         'max_nfes', 300, 'project_root', project_root, 'verbose', false};
bad_out = fullfile(out_root, 'rejected');
assert_rejected(@() run_experiment('optimizer', 'gsk', small{:}, 'output_dir', bad_out, ...
                                   'seed_policy', 'unifed'), 'seed_policy', bad_out);
% rand_generator auto/default is resolved only under unified; with
% native/derived it would fail every cell, so the call must be rejected.
assert_rejected(@() run_experiment('optimizer', 'gsk', small{:}, 'output_dir', bad_out, ...
                                   'seed_policy', 'native', 'rand_generator', 'auto'), ...
                'rand_generator', bad_out);
out_mixed = fullfile(out_root, 'mixed_case', 'gsk', 'sphere');
run_experiment('optimizer', 'gsk', small{:}, 'output_dir', out_mixed, 'seed_policy', 'Unified');
assert(read_first_seed(out_mixed) == get_cec_seed(base_seed, 2, 1, 1), ...
       'mixed-case ''Unified'' must select the unified schedule');

% ---- reference-mode seed metadata matches the optimizer's real formula ------
ref_root = fullfile(out_root, 'reference');
for opt = {'gsk', 'agsk'}
    out_ref = fullfile(ref_root, opt{1}, 'sphere');
    run_experiment('optimizer', opt{1}, 'suite', 'sphere', 'functions', 3, 'dimensions', D, ...
                   'runs', 2, 'max_nfes', 300, 'project_root', project_root, ...
                   'output_dir', out_ref, 'seed_policy', 'reference', 'verbose', false);
    cfg = jsondecode(fileread(fullfile(out_ref, 'summary', 'run_config.json')));
    proto = jsondecode(fileread(fullfile(out_ref, 'summary', 'phase0_protocol.json')));
    env = jsondecode(fileread(fullfile(out_ref, 'summary', 'environment.json')));
    seeds = read_seeds(out_ref);
    if strcmp(opt{1}, 'gsk')
        assert(cfg.stride_run == 1 && cfg.dim_stride == 0 && cfg.func_stride == 9973, ...
               'gsk reference strides must describe base_seed + 9973*func + (run-1)');
        assert(isequal(seeds, cfg.base_seed + cfg.func_stride * 3 + cfg.stride_run * ((1:2)' - 1)), ...
               'gsk reference seeds must follow the recorded strides');
        assert(strcmp(proto.seed_policy.base_seed_field, 'base_seed'), 'gsk phase0 base_seed_field');
    else
        assert(isempty(cfg.stride_run) && isempty(cfg.dim_stride) && isempty(cfg.func_stride), ...
               'agsk reference (dim*func*run) has no additive strides (null)');
        assert(strcmp(cfg.seed_formula, 'dim*func*run') && strcmp(proto.seed_policy.formula, 'dim*func*run'), ...
               'agsk reference seed_formula');
        assert(isempty(proto.seed_policy.base_seed_field), 'agsk reference does not use base_seed');
        assert(isequal(seeds, D * 3 * (1:2)'), 'agsk reference seeds must be dim*func*run');
        assert(contains(env.seed_policy, 'dim*func*run') && ~contains(env.seed_policy, '9973'), ...
               'agsk reference scheme must describe only its own formula');
    end
end

% ---- dt-gsk is unified-only: get_cec_seed + threefry under every policy ------
for pol = {'reference', 'native'}
    out_dt = fullfile(out_root, ['dt_' pol{1}], 'dt-gsk', 'sphere');
    run_experiment('optimizer', 'dt-gsk', 'suite', 'sphere', 'functions', 3, 'dimensions', D, ...
                   'runs', 2, 'max_nfes', 300, 'project_root', project_root, ...
                   'output_dir', out_dt, 'seed_policy', pol{1}, 'verbose', false);
    seeds = read_seeds(out_dt);
    assert(isequal(seeds, [get_cec_seed(base_seed, D, 3, 1); get_cec_seed(base_seed, D, 3, 2)]), ...
           'dt-gsk must use get_cec_seed under seed_policy=%s', pol{1});
    env = jsondecode(fileread(fullfile(out_dt, 'summary', 'environment.json')));
    cfg = jsondecode(fileread(fullfile(out_dt, 'summary', 'run_config.json')));
    assert(strcmp(env.rand_generator, 'threefry'), 'dt-gsk must run threefry under %s', pol{1});
    assert(contains(env.initial_population_policy, 'self-initializes'), 'dt-gsk X0 metadata');
    assert(strcmp(cfg.profile, 'pub') && strcmp(cfg.seed_formula, 'get_cec_seed(base_seed, dim, func, run)'), ...
           'dt-gsk run_config profile/seed_formula');
end

% ---- verify_unified_seed_schedule: compare common keys, warn on missing ones ----
syn = fullfile(out_root, 'synthetic');
write_schedule(syn, 'opt_a', [10 1 1 11; 10 1 2 12]);
write_schedule(syn, 'opt_b', [10 1 1 11]);                 % a failed/skipped cell
write_schedule(syn, 'opt_c', [10 1 2 12; 10 2 1 21]);      % extra historical key
lastwarn('');
verify_unified_seed_schedule(syn, {'opt_a', 'opt_b', 'opt_c'}, 'sphere');
[~, warn_id] = lastwarn;
assert(strcmp(warn_id, 'verify_unified_seed_schedule:missingKeys'), ...
       'missing schedule keys must be reported as a warning, not an error');
% A key absent from the first optimizer is still compared between the others.
write_schedule(syn, 'opt_d', [10 2 1 99]);
threw = false;
try
    verify_unified_seed_schedule(syn, {'opt_b', 'opt_c', 'opt_d'}, 'sphere');
catch err
    threw = strcmp(err.identifier, 'verify_unified_seed_schedule:seedMismatch');
end
assert(threw, 'a seed mismatch on a key the first optimizer lacks must still fail');

% ---- policy round trip: reused runs must be visible in the schedule --------
% unified -> reference -> unified into the same trees: the third session
% reuses the unified rows, and the verifier (latest row per key) must see
% the unified seeds again, not the reference ones from the middle session.
rt_root = fullfile(out_root, 'round_trip');
for policy = {'unified', 'reference', 'unified'}
    for opt = {'gsk', 'agsk'}
        run_experiment('optimizer', opt{1}, small{:}, 'output_dir', fullfile(rt_root, opt{1}, 'sphere'), ...
                       'seed_policy', policy{1});
    end
end
verify_unified_seed_schedule(rt_root, {'gsk', 'agsk'}, 'sphere');
assert(numel(read_seeds(fullfile(rt_root, 'gsk', 'sphere'))) == 3, ...
       'the reused unified run must be re-recorded in seed_schedule.csv');

% ---- serial vs parfor -----------------------------------------------------
if license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'))
    [pool_ok, pool_note, pool_guard] = small_process_pool(); %#ok<ASGLU>
    if pool_ok
        task_matrix = [30 1 1; 30 2 1; 30 3 1; 30 1 2; 30 2 2; 30 3 2];
        serial_fingerprints = seed_task_fingerprints(task_matrix, base_seed, selected_generator, false);
        parallel_fingerprints = seed_task_fingerprints(task_matrix, base_seed, selected_generator, true);
        assert(isequaln(serial_fingerprints, parallel_fingerprints), ...
            'parfor workers must reproduce the unified seed and rng(seed,generator) draws');

        % The runner's own parfor branch (per-worker problem, runner X0,
        % sliced seeds/rows) must write the same files as the serial loop.
        common = {'optimizer', 'gsk', 'suite', 'sphere', 'functions', 1, 'dimensions', D, ...
                  'runs', 3, 'base_seed', base_seed, 'max_nfes', 1200, 'project_root', project_root, ...
                  'seed_policy', 'unified', 'rand_generator', 'threefry', 'verbose', false, ...
                  'write_graphs', false, 'overwrite', true};
        out_ser = fullfile(out_root, 'parcheck', 'serial');
        out_par = fullfile(out_root, 'parcheck', 'parfor');
        run_experiment(common{:}, 'output_dir', out_ser, 'use_parallel', false);
        run_experiment(common{:}, 'output_dir', out_par, 'use_parallel', true);
        assert(~isempty(gcp('nocreate')), 'runner parfor check ran without a pool');
        strip_runtime = @(txt) regexprep(txt, '^((?:[^,\r\n]*,){10})[^,\r\n]*', '$1', 'lineanchors');
        same = {fullfile('summary', 'seed_schedule.csv'), fullfile('summary', 'gsk_sphere_D10.csv'), ...
                fullfile('gen_logs', 'CheckpointErrors_gsk_F1_D10.csv')};
        for k = 1:numel(same)
            assert(strcmp(fileread(fullfile(out_ser, same{k})), fileread(fullfile(out_par, same{k}))), ...
                   'serial and parfor runner outputs differ: %s', same{k});
        end
        assert(strcmp(strip_runtime(fileread(fullfile(out_ser, 'summary', 'per_run.csv'))), ...
                      strip_runtime(fileread(fullfile(out_par, 'summary', 'per_run.csv')))), ...
               'serial and parfor runner per_run.csv differ (runtime column excluded)');
        cs = dir(fullfile(out_ser, 'curves', '*.csv'));
        cp = dir(fullfile(out_par, 'curves', '*.csv'));
        assert(isequal({cs.name}, {cp.name}) && ...
               strcmp(fileread(fullfile(cs(1).folder, cs(1).name)), fileread(fullfile(cp(1).folder, cp(1).name))), ...
               'serial and parfor runner median curves differ');
    else
        fprintf('test_seed_policy: parfor checks skipped (%s)\n', pool_note);
    end
else
    fprintf('test_seed_policy: parfor checks skipped (Parallel Computing Toolbox unavailable)\n');
end

fprintf('test_seed_policy: PASS\n');
end

function seed = read_first_seed(out_dir)
% Seed of the first data row in seed_schedule.csv.
rows = readlines(fullfile(out_dir, 'summary', 'seed_schedule.csv'));
rows = rows(strlength(strtrim(rows)) > 0);
fields = strsplit(char(rows(2)), ',');
seed = str2double(fields{4});
end

function seeds = read_seeds(out_dir)
% Seed column of every seed_schedule.csv row, in file order.
rows = readlines(fullfile(out_dir, 'summary', 'seed_schedule.csv'));
rows = rows(strlength(strtrim(rows)) > 0);
seeds = zeros(numel(rows) - 1, 1);
for i = 2:numel(rows)
    fields = strsplit(char(rows(i)), ',');
    seeds(i - 1) = str2double(fields{4});
end
end

function assert_rejected(call, what, out_dir)
% call() must fail with a message that names 'what' and create no out_dir.
threw = false;
try
    call();
catch err
    threw = contains(err.message, what);
end
assert(threw, 'run_experiment must reject an invalid %s', what);
assert(~exist(out_dir, 'dir'), 'a rejected call must not create the output tree');
end

function write_schedule(root, opt, rows)
% Write a synthetic seed_schedule.csv; each row is [Dim Function Run Seed].
d = fullfile(root, opt, 'sphere', 'summary');
if ~exist(d, 'dir'); mkdir(d); end
fid = fopen(fullfile(d, 'seed_schedule.csv'), 'w');
fprintf(fid, 'Dim,Function,Run,Seed\n');
fprintf(fid, '%d,%d,%d,%d\n', rows');
fclose(fid);
end

function [ok, note, guard] = small_process_pool()
% Open a 2-worker process pool for the parfor checks, so that neither parfor
% nor run_experiment opens one worker per core. guard deletes the pool when
% this test created it. An open process pool is reused. Any other open pool
% (e.g. a thread pool) is left alone and the checks are skipped, since the
% runner would replace that pool.
ok = false;
note = '';
guard = [];
pool = gcp('nocreate');
if ~isempty(pool)
    ok = isa(pool, 'parallel.ProcessPool');
    if ~ok; note = 'an existing non-process pool is open'; end
    return;
end
try
    parpool('Processes', 2);
    ok = true;
    guard = onCleanup(@() delete(gcp('nocreate')));
catch err
    note = sprintf('could not start a process pool: %s', err.message);
end
end

function fingerprints = seed_task_fingerprints(task_matrix, base_seed, rng_generator, use_parallel)
% Quick worker check without an optimizer run: one fingerprint row per task
% (num_tasks x 4, see one_seed_task) of the unified seed and its
% rng(seed, generator) draws, computed serially or in parfor. The runner's
% own X0 is covered by the serial-vs-parfor run_experiment check in the
% main test.
num_tasks = size(task_matrix, 1);
fingerprints = zeros(num_tasks, 4);
np = 8;
if use_parallel
    parfor i = 1:num_tasks
        fingerprints(i, :) = one_seed_task(task_matrix(i, :), base_seed, rng_generator, np);
    end
else
    for i = 1:num_tasks
        fingerprints(i, :) = one_seed_task(task_matrix(i, :), base_seed, rng_generator, np);
    end
end
end

function fingerprint = one_seed_task(task, base_seed, rng_generator, np)
% task = [dim func run]. Returns [seed, sum, mean, last value] of an
% np x dim rand draw made right after rng(seed, rng_generator).
dim = task(1);
func = task(2);
run = task(3);
seed = get_cec_seed(base_seed, dim, func, run);
rng(seed, rng_generator);
x0 = rand(np, dim);
fingerprint = [seed, sum(x0(:)), mean(x0(:)), x0(end)];
end

function cleanup_dirs(varargin)
% Delete each given folder and its contents, if it exists.
for i = 1:nargin
    if exist(varargin{i}, 'dir')
        rmdir(varargin{i}, 's');
    end
end
end
