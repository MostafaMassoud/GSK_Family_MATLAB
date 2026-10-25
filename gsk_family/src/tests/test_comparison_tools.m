function test_comparison_tools()
%TEST_COMPARISON_TOOLS compare_algorithms, plot_statistics and plot_convergence on sphere runs.
%
% Runs gsk, agsk and apgsk on the sphere suite (no MEX), then checks that:
%   1. compare_algorithms writes the post-hoc, Nemenyi and effect-size
%      outputs: Holm/Hochberg/Finner/Bonferroni-Dunn p-values are >= the
%      unadjusted ones and <= 1, Holm <= Bonferroni-Dunn, the Nemenyi q for
%      k = 3 at alpha 0.05 is Demsar's 2.343, Cliff's delta = 2*A12 - 1, and
%      the Iman-Davenport p-value is in [0, 1];
%   2. 'correction','holm' gives table signs no more significant than the
%      raw ones;
%   3. plot_statistics draws the CD diagram, box, violin and rank figures;
%   4. plot_convergence draws median curves with IQR bands.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
addpath(fullfile(project_root, 'scripts'));
root = fullfile(tempdir, sprintf('gskcec_cmp_tools_%d', feature('getpid')));
if exist(root, 'dir'); rmdir(root, 's'); end
cleanup = onCleanup(@() remove_dir(root)); %#ok<NASGU>
names = {'gsk', 'agsk', 'apgsk'};
for i = 1:numel(names)
    run_experiment('optimizer', names{i}, 'suite', 'sphere', 'functions', 1, 'dimensions', [5 10], ...
        'runs', 12, 'base_seed', 7, 'max_nfes', 1500, 'project_root', project_root, ...
        'output_dir', fullfile(root, names{i}, 'sphere'), 'verbose', false);
end

% 1. Tables.
cmp = fullfile(root, 'cmp');
rep = compare_algorithms('suite', 'sphere', 'optimizers', names, 'results_root', root, 'output_dir', cmp);
P = readtable(fullfile(cmp, 'posthoc_sphere.csv'), 'TextType', 'char', 'VariableNamingRule', 'preserve');
assert(height(P) == 3 * 2, 'posthoc rows: 2 competitors x (2 dimensions + overall)');
adj = [P.p_bonferroni_dunn, P.p_holm, P.p_hochberg, P.p_finner];
assert(all(adj(:) >= repmat(P.p_unadjusted, 4, 1) - 1e-12) && all(adj(:) <= 1), 'adjusted p range');
assert(all(P.p_holm <= P.p_bonferroni_dunn + 1e-12), 'Holm <= Bonferroni-Dunn');
N = readtable(fullfile(cmp, 'nemenyi_sphere.csv'), 'TextType', 'char', 'VariableNamingRule', 'preserve');
assert(all(abs(N.q_alpha - 2.343) < 1e-3), 'Nemenyi q(k=3, 0.05) = 2.343');
assert(all(abs(N.critical_difference - N.q_alpha .* sqrt(3 * 4 ./ (6 * N.n_functions))) < 1e-3), 'CD formula');
R = readtable(fullfile(cmp, 'ranksum_sphere.csv'), 'TextType', 'char', 'VariableNamingRule', 'preserve');
assert(all(abs(R.cliffs_delta - (2 * R.a12 - 1)) < 1e-3) && all(R.a12 >= 0 & R.a12 <= 1), 'A12 / delta');
assert(all(R.p_holm >= R.p_value - 1e-12), 'Holm-adjusted rank-sum p >= raw p');
F = readtable(fullfile(cmp, 'friedman_sphere.csv'), 'TextType', 'char', 'VariableNamingRule', 'preserve');
ok = isnan(F.id_p_value) | (F.id_p_value >= 0 & F.id_p_value <= 1);
assert(all(ok), 'Iman-Davenport p in [0, 1]');
assert(isfield(rep, 'overall_posthoc') && numel(rep.overall_posthoc) == 2, 'overall post-hoc in the report');

% 2. Holm signs are never more significant than raw signs.
rep_h = compare_algorithms('suite', 'sphere', 'optimizers', names, 'results_root', root, ...
                           'output_dir', fullfile(root, 'cmp_holm'), 'correction', 'holm');
for g = 1:numel(rep.groups)
    raw = sum(arrayfun(@(w) sum(w.wtl([1 3])), rep.groups(g).wilcoxon));
    hol = sum(arrayfun(@(w) sum(w.wtl([1 3])), rep_h.groups(g).wilcoxon));
    assert(hol <= raw, 'Holm signs must not add significant results');
end

% 3. Statistics figures.
st = plot_statistics('suite', 'sphere', 'optimizers', names, 'results_root', root, ...
    'output_dir', fullfile(root, 'stat'), 'compare_dir', fullfile(root, 'cmp_stat'), ...
    'figures', {'cd', 'box', 'violin', 'ranks'}, 'formats', {'png'});
need = {'cd_sphere_D5.png', 'cd_sphere_overall.png', 'box_sphere_F1_D10.png', ...
        'violin_sphere_F1_D10.png', 'box_sphere_D5_overview.png', 'ranks_sphere_bars.png'};
for k = 1:numel(need)
    assert(isfile(fullfile(root, 'stat', need{k})), 'missing figure %s', need{k});
end
assert(numel(st.figures) >= numel(need), 'plot_statistics report');

% 4. Convergence with IQR bands.
cv = plot_convergence('suite', 'sphere', 'optimizers', names, 'results_root', root, ...
    'output_dir', fullfile(root, 'conv'), 'curve', 'median', 'band', 'iqr', 'formats', {'png'});
assert(isfile(fullfile(root, 'conv', 'sphere_F1_D10.png')) && isempty(cv.incomplete), 'banded curves');

fprintf('test_comparison_tools: PASS\n');
end

function remove_dir(d)
%REMOVE_DIR Delete folder d and its contents, if it exists.
if exist(d, 'dir'); rmdir(d, 's'); end
end
