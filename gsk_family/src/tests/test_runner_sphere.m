function test_runner_sphere()
%TEST_RUNNER_SPHERE End-to-end runner smoke on the pure-MATLAB sphere suite.
%
% Runs run_experiment without the MEX bridge and checks that:
%   - the CEC-competition output layout (summary/curves/gen_logs) is
%     written and follows docs/reference/result_schema.md;
%   - a rerun with the same seed gives byte-identical numeric content;
%   - resume keeps existing output and appends only the missing runs;
%   - output inside benchmarks/cec_reference_results is refused.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
out_dir = fullfile(tempdir, sprintf('gskcec_runner_smoke_%d', feature('getpid')));
if exist(out_dir, 'dir'); rmdir(out_dir, 's'); end

run_experiment('optimizer', 'gsk', 'suite', 'sphere', 'functions', 1, ...
               'dimensions', 10, 'runs', 2, 'base_seed', 4242, 'max_nfes', 4000, ...
               'project_root', project_root, 'output_dir', out_dir, 'overwrite', true);

summary_dir = fullfile(out_dir, 'summary');
curves_dir = fullfile(out_dir, 'curves');
genlogs_dir = fullfile(out_dir, 'gen_logs');
assert(isfolder(summary_dir) && isfolder(curves_dir) && isfolder(genlogs_dir), ...
       'summary/curves/gen_logs missing');

% Per-dimension summary table (Function,Best,Median,Mean,Worst,SD).
summary_csv = fullfile(summary_dir, 'gsk_sphere_D10.csv');
assert(isfile(summary_csv), 'per-dimension summary missing: %s', summary_csv);
srows = readlines(summary_csv);
assert(strcmp(strtrim(srows(1)), 'Function,Best,Median,Mean,Worst,SD'), 'summary header mismatch');
svals = strsplit(char(srows(2)), ',');
assert(str2double(svals{1}) == 1, 'summary function id');
assert(str2double(svals{2}) <= str2double(svals{5}), 'summary best <= worst');

% Full per-run table (with seeds) in summary/per_run.csv.
per_run = fullfile(summary_dir, 'per_run.csv');
assert(isfile(per_run), 'per_run.csv missing');
prows = readlines(per_run);
assert(strcmp(prows(1), ['optimizer,suite,function,dimension,run,seed,best_fitness,error,' ...
                         'nfes,termination,runtime_seconds,max_nfes,rand_generator']), 'per_run header');
assert(numel(prows) >= 3, 'expected 2 per-run rows');
first = strsplit(char(prows(2)), ',');
assert(str2double(first{9}) <= 4000, 'nfes exceeds budget');
assert(str2double(first{12}) == 4000, 'per_run max_nfes column must hold the cell budget');
assert(any(strcmp(first{13}, {'threefry', 'twister'})), 'per_run rand_generator column');
% best_fitness/error are stored at round-trip precision (%.17g).
assert(sprintf('%.17g', str2double(first{7})) == string(first{7}), 'best_fitness not round-trip');
per_run_before_resume = fileread(per_run);

% environment.json holds the run metadata.
env = jsondecode(fileread(fullfile(summary_dir, 'environment.json')));
assert(strcmp(env.optimizer, 'gsk') && strcmp(env.suite, 'sphere'), 'environment content');
assert(env.base_seed == 4242 && ~isempty(env.seed_policy), 'environment seed policy');

% Curves (median run) and gen_logs (checkpoint errors across runs).
assert(~isempty(dir(fullfile(curves_dir, 'Figure_F1_D10_Run#*.csv'))), 'curve file missing');
chk = fullfile(genlogs_dir, 'CheckpointErrors_gsk_F1_D10.csv');
assert(isfile(chk), 'CheckpointErrors missing');
crows = readlines(chk);
assert(startsWith(crows(1), 'Run,Seed,E'), 'checkpoint header');
assert(numel(crows) >= 3, 'expected 2 checkpoint rows');

% Determinism: rerun and compare the numeric outputs byte for byte.
% environment.json (has a timestamp) is skipped; per_run.csv is compared
% without its runtime column.
out2 = [out_dir '_b'];
if exist(out2, 'dir'); rmdir(out2, 's'); end
run_experiment('optimizer', 'gsk', 'suite', 'sphere', 'functions', 1, ...
               'dimensions', 10, 'runs', 2, 'base_seed', 4242, 'max_nfes', 4000, ...
               'project_root', project_root, 'output_dir', out2, 'overwrite', true);
