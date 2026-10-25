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
%   4. plot_convergence draws median curves with IQR bands;
%   5. compare_algorithms writes the runtime table;
%   6. plot_performance gives the hand-computed success rates and ERT on
%      made-up traces, and draws the ECDF and the ERT table;
%   7. make_study_aliases writes sensitivity and ablation aliases with the
%      documented names and settings, and refuses to write them twice.

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

% 5. Runtime table (written by compare_algorithms in part 1).
T = readtable(fullfile(cmp, 'runtime_sphere.csv'), 'TextType', 'char', 'VariableNamingRule', 'preserve');
assert(height(T) == 3 * 2 && all(T.runs == 12) && all(T.mean_seconds >= 0), 'runtime table');
assert(isfile(fullfile(cmp, 'runtime_sphere.tex')) && numel(rep.runtime) == 2, 'runtime tex and report');

% 6. ERT and success rate on hand-made traces (budgets 10, 100, 1000; 4 runs).
pr = fullfile(root, 'perf');
vals = {[5 0.5 0.001; 5 5 5; 1 0.1 0.01; 50 50 0.5], [9 9 9; 9 9 9; 9 9 9; 9 9 0.001]};
for i = 1:2
    gl = fullfile(pr, sprintf('opt-%c', 'a' + i - 1), 'sphere', 'gen_logs'); mkdir(gl);
    fid = fopen(fullfile(gl, sprintf('BestTrace_opt-%c_F1_D10.csv', 'a' + i - 1)), 'w');
    fprintf(fid, 'Run,Seed,E10,E100,E1000\n');
    for r = 1:4; fprintf(fid, '%d,1,%.17g,%.17g,%.17g\n', r, vals{i}(r, :)); end
    fclose(fid);
end
pf = plot_performance('suite', 'sphere', 'optimizers', {'opt-a', 'opt-b'}, 'results_root', pr, ...
    'output_dir', fullfile(pr, 'out'), 'targets', [1 0.01], 'formats', {'png'});
pick = @(o, t) pf.results([pf.results.opt] == o & [pf.results.target] == t);
r1 = pick(1, 1); r2 = pick(1, 0.01); r3 = pick(2, 1);
% opt-a, target 1: runs reach it at 100, never, 10, 1000 -> SR 3/4, ERT (100+1000+10+1000)/3.
assert(abs(r1.sr - 0.75) < 1e-12 && abs(r1.ert - 2110 / 3) < 1e-9, 'ERT/SR target 1');
% opt-a, target 0.01: runs 1 and 3 at 1000 -> ERT 4000/2.
assert(abs(r2.sr - 0.5) < 1e-12 && abs(r2.ert - 2000) < 1e-9, 'ERT/SR target 0.01');
% opt-b, target 1: only run 4, at 1000 -> ERT 4000.
assert(abs(r3.sr - 0.25) < 1e-12 && abs(r3.ert - 4000) < 1e-9, 'ERT/SR opt-b');
assert(isfile(fullfile(pr, 'out', 'ecdf_sphere_D10.png')) && isfile(fullfile(pr, 'out', 'ert_sphere_D10.tex')), ...
       'ECDF figure and ERT table');

% 7. Study aliases: names, the written file, and the refusal to write twice.
ini = fullfile(root, 'study.ini');
n1 = make_study_aliases('sensitivity', 'gsk', {'kf', [0.3 0.5], 'np_init', [50 100]}, 'file', ini, ...
                        'project_root', project_root);
assert(isequal(n1, {'gsk-kf-0p3-npinit-50', 'gsk-kf-0p3-npinit-100', 'gsk-kf-0p5-npinit-50', ...
                    'gsk-kf-0p5-npinit-100'}), 'sensitivity alias names');
n2 = make_study_aliases('ablation', 'egsk', {'use_fmincon'}, 'file', ini, 'project_root', project_root);
assert(isequal(n2, {'egsk-no-use-fmincon'}), 'ablation alias name');
m = read_algorithm_aliases(ini);
al = m('gsk-kf-0p5-npinit-50');
assert(m.Count == 5 && strcmp(al.base, 'gsk') && al.settings.kf == 0.5 && al.settings.np_init == 50, 'written aliases');
assert(islogical(m('egsk-no-use-fmincon').settings.use_fmincon), 'ablation switch is false');
try
    make_study_aliases('ablation', 'egsk', {'use_fmincon'}, 'file', ini, 'project_root', project_root);
    error('test_comparison_tools:noError', 'second write must be refused');
catch err
    assert(strcmp(err.identifier, 'make_study_aliases:exists'), 'refusal id: %s', err.identifier);
end
assert(isequal(make_study_aliases('ablation', 'egsk', {'use_fmincon'}, 'dry_run', true), n2), 'dry run');

fprintf('test_comparison_tools: PASS\n');
end

function remove_dir(d)
%REMOVE_DIR Delete folder d and its contents, if it exists.
if exist(d, 'dir'); rmdir(d, 's'); end
end
