%RUN_COMPARE_ALGORITHMS Convergence curves and statistical analysis of finished runs.
%
% How to use:
%   1. Run the algorithms first with the run_all_cec*.m launchers (same
%      functions, dimensions and runs for every algorithm).
%   2. Open this file in MATLAB (it sits next to the gsk_family/ folder).
%   3. Edit the CONFIG block below: which suites, which algorithms, and
%      which one is your proposed algorithm.
%   4. Press the green Run button (click "Change Folder" if MATLAB asks).
%
% For each suite it writes:
%   gsk_family/results/analysis/convergence/<suite>/
%       <suite>_F<f>_D<d>.png/.pdf     every algorithm's curve, one figure per
%                                      function and dimension
%       <suite>_D<d>_overview.png/.pdf all functions of one dimension
%                                      (<suite>_all_overview for CEC2011 and
%                                      CEC2013-LSGO)
%   gsk_family/results/analysis/compare/<suite>/
%       table_<suite>_D<d>.tex/.csv    Mean (SD) per function, best mean in
%                                      bold, +/=/- per competitor
%       ranksum_<suite>.csv            Wilcoxon rank-sum test per function
%       wilcoxon_<suite>.csv           Wilcoxon signed-rank test (R+, R-, p)
%       friedman_<suite>.csv           Friedman mean ranks
%       statistics_<suite>.csv         Best, Median, Mean, Worst, SD
%
% Notes:
%   - Works for every suite and every algorithm with results, including one
%     you added yourself (see gsk_family/docs/research/comparing_algorithms.md).
%   - It only reads finished results; it never runs an algorithm. Run it again
%     at any time, also on a partial campaign; it overwrites its own output.
%   - "+" means the proposed algorithm is significantly better than that
%     competitor on that function, "-" significantly worse, "=" no
%     significant difference (two-sided Wilcoxon rank-sum, alpha below).
%   - CEC2013, CEC2017 and CEC2020 curves show the error f(x) - f(x*) on a log
%     axis. CEC2011 and CEC2013-LSGO show raw objective values (linear axis
%     when a value is zero or negative).
%   - Options of the two commands it calls: help plot_convergence,
%     help compare_algorithms (in gsk_family/scripts).

%% ------------------------------ CONFIG ----------------------------------

suites     = {'cec2017', 'cec2011'};   % any of 'cec2011','cec2013','cec2013lsgo','cec2017','cec2020'

optimizers = {};                       % {} = every algorithm with results for the suite
%optimizers = {'my-gsk', 'gsk'};        % e.g. your variant and GSK (first = legend/table order)
%optimizers = {'gsk', 'agsk', 'apgsk', 'fdb-agsk', 'atmals-gsk', 'egsk', 'dt-gsk'};

labels     = {};                       % names in legends and tables; {} = GSK, AGSK, ..., or the name in capitals
%labels     = {'Proposed', 'GSK'};      % one per entry of optimizers

proposed   = '';                       % algorithm tested against all others; '' = the first of optimizers
%proposed   = 'my-gsk';

functions  = [];                       % [] = all functions found; e.g. [1 5 10]
dimensions = [];                       % [] = all dimensions found; e.g. [10 30]; ignored for CEC2011 and CEC2013-LSGO

curve      = 'median_run';             % 'median_run' = full trace of each algorithm's median run
                                       % 'mean'       = mean over all runs at the 14 CEC checkpoints
formats    = {'png', 'pdf'};           % any of 'png', 'pdf', 'eps', 'fig'
overview   = true;                     % also one figure with all functions per dimension
alpha      = 0.05;                     % significance level of the Wilcoxon tests
% -------------------------------------------------------------------------

%% ------------------------------ SET UP ----------------------------------
root = fullfile(fileparts(mfilename('fullpath')), 'gsk_family');
if ~isfolder(fullfile(root, 'scripts'))
    error('run_compare:missingSource', 'gsk_family/scripts not found under %s', fileparts(root));
end
addpath(fullfile(root, 'scripts'));
results_root = fullfile(root, 'results', '_run_all');   % where the launchers write

fprintf('\n==================== run_compare_algorithms ====================\n');
fprintf('suites=%s  optimizers=%s  proposed=%s  curve=%s\n', strjoin(suites, ','), ...
        ternary_text(isempty(optimizers), 'all found', strjoin(optimizers, ',')), ...
        ternary_text(isempty(proposed), 'first', proposed), curve);

%% ------------------------------ RUN -------------------------------------
for s = 1:numel(suites)
    suite = suites{s};
    fprintf('\n----- [%d/%d] %s -----\n', s, numel(suites), upper(suite));
    if ~isfolder(results_root)
        fprintf(2, 'SKIP  %s: no results under %s (run the launchers first)\n', upper(suite), results_root);
        continue;
    end
    common = {'suite', suite, 'results_root', results_root, 'project_root', root, ...
              'functions', functions, 'dimensions', dimensions};
    if ~isempty(optimizers); common = [common, {'optimizers', optimizers}]; end %#ok<AGROW>
    if ~isempty(labels);     common = [common, {'labels', labels}];         end %#ok<AGROW>
    try
        plot_convergence(common{:}, 'curve', curve, 'formats', formats, 'overview', overview);
    catch err
        fprintf(2, 'FAIL  %s convergence curves: %s\n', upper(suite), err.message);
    end
    try
        cmp = [common, {'alpha', alpha}];
        if ~isempty(proposed); cmp = [cmp, {'proposed', proposed}]; end %#ok<AGROW>
        compare_algorithms(cmp{:});
    catch err
        fprintf(2, 'FAIL  %s statistics: %s\n', upper(suite), err.message);
    end
end

fprintf('\n==================== done ====================\n');
fprintf('Figures under: %s\n', fullfile(root, 'results', 'analysis', 'convergence'));
fprintf('Tables under:  %s\n', fullfile(root, 'results', 'analysis', 'compare'));

function s = ternary_text(cond, a, b)
if cond; s = a; else; s = b; end
end