det = {fullfile('summary', 'gsk_sphere_D10.csv'), ...
       fullfile('gen_logs', 'CheckpointErrors_gsk_F1_D10.csv')};
for k = 1:numel(det)
    a = fileread(fullfile(out_dir, det{k}));
    b = fileread(fullfile(out2, det{k}));
    assert(strcmp(a, b), '%s not deterministic across reruns', det{k});
end
% Compare per_run.csv without runtime_seconds (field 11 of 13).
strip_runtime = @(txt) regexprep(txt, '^((?:[^,\r\n]*,){10})[^,\r\n]*', '$1', 'lineanchors');
a = strip_runtime(fileread(per_run));
b = strip_runtime(fileread(fullfile(out2, 'summary', 'per_run.csv')));
assert(~contains(a, 'runtime_seconds') && contains(a, ',max_nfes,rand_generator'), ...
       'runtime column strip misaligned');
assert(strcmp(a, b), 'per_run.csv not deterministic across reruns');

% Resume: an existing output tree is never deleted. Rerunning with more runs
% appends only the missing run and moves each fixed-name file it refreshes
% to <folder>/_archive (checked here for summary/).
run_experiment('optimizer', 'gsk', 'suite', 'sphere', 'functions', 1, ...
               'dimensions', 10, 'runs', 3, 'base_seed', 4242, 'max_nfes', 4000, ...
               'project_root', project_root, 'output_dir', out_dir, 'overwrite', false);
prows_after = readlines(per_run);
prows_after = prows_after(strlength(strtrim(prows_after)) > 0);
assert(numel(prows_after) == 4, 'resume should keep 2 rows and append run 3');
assert(strcmp(strtrim(prows_after(2)), strtrim(prows(2))) && ...
       strcmp(strtrim(prows_after(3)), strtrim(prows(3))), ...
       'resume modified existing per-run rows');
last = strsplit(char(prows_after(4)), ',');
assert(str2double(last{5}) == 3, 'resume did not append the missing run id');
assert(startsWith(fileread(per_run), per_run_before_resume), ...
       'resume should append to per_run.csv instead of rewriting it');
chk_rows_after = readlines(chk);
chk_rows_after = chk_rows_after(strlength(strtrim(chk_rows_after)) > 0);
assert(numel(chk_rows_after) == 4, 'resume should append checkpoint row for run 3');
assert(isfolder(fullfile(summary_dir, '_archive')), 'resume archive folder missing');

% Output inside the imported reference tree is refused on every run (not
% only with overwrite=true) with run_experiment:outputUnsafe, before any
% folder is created. Tested with an absolute output_dir and with one
% relative to the current folder.
ref_root = fullfile(project_root, 'benchmarks', 'cec_reference_results');
guard_leaf = sprintf('_runner_guard_test_%d', feature('getpid'));
guard_args = {'optimizer', 'gsk', 'suite', 'sphere', 'functions', 1, 'dimensions', 2, ...
              'runs', 1, 'max_nfes', 300, 'project_root', project_root, 'verbose', false};
here_before = pwd;
restore_dir = onCleanup(@() cd(here_before)); %#ok<NASGU>
for k = 1:2
    if k == 1
        target = fullfile(ref_root, guard_leaf);
    else
        cd(fullfile(project_root, 'benchmarks'));
        target = fullfile('cec_reference_results', guard_leaf);
    end
    threw = false;
    try
        run_experiment(guard_args{:}, 'output_dir', target, 'overwrite', false);
    catch err
        threw = strcmp(err.identifier, 'run_experiment:outputUnsafe');
    end
    if ~threw   % never leave a stray tree in the reference folder, even on failure
        if exist(fullfile(ref_root, guard_leaf), 'dir'); rmdir(fullfile(ref_root, guard_leaf), 's'); end
    end
    assert(threw, 'output_dir inside cec_reference_results must be refused (case %d)', k);
    assert(~exist(fullfile(ref_root, guard_leaf), 'dir'), ...
           'refused run must not create anything under cec_reference_results');
end
cd(here_before);

rmdir(out_dir, 's');
rmdir(out2, 's');
fprintf('test_runner_sphere: PASS\n');
end
