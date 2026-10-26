%RUN_ALL_CEC2013LSGO Run GSK-family optimizers on the CEC2013-LSGO suite.
%
% How to use:
%   1. Open this file in MATLAB (it sits next to the gsk_family/ folder).
%   2. Press the green Run button (click "Change Folder" if MATLAB asks).
%   3. Each problem prints one results row; results print per run. The full
%      report is saved under results/_run_all/<opt>/cec2013lsgo/summary/.
%
% CEC2013-LSGO (large-scale) notes:
%   - 15 problems, each with its own (native) dimension of about 1000.
%   - No known optimum: statistics use raw objective values.
%   - Budget: 3,000,000 evaluations per problem, so a full run is VERY long
%     (3e6 x 15 x runs at about 1000-D).
%   - Keep dimensions = 0 (0 = each problem's own dimension).
%   - Reference tables: the published DECC-G and MOS results (not GSK
%     members) and the imported DT-GSK tables (one per native dimension,
%     D1000/D905). For DT-GSK the in-run comparison table merges those
%     per-dimension tables.
%   - DT-GSK uses the unified seed and threefry under every seed_policy, and
%     samples its own NP = 5*D initial population (it ignores the runner X0).
%   - np_init (CONFIG) sets the initial population size of every optimizer,
%     DT-GSK included; min_pop_size sets the final size of the four that
%     shrink their population. [] keeps each default.

%% ------------------------------ CONFIG ----------------------------------
optimizers  = {'gsk'};
% optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk', 'dt-gsk'};
% Aliases from algorithms.ini (next to this file) work too, e.g. {'gsk', 'gsk-np50'}:
% the same code under other settings, with its own results folder.

functions   = 1:15;        % CEC2013-LSGO has 15 problems
dimensions  = 0;           % 0 = each problem's native (large-scale) dimension
runs         = 25;         % LSGO protocol (start with 1-3 for a quick check)
max_nfes    = 0;           % 0 = suite default (3,000,000 evaluations)
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
use_parallel = false;      % serial by default; set true only after checking worker paths
write_graphs = false;      % false = keep numeric curves/gen_logs, skip slow PNG rendering
overwrite = true;          % true = archive the previous result tree and start clean
%trace_points = 50;          % optional: log each run's best value at 50 budgets (smooth ERT/ECDF curves)
%log_trace = true;            % optional: record each run's diversity and adaptive parameters (plot_dynamics)
% -------------------------------------------------------------------------
% trace_points: 0 (no extra log) unless set in CONFIG above.
if ~exist('trace_points', 'var'); trace_points = 0; end
if ~exist('log_trace', 'var'); log_trace = false; end

suite = 'cec2013lsgo';

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
gskcec_require_mex(root, 'run_all_cec2013lsgo');

fprintf('\n==================== run_all (CEC2013LSGO) ====================\n');
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
            'write_graphs', write_graphs, 'trace_points', trace_points, 'log_trace', log_trace);
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
