function test_seed_policy()
%TEST_SEED_POLICY Guard reference/unified seed-policy semantics.

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

if license('test', 'Distrib_Computing_Toolbox')
    task_matrix = [30 1 1; 30 2 1; 30 3 1; 30 1 2; 30 2 2; 30 3 2];
    serial_fingerprints = seed_task_fingerprints(task_matrix, base_seed, selected_generator, false);
    parallel_fingerprints = seed_task_fingerprints(task_matrix, base_seed, selected_generator, true);
    assert(isequaln(serial_fingerprints, parallel_fingerprints), ...
        'serial and parfor unified seed/X0 schedules must match');
else
    fprintf('test_seed_policy: parallel reproducibility check skipped (Parallel Computing Toolbox unavailable)\n');
end

fprintf('test_seed_policy: PASS\n');
end

function seed = read_first_seed(out_dir)
rows = readlines(fullfile(out_dir, 'summary', 'seed_schedule.csv'));
rows = rows(strlength(strtrim(rows)) > 0);
fields = strsplit(char(rows(2)), ',');
seed = str2double(fields{4});
end

function fingerprints = seed_task_fingerprints(task_matrix, base_seed, rng_generator, use_parallel)
% Exercise the same seed/X0 schedule in serial and parfor without running a
% full optimizer. This keeps the reproducibility test independent of worker
% startup quirks, MEX handles, plotting, and optimizer runtime.
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
dim = task(1);
func = task(2);
run = task(3);
seed = get_cec_seed(base_seed, dim, func, run);
rng(seed, rng_generator);
x0 = rand(np, dim);
fingerprint = [seed, sum(x0(:)), mean(x0(:)), x0(end)];
end

function cleanup_dirs(varargin)
for i = 1:nargin
    if exist(varargin{i}, 'dir')
        rmdir(varargin{i}, 's');
    end
end
end
