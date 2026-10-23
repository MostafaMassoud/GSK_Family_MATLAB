%RUN_ALL_CEC2011 Run GSK-family optimizers on the CEC2011 real-world suite.
%
% How to use:
%   1. Open this file in MATLAB (it sits next to the gsk_family/ folder).
%   2. Press the green Run button (click "Change Folder" if MATLAB asks).
%   3. Each problem prints one results row, then a results table and a
%      comparison with the optimizer's reference results. The full report is
%      also saved to
%      results/_run_all/<opt>/cec2011/summary/<opt>_native_log_*.txt
%      (per-run detail in <opt>_native_runs_log_*.txt).
%
% CEC2011 notes:
%   - 22 real-world problems, each with its own (native) dimension.
%   - No known optimum: statistics use raw objective values, which can be
%     negative.
%   - Budget: 150,000 evaluations per problem.
%   - Keep dimensions = 0 (0 = each problem's own dimension).
%   - The CONFIG below runs problems 4:6 only; set functions = 1:22 for the
%     full suite.
%   - DT-GSK uses the unified seed and threefry under every seed_policy, and
%     samples its own NP = 5*D initial population (it ignores the runner X0).
%   - np_init (CONFIG) sets the initial population size of every optimizer,
%     DT-GSK included; min_pop_size sets the final size of the four that
%     shrink their population. [] keeps each default.

%% ------------------------------ CONFIG ----------------------------------
optimizers  = {'gsk'};
% optimizers = {'gsk', 'agsk', 'apgsk','fdb-agsk','egsk','atmals-gsk','dt-gsk'};

functions   = 4:6;         % subset; full suite is 1:22 (none excluded)
dimensions  = 0;            % 0 = each problem's native dimension (required for CEC2011)
runs        = 25;           % CEC2011 protocol (adjust as needed)
max_nfes    = 0;            % 0 = suite default (150,000 evaluations)
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
use_parallel = true;       % true = parfor over runs; false = serial baseline / troubleshooting
write_graphs = false;      % false = keep numeric curves/gen_logs, skip slow PNG rendering
overwrite = true;          % true = archive the previous result tree and start clean
% -------------------------------------------------------------------------

suite = 'cec2011';

%% ------------------------------ SET UP ----------------------------------
root = fullfile(fileparts(mfilename('fullpath')), 'gsk_family');
src_dir = fullfile(root, 'src');
if ~isfolder(src_dir)
    error('run_all:missingSource', 'GSK source folder not found: %s', src_dir);
end
addpath(genpath(src_dir));                      % optimizers, runners, helpers
rehash;
clear run_experiment;                           % pick up runner edits in long MATLAB sessions
% The CEC suites need the C++ MEX bridge gskcec_eval. Build it first
% (RUNBOOK.md section 3; commands also in build.txt).
gskcec_require_mex(root, 'run_all_cec2011');

fprintf('\n==================== run_all (CEC2011) ====================\n');
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
