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
%       ranksum_<suite>.csv            Wilcoxon rank-sum test per function, with
%                                      Holm-adjusted p and the effect size
%                                      (Vargha-Delaney A12, Cliff's delta)
%       wilcoxon_<suite>.csv           Wilcoxon signed-rank test (R+, R-, p)
%       friedman_<suite>.csv           Friedman mean ranks and Iman-Davenport test
%       posthoc_<suite>.csv            post-hoc vs the proposed algorithm:
%                                      Bonferroni-Dunn, Holm, Hochberg, Finner
%       nemenyi_<suite>.csv            Nemenyi critical difference
%       statistics_<suite>.csv         Best, Median, Mean, Worst, SD
%       runtime_<suite>.tex/.csv       seconds per run, mean (SD)
%       settings_<suite>.tex/.csv      code, population sizes and changed
%                                      settings of each compared name
%   gsk_family/results/analysis/statistics/<suite>/   (statistics_figures)
%       cd_<suite>_<D or all or overall>.png/.pdf     critical difference diagram
%       box_... / violin_...           final values of all runs, per function
%                                      and an overview per dimension
%       ranks_<suite>_bars / _radar    Friedman mean ranks per dimension
%       runtime_<suite>                seconds per run
%   gsk_family/results/analysis/performance/<suite>/  (performance = true)
%       performance_<suite>.csv        success rate and ERT per function and target
%       ert_<suite>_<D>.tex            ERT (success rate) table
%       ecdf_<suite>_<D or overall>    ECDF data profiles
%   gsk_family/results/analysis/dynamics/<suite>/     (dynamics = true)
%       diversity_ / xplxpt_ / population_ / parameters_   population dynamics
%   gsk_family/results/analysis/sensitivity/ and ablation/   (when set)
%       plot_sensitivity / plot_ablation tables and figures
%   gsk_family/results/analysis/complexity/<suite>/   (complexity = true)
%       complexity_<suite>.tex/.csv    T0, T1, T2_hat, (T2_hat - T1)/T0
%
% Notes:
%   - Works for every suite and every algorithm with results, including one
%     you added yourself (see gsk_family/docs/research/comparing_algorithms.md)
%     and aliases from algorithms.ini (e.g. 'gsk-np50'): list them in
%     optimizers like any algorithm. settings_<suite>.tex/.csv then shows
%     what each name changed.
%   - It only reads finished results (except complexity = true, which times
%     short runs in a temporary folder). Run it again at any time, also on a
%     partial campaign; it overwrites its own output.
%   - "+" means the proposed algorithm is significantly better than that
%     competitor on that function, "-" significantly worse, "=" no
%     significant difference (two-sided Wilcoxon rank-sum, alpha below).
%   - CEC2013, CEC2017 and CEC2020 curves show the error f(x) - f(x*) on a log
%     axis. CEC2011 and CEC2013-LSGO show raw objective values (linear axis
%     when a value is zero or negative).
%   - Options of the commands it calls: help plot_convergence,
%     help compare_algorithms, help plot_statistics, help cec_complexity
%     (in gsk_family/scripts).

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
                                       % 'mean'/'median' = mean/median over all runs at the 14 CEC checkpoints
band       = 'none';                   % 'iqr' = shaded 25-75% band of all runs under each curve
formats    = {'png', 'pdf'};           % any of 'png', 'pdf', 'eps', 'fig'
overview   = true;                     % also one figure with all functions per dimension
alpha      = 0.05;                     % significance level of the tests
correction = 'none';                   % 'holm' = table signs (+/=/-) from Holm-adjusted rank-sum p-values

statistics_figures = {'cd', 'box', 'ranks', 'runtime'};   % {} = none; CD diagram, box plots, rank and runtime charts (add 'violin' for violins)
performance = true;                    % success rates, ERT tables and ECDF data profiles (smooth with launcher trace_points)
dynamics   = false;                 % true = diversity, exploration/exploitation, population and parameter
                                       % figures; needs runs made with log_trace = true in the launcher

complexity = false;                    % true = also measure the CEC complexity table (T0, T1, T2) for
                                       % cec2017; this RUNS each algorithm 5 x 200,000 evaluations
                                       % per dimension (minutes to hours; keep the PC otherwise idle)

% Optional studies (run their aliases first; see make_study_aliases):
sensitivity = {};                      % e.g. {'gsk', {'kf', [0.3 0.5 0.7]}}  or  {'gsk', {'kf', [0.3 0.5], 'kr', [0.8 0.9]}}
ablation    = {};                      % e.g. {'my-gsk', {'use_step_a', 'use_step_b'}}
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
        plot_convergence(common{:}, 'curve', curve, 'band', band, 'formats', formats, 'overview', overview);
    catch err
        fprintf(2, 'FAIL  %s convergence curves: %s\n', upper(suite), err.message);
    end
    try
        cmp = [common, {'alpha', alpha}];
        if ~isempty(proposed); cmp = [cmp, {'proposed', proposed}]; end %#ok<AGROW>
        compare_algorithms(cmp{:}, 'correction', correction);
    catch err
        fprintf(2, 'FAIL  %s statistics: %s\n', upper(suite), err.message);
    end
    if ~isempty(statistics_figures)
        try
            plot_statistics(cmp{:}, 'correction', correction, 'figures', statistics_figures, 'formats', formats);
        catch err
            fprintf(2, 'FAIL  %s statistics figures: %s\n', upper(suite), err.message);
        end
    end
    pf = {'suite', suite, 'results_root', results_root, 'project_root', root, ...
          'functions', functions, 'dimensions', dimensions, 'formats', formats};
    if ~isempty(optimizers); pf = [pf, {'optimizers', optimizers}]; end %#ok<AGROW>
    if ~isempty(labels);     pf = [pf, {'labels', labels}];         end %#ok<AGROW>
    if performance
        try
            plot_performance(pf{:});
        catch err
            fprintf(2, 'FAIL  %s performance profiles: %s\n', upper(suite), err.message);
        end
    end
    if dynamics
        try
            plot_dynamics(pf{:});
        catch err
            fprintf(2, 'FAIL  %s dynamics: %s\n', upper(suite), err.message);
        end
    end
    if ~isempty(sensitivity)
        try
            plot_sensitivity('suite', suite, 'base', sensitivity{1}, 'spec', sensitivity{2}, ...
                             'results_root', results_root, 'project_root', root, 'formats', formats);
        catch err
            fprintf(2, 'FAIL  %s sensitivity: %s\n', upper(suite), err.message);
        end
    end
    if ~isempty(ablation)
        try
            plot_ablation('suite', suite, 'base', ablation{1}, 'switches', ablation{2}, ...
                          'results_root', results_root, 'project_root', root, 'formats', formats);
        catch err
            fprintf(2, 'FAIL  %s ablation: %s\n', upper(suite), err.message);
        end
    end
    if complexity
        if strcmp(suite, 'cec2017') && ~isempty(optimizers)
            try
                cec_complexity('suite', suite, 'optimizers', optimizers, 'labels', labels, 'project_root', root);
            catch err
                fprintf(2, 'FAIL  %s complexity: %s\n', upper(suite), err.message);
            end
        else
            fprintf(2, ['SKIP  %s complexity: set optimizers explicitly; the complexity table is ' ...
                        'defined for cec2017 (other suites: call cec_complexity with ''function'')\n'], upper(suite));
        end
    end
end

fprintf('\n==================== done ====================\n');
fprintf('Convergence figures under: %s\n', fullfile(root, 'results', 'analysis', 'convergence'));
fprintf('Tables under:              %s\n', fullfile(root, 'results', 'analysis', 'compare'));
fprintf('Statistics figures under:  %s\n', fullfile(root, 'results', 'analysis', 'statistics'));
if performance; fprintf('Performance profiles under: %s\n', fullfile(root, 'results', 'analysis', 'performance')); end
if dynamics; fprintf('Dynamics figures under:    %s\n', fullfile(root, 'results', 'analysis', 'dynamics')); end
if ~isempty(sensitivity); fprintf('Sensitivity under:         %s\n', fullfile(root, 'results', 'analysis', 'sensitivity')); end
if ~isempty(ablation); fprintf('Ablation under:            %s\n', fullfile(root, 'results', 'analysis', 'ablation')); end
if complexity; fprintf('Complexity table under:    %s\n', fullfile(root, 'results', 'analysis', 'complexity')); end

function s = ternary_text(cond, a, b)
if cond; s = a; else; s = b; end
end
