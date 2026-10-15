% run_all_cec2013lsgo.m
% =========================================================================
% Run the GSK-family optimizer(s) on the CEC2013 Large-Scale (LSGO) suite.
%
% HOW TO USE
%   1. Open this file in MATLAB (it sits next to the  gsk_family/  folder).
%   2. Press the green Run button (click "Change Folder" if MATLAB asks).
%   3. Each problem prints one results row; results print per run. The full
%      report is saved under results/_run_all/<opt>/cec2013lsgo/summary/.
%
% CEC2013LSGO notes: 15 large-scale problems with NATIVE (~1000-D) dimensions
% and NO known optimum -- statistics are over raw objective values. The budget
% is 3,000,000 evaluations per problem, so this is VERY long (3e6 x 15 x runs
% at ~1000-D). Keep dimensions = [0] (0 = each problem's own dimension). The
% published references are DECC-G / MOS (not GSK members) plus the imported
% DT-GSK tables (one per native dimension, D1000/D905). The in-run comparison
% table looks for a single native-dims table, so it is skipped here -- results
% are still written. DT-GSK runs the unified seed + threefry under every
% seed_policy and samples its own NP = 5*D initial population (it ignores the
% runner X0).
% =========================================================================

%% ------------------------------ CONFIG ----------------------------------
optimizers  = {'gsk'};
% optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk', 'dt-gsk'};

functions   = 1:15;        % CEC2013 LSGO has 15 problems
dimensions  = 0;           % 0 = each problem's native (large-scale) dimension
runs         = 25;         % LSGO protocol (start with 1-3 for a quick check)
max_nfes    = 0;           % 0 = suite default (3,000,000 evaluations)
% Base seed is centralized in gsk_family/src/runners/run_experiment.m.
% seed_policy:
%   'unified'   -> same seed + same runner-generated X0 + same post-X0 RNG
%                  state per (D,function,run); threefry if available, else twister
%   'reference' -> published-table reproduction; per-optimizer reference rules
%   'native'/'derived' -> optimizer/suite-hashed diagnostic schedules
seed_policy = 'unified';
rand_generator = 'threefry';
use_parallel = false;      % serial by default; set true only after validating worker paths
write_graphs = false;      % false = keep numeric curves/gen_logs, skip slow PNG rendering
overwrite = true;          % true = archive previous result tree and start a clean run
% -------------------------------------------------------------------------

suite = 'cec2013lsgo';

%% ------------------------------ SET UP ----------------------------------
root = fullfile(fileparts(mfilename('fullpath')), 'gsk_family');
src_dir = fullfile(root, 'src');
if ~isfolder(src_dir)
    error('run_all:missingSource', 'GSK source folder not found: %s', src_dir);
end
addpath(genpath(src_dir));                      % optimizers, runners, helpers
rehash;
clear run_experiment gskcec_make_problem;       % reload updated runner helpers in long MATLAB sessions
% Prerequisite: CEC suites require the C++ gskcec_eval MEX bridge.
% Build first; see build.txt and gsk_family/build.txt for commands.
gskcec_require_mex(root, 'run_all_cec2013lsgo');

fprintf('\n==================== run_all (CEC2013LSGO) ====================\n');
fprintf('suite=%s  functions=%s  dims=%s  runs=%d  seed_policy=%s  rng=%s  parallel=%d  graphs=%d  overwrite=%d\n', ...
        suite, mat2str(functions), mat2str(dimensions), runs, seed_policy, rand_generator, use_parallel, write_graphs, overwrite);

%% ------------------------------ RUN -------------------------------------
passed_optimizers = {};
for i = 1:numel(optimizers)
    opt = optimizers{i};
    out = fullfile(root, 'results', '_run_all', opt, suite);
    fprintf('\n----- [%d/%d] %s -----\n', i, numel(optimizers), upper(opt));
    try
        run_experiment('optimizer', opt, 'suite', suite, ...
            'functions', functions, 'dimensions', dimensions, 'runs', runs, ...
            'max_nfes', max_nfes, ...
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
    % Confirms the files written by successful optimizers really used identical
    % seeds for each (D,function,run); catches accidental policy drift.
    verify_unified_seed_schedule(fullfile(root, 'results', '_run_all'), passed_optimizers, suite);
end

fprintf('\n==================== done ====================\n');
fprintf('Results under: %s\n', fullfile(root, 'results', '_run_all'));
