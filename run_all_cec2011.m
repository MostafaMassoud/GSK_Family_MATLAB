% run_all_cec2011.m
% =========================================================================
% Run the GSK-family optimizer(s) on the CEC2011 real-world suite.
%
% HOW TO USE
%   1. Open this file in MATLAB (it sits next to the  gsk_family/  folder).
%   2. Press the green Run button (click "Change Folder" if MATLAB asks).
%   3. Each problem prints one results row; a results table and a
%      Reference-GSK comparison print. The full report is also saved to
%      results/_run_all/<opt>/cec2011/summary/report.txt.
%
% CEC2011 notes: 22 real-world problems with NATIVE (per-problem) dimensions
% and NO known optimum -- statistics are over raw objective values, which can
% be negative. The budget is 150,000 evaluations per problem. Keep
% dimensions = [0] (0 = each problem's own dimension).
% =========================================================================

%% ------------------------------ CONFIG ----------------------------------
optimizers  = {'gsk'};
% optimizers = {'gsk', 'agsk', 'apgsk','fdb-agsk','egsk','atmals-gsk'};

functions   = 4:6;         % 22 real-world problems (none excluded)
dimensions  = 0;            % 0 = each problem's native dimension (required for CEC2011)
runs        = 25;           % CEC2011 protocol (adjust as needed)
max_nfes    = 0;            % 0 = suite default (150,000 evaluations)
% Base seed is centralized in gsk_family/src/runners/run_experiment.m.
% seed_policy:
%   'unified'   -> same seed + same runner-generated X0 + same post-X0 RNG
%                  state per (D,function,run); threefry if available, else twister
%   'reference' -> published-table reproduction; per-optimizer reference rules
%   'native'/'derived' -> optimizer/suite-hashed diagnostic schedules
seed_policy = 'unified';
rand_generator = 'threefry';
use_parallel = true;       % true = parfor run loop; set false for serial troubleshooting
write_graphs = false;      % false = keep numeric curves/gen_logs, skip slow PNG rendering
overwrite = true;          % true = archive previous result tree and start a clean run
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
clear run_experiment;                           % reload updated runner helpers in long MATLAB sessions
% Prerequisite: CEC suites require the C++ gskcec_eval MEX bridge.
% Build first; see build.txt and gsk_family/build.txt for commands.
gskcec_require_mex(root, 'run_all_cec2011');

fprintf('\n==================== run_all (CEC2011) ====================\n');
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
