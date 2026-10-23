%RUN_ALL_CEC2020 Run GSK-family optimizers on the CEC2020 suite.
%
% How to use:
%   1. Open this file in MATLAB (it sits next to the gsk_family/ folder).
%   2. Press the green Run button (click "Change Folder" if MATLAB asks).
%   3. Each function prints one results row, then results and comparison
%      tables for each dimension. The full report is saved under
%      results/_run_all/<opt>/cec2020/summary/.
%
% CEC2020 notes:
%   - 10 bound-constrained functions with known optima.
%   - Budgets grow steeply with dimension: D5 = 50k, D10 = 1M, D15 = 3M,
%     D20 = 10M evaluations. D15 and D20 are EXTREMELY long.
%   - Only AGSK (published) and DT-GSK (imported from its reference
%     implementation) have CEC2020 reference tables. For other optimizers
%     the comparison table is skipped; results are still written.
%   - DT-GSK uses the unified seed and threefry under every seed_policy, and
%     samples its own NP = 5*D initial population (it ignores the runner X0).
%   - np_init (CONFIG) sets the initial population size of every optimizer,
%     DT-GSK included; [] keeps each default.

%% ------------------------------ CONFIG ----------------------------------
optimizers  = {'gsk'};       % set to {'agsk'} or {'dt-gsk'} to get the reference comparison
% optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk', 'dt-gsk'};

functions   = 1:10;           % CEC2020 has 10 functions
dimensions  = [5 10];         % start small; full set is [5 10 15 20] (D15/D20 are huge)
runs        = 30;             % CEC2020 standard
max_nfes    = 0;              % 0 = suite default (D5=50k, D10=1M, D15=3M, D20=10M)
np_init     = [];             % initial population size for every optimizer: [] = each one's
                               % default (100; DT-GSK 5*D); e.g. 100 for the same NP everywhere
% The base seed is set in gsk_family/src/runners/run_experiment.m.
% seed_policy:
%   'unified'   -> for each (D, function, run), every optimizer gets the same
%                  seed, the same runner-made X0 and the same RNG state after
%                  X0; threefry if available, else twister
%   'reference' -> reproduce published tables with each optimizer's own rules
%   'native'/'derived' -> diagnostic seed schedules hashed per optimizer/suite
seed_policy = 'unified';
rand_generator = 'threefry';
use_parallel = false;         % serial by default; set true only after checking worker paths
write_graphs = false;         % false = keep numeric curves/gen_logs, skip slow PNG rendering
overwrite = true;             % true = archive the previous result tree and start clean
% -------------------------------------------------------------------------

suite = 'cec2020';

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
gskcec_require_mex(root, 'run_all_cec2020');

fprintf('\n==================== run_all (CEC2020) ====================\n');
fprintf('suite=%s  functions=%s  dims=%s  runs=%d  seed_policy=%s  rng=%s  parallel=%d  graphs=%d  overwrite=%d  np_init=%s\n', ...
        suite, mat2str(functions), mat2str(dimensions), runs, seed_policy, rand_generator, use_parallel, write_graphs, overwrite, mat2str(np_init));

%% ------------------------------ RUN -------------------------------------
passed_optimizers = {};
for i = 1:numel(optimizers)
    opt = optimizers{i};
    out = fullfile(root, 'results', '_run_all', opt, suite);
    fprintf('\n----- [%d/%d] %s -----\n', i, numel(optimizers), upper(opt));
    try
        run_experiment('optimizer', opt, 'suite', suite, ...
            'functions', functions, 'dimensions', dimensions, 'runs', runs, ...
            'max_nfes', max_nfes, 'np_init', np_init, ...
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
