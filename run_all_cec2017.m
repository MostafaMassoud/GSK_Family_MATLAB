%RUN_ALL_CEC2017 Run GSK-family optimizers on the CEC2017 suite.
%
% How to use:
%   1. Open this file in MATLAB (it sits next to the gsk_family/ folder).
%   2. Press the green Run button (click "Change Folder" if MATLAB asks).
%   3. Each function prints one results row, then a results table and a
%      comparison with the optimizer's reference results for each dimension.
%      The full report is also saved to
%      results/_run_all/<opt>/cec2017/summary/<opt>_D<d>_log_*.txt
%      (per-run detail in <opt>_D<d>_runs_log_*.txt).
%
% CEC2017 notes:
%   - F2 is excluded automatically for all optimizers (unstable; not in the
%     reference tables).
%   - The default seed_policy is 'unified', for fair comparisons across the
%     family: every optimizer gets the same seed for each (D, function, run),
%     and the RNG is threefry when this MATLAB supports it, else twister.
%   - To reproduce published tables, set seed_policy = 'reference':
%       GSK, ATMALS-GSK, eGSK: runner default seed + 9973*func + run - 1
%       AGSK, APGSK, FDB-AGSK: D*func*run
%   - DT-GSK uses the unified seed and threefry under every seed_policy (its
%     reference protocol), and samples its own NP = 5*D initial population
%     (it ignores the runner X0).
%   - np_init (CONFIG) sets the initial population size of every optimizer,
%     DT-GSK included; min_pop_size sets the final size of the four that
%     shrink their population. [] keeps each default.
%   - Edit the CONFIG block to change optimizers, functions, dimensions and
%     runs.

%% ------------------------------ CONFIG ----------------------------------

optimizers = {'gsk'};
%optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk', 'dt-gsk'};

functions   = [1:30];             % F2 is excluded automatically, so 29 functions run
dimensions  = [10];   % CEC2017 standard dims are [10 30 50 100]; this runs D10 only
runs        = 51;               % independent runs per function
max_nfes    = 0;                % 0 = suite default (10000 * D)
np_init     = [];             % initial population size for every optimizer: [] = each one's
                               % default (100; DT-GSK 5*D); e.g. 100 for the same NP everywhere
min_pop_size = [];            % final population size of agsk, apgsk, fdb-agsk, dt-gsk (>= 11); [] = each
                               % one's default (12; DT-GSK 25 for D >= 50); gsk, egsk, atmals-gsk ignore it
% The base seed is set in gsk_family/src/runners/run_experiment.m.
% seed_policy:
%   'unified'   -> for each (D, function, run), every optimizer gets the same
%                  seed, the same runner-made X0 and the same RNG state after
%                  X0; threefry if available, else twister
%   'reference' -> reproduce published tables with each optimizer's own rules
%   'native'/'derived' -> diagnostic seed schedules hashed per optimizer/suite
seed_policy = 'unified';
rand_generator = 'threefry';
use_parallel = true;           % true = parfor over runs; false = serial baseline (no worker-path failures)
write_graphs = false;          % false = keep numeric curves/gen_logs, skip slow PNG rendering
overwrite = true;              % true = archive the previous result tree and start clean
% -------------------------------------------------------------------------

suite = 'cec2017';

%% ------------------------------ SET UP ----------------------------------
root = fullfile(fileparts(mfilename('fullpath')), 'gsk_family');
src_dir = fullfile(root, 'src');
if ~isfolder(src_dir)
    error('run_all:missingSource', 'GSK source folder not found: %s', src_dir);
end
addpath(genpath(src_dir));                      % optimizers, runners, helpers
rehash;
clear run_experiment gskcec_make_problem;       % pick up runner edits in long MATLAB sessions
% The CEC suites need the C++ MEX bridge gskcec_eval. Build it first
% (RUNBOOK.md section 3; commands also in build.txt).
gskcec_require_mex(root, 'run_all_cec2017');

fprintf('\n==================== run_all (CEC2017) ====================\n');
fprintf('suite=%s  functions=%s  dims=%s  runs=%d  seed_policy=%s  rng=%s  parallel=%d  graphs=%d  overwrite=%d  np_init=%s  min_pop_size=%s\n', ...
        suite, mat2str(functions), mat2str(dimensions), runs, seed_policy, rand_generator, use_parallel, write_graphs, overwrite, mat2str(np_init), mat2str(min_pop_size));

%% ------------------------------ RUN -------------------------------------
passed_optimizers = {};
for i = 1:numel(optimizers)
    opt = optimizers{i};
    out = fullfile(root, 'results', '_run_all', opt, suite);
    fprintf('\n----- [%d/%d] %s -----\n', i, numel(optimizers), upper(opt));
    try
        run_experiment('optimizer', opt, 'suite', suite, ...
            'functions', functions, 'dimensions', dimensions, 'runs', runs, ...
            'max_nfes', max_nfes, 'np_init', np_init, 'min_pop_size', min_pop_size, ...
            'project_root', root, 'output_dir', out, 'overwrite', overwrite, ...
            'verbose', false, 'seed_policy', seed_policy, ...
            'rand_generator', rand_generator, ...
            'use_parallel', use_parallel, ...
            'write_graphs', write_graphs);
        fprintf('PASS  %s\n', upper(opt));
        passed_optimizers{end + 1} = opt; %#ok<SAGROW>
    catch err
        fprintf(2, 'FAIL  %s: %s\n', upper(opt), err.message);
    end
end
if strcmpi(seed_policy, 'unified')
    % Check that the passed optimizers recorded the same seed for each
    % (D, function, run) in seed_schedule.csv; catches seed-policy drift.
    verify_unified_seed_schedule(fullfile(root, 'results', '_run_all'), passed_optimizers, suite);
end

fprintf('\n==================== done ====================\n');
fprintf('Results under: %s\n', fullfile(root, 'results', '_run_all'));
