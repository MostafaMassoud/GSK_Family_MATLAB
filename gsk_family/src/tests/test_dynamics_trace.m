function test_dynamics_trace()
%TEST_DYNAMICS_TRACE Opt-in per-generation trace (log_trace) of every optimizer.
%
% On the sphere suite (no MEX), checks that:
%   1. gsk_trace_add computes the documented diversity on a known population;
%   2. every optimizer gives exactly the same results with and without
%      options.log_trace, and returns result.trace only when it is on, with
%      its documented columns (rows of nfes, np, diversity and parameters);
%   3. run_experiment(..., 'log_trace', true) writes
%      trace/Dynamics_<name>_F<f>_D<d>.csv with at most trace_rows rows per
%      run and leaves per_run.csv identical to an untraced run;
%   4. plot_dynamics draws the diversity, exploration/exploitation,
%      population and parameter figures and the XPL/XPT table.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
addpath(fullfile(project_root, 'src', 'common'));
addpath(genpath(fullfile(project_root, 'src', 'optimizers')));
addpath(fullfile(project_root, 'scripts'));
root = fullfile(tempdir, sprintf('gskcec_dynamics_%d', feature('getpid')));
if exist(root, 'dir'); rmdir(root, 's'); end
cleanup = onCleanup(@() remove_dir(root)); %#ok<NASGU>

% 1. Diversity on a known population: median [1 1], mean |x - median| = 2/3
% per dimension, range 4 -> 1/6.
tr = gsk_trace_start(struct('log_trace', true), 2);
tr = gsk_trace_add(tr, 30, [0 0; 1 1; 2 2], [0 0], [4 4]);
t = gsk_trace_finish(tr);
assert(abs(t.rows(1, 3) - 1 / 6) < 1e-15 && t.rows(1, 2) == 3 && t.rows(1, 1) == 30, 'diversity formula');
assert(isempty(gsk_trace_finish(gsk_trace_start(struct(), 5))), 'trace off -> []');

% 2. Every optimizer: identical results with tracing on, documented columns.
setup = {'gsk', {}; 'agsk', {'kw1', 'kw2', 'kw3', 'kw4'}; ...
         'apgsk', {'kw1', 'kw2', 'kw3', 'kw4', 'kf_mean', 'kr_mean', 'd_junior'}; ...
         'fdb_agsk', {'kw1', 'kw2', 'kw3', 'kw4'}; 'atmals_gsk', {'kf', 'kr', 'k', 'p', 'pls'}; ...
         'egsk', {'kf1_mean', 'kf2_mean', 'ip_refine'}; ...
         'dt_gsk', {'kf_mean', 'kr_mean', 'acceptance', 'restarts', 'polish_done', 'deep_restart'}};
has_fmincon = license('test', 'Optimization_Toolbox') && ~isempty(ver('optim'));
for k = 1:size(setup, 1)
    name = setup{k, 1};
    if strcmp(name, 'egsk') && ~has_fmincon; continue; end
    p = gskcec_make_problem('sphere', 1, 10, project_root, 3000);
    r0 = feval([name '_optimize'], p, struct('seed', 9));
    r1 = feval([name '_optimize'], p, struct('seed', 9, 'log_trace', true));
    assert(~isfield(r0, 'trace'), '%s: no trace without log_trace', name);
    same = isequal(r0.best_x, r1.best_x) && isequal(r0.best_fitness, r1.best_fitness) && ...
           isequal(r0.nfes, r1.nfes) && isequal(r0.convergence, r1.convergence);
    assert(same, '%s: log_trace changed the run', name);
    want = [{'nfes', 'np', 'diversity'}, setup{k, 2}];
    assert(isequal(r1.trace.names, want), '%s: trace columns', name);
    T = r1.trace.rows;
    assert(size(T, 1) >= 2 && all(diff(T(:, 1)) >= 0) && all(T(:, 3) >= 0 & T(:, 3) <= 1), ...
           '%s: trace rows (nfes non-decreasing, diversity in [0, 1])', name);
end

% 3. Through the runner.
common = {'suite', 'sphere', 'functions', 1, 'dimensions', 10, 'runs', 3, 'base_seed', 5, ...
          'max_nfes', 3000, 'project_root', project_root, 'verbose', false};
for o = {'gsk', 'agsk', 'dt-gsk'}
    run_experiment('optimizer', o{1}, common{:}, 'output_dir', fullfile(root, 'plain', o{1}, 'sphere'));
    run_experiment('optimizer', o{1}, common{:}, 'output_dir', fullfile(root, 'traced', o{1}, 'sphere'), ...
                   'log_trace', true, 'trace_rows', 20);
    A = readtable(fullfile(root, 'plain', o{1}, 'sphere', 'summary', 'per_run.csv'), 'VariableNamingRule', 'preserve');
    B = readtable(fullfile(root, 'traced', o{1}, 'sphere', 'summary', 'per_run.csv'), 'VariableNamingRule', 'preserve');
    assert(isequal(A.best_fitness, B.best_fitness), '%s: runner results changed by log_trace', o{1});
    f = fullfile(root, 'traced', o{1}, 'sphere', 'trace', sprintf('Dynamics_%s_F1_D10.csv', o{1}));
    assert(isfile(f), 'missing %s', f);
    M = readmatrix(f, 'NumHeaderLines', 1);
    assert(isequal(unique(M(:, 1))', 1:3) && all(accumarray(M(:, 1), 1) <= 20), '%s: trace rows per run', o{1});
    assert(~exist(fullfile(root, 'plain', o{1}, 'sphere', 'trace'), 'dir'), 'no trace folder without log_trace');
end

% 4. Figures.
rep = plot_dynamics('suite', 'sphere', 'optimizers', {'gsk', 'agsk', 'dt-gsk'}, ...
    'results_root', fullfile(root, 'traced'), 'output_dir', fullfile(root, 'fig'), 'formats', {'png'});
need = {'diversity_sphere_F1_D10.png', 'xplxpt_sphere_F1_D10.png', 'population_sphere_D10.png', ...
        'parameters_sphere_agsk_D10.png', 'parameters_sphere_dt-gsk_D10.png', 'xplxpt_sphere.csv'};
for k = 1:numel(need)
    assert(isfile(fullfile(root, 'fig', need{k})), 'missing %s', need{k});
end
assert(numel(rep.figures) == 5, 'gsk has no parameters, so no parameter figure');
X = readtable(fullfile(root, 'fig', 'xplxpt_sphere.csv'), 'VariableNamingRule', 'preserve');
assert(all(abs(X.mean_xpl_percent + X.mean_xpt_percent - 100) < 0.02), 'XPL + XPT = 100');

fprintf('test_dynamics_trace: PASS\n');
end

function remove_dir(d)
%REMOVE_DIR Delete folder d and its contents, if it exists.
if exist(d, 'dir'); rmdir(d, 's'); end
end
