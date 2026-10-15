function analyze_results(varargin)
%ANALYZE_RESULTS Statistics and figures comparing generated runs to references.
%
%   analyze_results('project_root','<root>', 'results_root','<root>/results', ...
%                   'reference_root','<root>/benchmarks/cec_reference_results', ...
%                   'output_dir','<root>/results/analysis')
%
% Reads the per-dimension summary tables under results_root
% (<optimizer>/<suite>/summary/<optimizer>_<suite>_D<dim>.csv, or the
% dimensionless rollup for native-dim suites), aligns each (optimizer, suite,
% dimension) with the matching imported reference table, and produces:
%   <output_dir>/comparison_table.csv   per-function generated vs reference mean
%   <output_dir>/friedman_ranks.csv     average Friedman rank per optimizer
%   <output_dir>/wilcoxon_vs_reference.csv  signed-rank p-value per optimizer
%   <output_dir>/fig_<suite>_D<dim>_boxplot.pdf      error spread per optimizer
%   <output_dir>/fig_<suite>_D<dim>_convergence.pdf  a convergence curve if present
%
% Statistics are implemented WITHOUT the Statistics and Machine Learning
% Toolbox (no Python anywhere): the Friedman chi-square uses base `gammainc`
% for its p-value and the Wilcoxon signed-rank uses base `erfc` for the normal
% approximation. Methods follow Derrac et al. (2011), "A practical tutorial on
% the use of nonparametric statistical tests..." Swarm and Evol. Comput.
%
% Lower error is better throughout. The script degrades gracefully: whatever
% optimizers/suites are present in results_root are analyzed; missing data is
% reported, never invented.

p = inputParser;
p.addParameter('project_root', pwd, @ischar);
p.addParameter('results_root', '', @ischar);
p.addParameter('reference_root', '', @ischar);
p.addParameter('output_dir', '', @ischar);
p.parse(varargin{:});
a = p.Results;
if isempty(a.results_root);   a.results_root = fullfile(a.project_root, 'results'); end
if isempty(a.reference_root); a.reference_root = fullfile(a.project_root, 'benchmarks', 'cec_reference_results'); end
if isempty(a.output_dir);     a.output_dir = fullfile(a.results_root, 'analysis'); end
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end

runs = load_all_summaries(a.results_root);
if isempty(runs)
    fprintf('analyze_results: no summary tables found under %s\n', a.results_root);
    return;
end
fprintf('analyze_results: %d (optimizer,suite,dimension) run(s) found\n', numel(runs));

% Group runs by (suite, dimension) so optimizers are compared on a common set.
keys = arrayfun(@(r) sprintf('%s|D%d', r.suite, r.dim), runs, 'UniformOutput', false);
[ukeys, ~, idx] = unique(keys);

comp_fid = fopen(fullfile(a.output_dir, 'comparison_table.csv'), 'w');
fri_fid  = fopen(fullfile(a.output_dir, 'friedman_ranks.csv'), 'w');
wil_fid  = fopen(fullfile(a.output_dir, 'wilcoxon_vs_reference.csv'), 'w');
fprintf(comp_fid, 'suite,dimension,optimizer,function,generated_mean,reference_mean\n');
fprintf(fri_fid,  'suite,dimension,optimizer,avg_friedman_rank,n_functions,chi2,df,p_value\n');
fprintf(wil_fid,  'suite,dimension,optimizer,n_functions,wilcoxon_W,z,p_value,verdict_vs_reference\n');

for g = 1:numel(ukeys)
    group = runs(idx == g);
    suite = group(1).suite;
    dim = group(1).dim;
    fprintf('\n== %s D%d : %d optimizer(s) ==\n', suite, dim, numel(group));

    % Build the optimizer x function matrix of mean errors over the common
    % functions present for every optimizer in this group.
    common_funcs = group(1).functions;
    for i = 2:numel(group)
        common_funcs = intersect(common_funcs, group(i).functions);
    end
    common_funcs = sort(common_funcs);
    if isempty(common_funcs)
        fprintf('   (no common functions across optimizers; skipped)\n');
        continue;
    end
    k = numel(group);
    nF = numel(common_funcs);
    M = zeros(nF, k);  % rows=functions, cols=optimizers
    names = strings(1, k);
    for i = 1:k
        names(i) = group(i).optimizer;
        for f = 1:nF
            M(f, i) = group(i).mean_for(common_funcs(f));
        end
    end

    % Per-function generated vs reference, and the Wilcoxon signed-rank of each
    % optimizer's means against the reference means across functions.
    for i = 1:k
        ref = load_reference_means(a.reference_root, suite, names(i), dim, common_funcs);
        gen = M(:, i);
        for f = 1:nF
            fprintf(comp_fid, '%s,%d,%s,%d,%.10e,%s\n', suite, dim, names(i), ...
                    common_funcs(f), gen(f), num_or_blank(ref(f)));
        end
        valid = ~isnan(ref);
        if nnz(valid) >= 5
            [W, z, pv] = wilcoxon_signed_rank(gen(valid), ref(valid));
            if pv >= 0.05
                verdict = 'comparable';
            elseif median(gen(valid) - ref(valid)) < 0
                verdict = 'better_than_reference';
            else
                verdict = 'worse_than_reference';
            end
            fprintf(wil_fid, '%s,%d,%s,%d,%.4g,%.4g,%.4g,%s\n', suite, dim, names(i), ...
                    nnz(valid), W, z, pv, verdict);
        else
            fprintf(wil_fid, '%s,%d,%s,%d,NaN,NaN,NaN,insufficient_reference\n', ...
                    suite, dim, names(i), nnz(valid));
        end
    end

    % Friedman ranks across optimizers (needs k >= 2).
    if k >= 2
        [avg_rank, chi2, df, pv] = friedman_ranks(M);
        for i = 1:k
            fprintf(fri_fid, '%s,%d,%s,%.4f,%d,%.4g,%d,%.4g\n', suite, dim, names(i), ...
                    avg_rank(i), nF, chi2, df, pv);
            fprintf('   %-12s avg rank %.3f\n', names(i), avg_rank(i));
        end
        fprintf('   Friedman chi2=%.4g df=%d p=%.4g\n', chi2, df, pv);
    end

    make_boxplot(M, names, suite, dim, a.output_dir);
    make_convergence_plot(group, suite, dim, a.output_dir);
end

fclose(comp_fid); fclose(fri_fid); fclose(wil_fid);
fprintf('\nanalyze_results: wrote tables and figures to %s\n', a.output_dir);
end

% ---- statistics (toolbox-free) ---------------------------------------------

function [avg_rank, chi2, df, pv] = friedman_ranks(M)
% M is nF x k (rows=problems, cols=algorithms); lower is better.
[nF, k] = size(M);
R = zeros(nF, k);
for f = 1:nF
    R(f, :) = tiedrank(M(f, :));  % 1 = best (smallest error)
end
avg_rank = mean(R, 1);
chi2 = 12 * nF / (k * (k + 1)) * sum((avg_rank - (k + 1) / 2) .^ 2);
df = k - 1;
% chi-square upper-tail p-value via base gammainc: chi2cdf(x,df)=gammainc(x/2,df/2)
pv = 1 - gammainc(chi2 / 2, df / 2);
end

function [W, z, pv] = wilcoxon_signed_rank(x, y)
% Paired signed-rank of x vs y; normal approximation with continuity
% correction (base MATLAB only).
d = x - y;
d = d(d ~= 0);
n = numel(d);
if n == 0
    W = 0; z = 0; pv = 1; return;
end
r = tiedrank(abs(d));
W = sum(r(d > 0));                 % sum of positive ranks
mu = n * (n + 1) / 4;
sigma = sqrt(n * (n + 1) * (2 * n + 1) / 24);
z = (W - mu - 0.5 * sign(W - mu)) / sigma;
pv = erfc(abs(z) / sqrt(2));       % two-sided normal p-value
end

% ---- figures ----------------------------------------------------------------

function make_boxplot(M, names, suite, dim, out_dir)
try
    f = figure('Visible', 'off', 'Position', [100 100 700 420]);
    ax = axes(f); hold(ax, 'on');
    for i = 1:size(M, 2)
        col = M(:, i);
        boxchart(ax, i * ones(size(col)), col);
    end
    set(ax, 'XTick', 1:numel(names), 'XTickLabel', cellstr(names));
    if all(M(:) > 0)
        set(ax, 'YScale', 'log');
    end
    ylabel(ax, 'mean error per function'); xlabel(ax, 'optimizer');
    title(ax, sprintf('%s  D%d  (n=%d functions)', suite, dim, size(M, 1)), 'Interpreter', 'none');
    grid(ax, 'on');
    exportgraphics(f, fullfile(out_dir, sprintf('fig_%s_D%d_boxplot.pdf', suite, dim)));
    close(f);
catch err
    fprintf('   (boxplot skipped: %s)\n', err.message);
end
end

function make_convergence_plot(group, suite, dim, out_dir)
try
    % A function whose median-run curve is present for every optimizer.
    common = [];
    for i = 1:numel(group)
        C = group(i).convergence;
        if isempty(C) || C.Count == 0; common = []; break; end
        ks = cell2mat(keys(C));
        if isempty(common); common = ks; else; common = intersect(common, ks); end
    end
    if isempty(common); return; end
    fsel = min(common);

    f = figure('Visible', 'off', 'Position', [100 100 700 420]);
    ax = axes(f); hold(ax, 'on');
    plotted = false;
    for i = 1:numel(group)
        C = group(i).convergence;
        if ~isKey(C, fsel); continue; end
        M = C(fsel);   % columns [Eval, BestError]
        plot(ax, M(:, 1), max(M(:, 2), realmin), 'DisplayName', char(group(i).optimizer));
        plotted = true;
    end
    if ~plotted; close(f); return; end
    set(ax, 'YScale', 'log'); grid(ax, 'on');
    xlabel(ax, 'function evaluations'); ylabel(ax, 'best error');
    title(ax, sprintf('%s  D%d  convergence (F%d, median run)', suite, dim, fsel), 'Interpreter', 'none');
    legend(ax, 'Interpreter', 'none', 'Location', 'northeast');
    exportgraphics(f, fullfile(out_dir, sprintf('fig_%s_D%d_convergence.pdf', suite, dim)));
    close(f);
catch err
    fprintf('   (convergence plot skipped: %s)\n', err.message);
end
end

% ---- data loading -----------------------------------------------------------

function T = read_csv(path)
% readtable that keeps the original headers but renames the reserved word
% 'function' (a MATLAB keyword) to 'func' so it can be dot-accessed.
T = readtable(path, 'CommentStyle', '#', 'VariableNamingRule', 'preserve');
vn = T.Properties.VariableNames;
hit = find(strcmp(vn, 'function'), 1);
if ~isempty(hit)
    vn{hit} = 'func';
    T.Properties.VariableNames = vn;
end
end

function runs = load_all_summaries(results_root)
% Walk the CEC layout results/<optimizer>/<suite>/summary/*.csv
% (Function,Best,Median,Mean,Worst,SD). Optimizer/suite come from the path.
% For fixed-dimension suites (cec2017/cec2020/cec2013) the per-dimension files
% <opt>_<suite>_D<dim>.csv are used (dim from the filename). For native-dimension
% suites (cec2011, cec2013lsgo) the per-function dimensions differ, so the
% per-dim files each hold only a few functions and would never let two
% optimizers share a comparison group; instead the dimensionless rollup
% <opt>_<suite>.csv (all functions, each once) is loaded under dim = 0 so the
% whole suite forms a single cross-optimizer group. per_run.csv is skipped.
runs = struct('optimizer', {}, 'suite', {}, 'dim', {}, 'functions', {}, ...
              'means', {}, 'mean_for', {}, 'convergence', {});
listing = dir(fullfile(results_root, '**', 'summary', '*.csv'));
for i = 1:numel(listing)
    name = listing(i).name;
    if strcmpi(name, 'per_run.csv'); continue; end
    summary_dir = listing(i).folder;
    suite_dir = fileparts(summary_dir);
    opt_dir = fileparts(suite_dir);
    [~, suite] = fileparts(suite_dir);
    [~, optimizer] = fileparts(opt_dir);

    native = any(strcmp(suite, {'cec2011', 'cec2013lsgo'}));
    tok = regexp(name, '_D(\d+)\.csv$', 'tokens', 'once');
    if native
        if ~isempty(tok); continue; end   % skip the per-dim files; use the rollup
        dim = 0;                           % synthetic "all native dimensions" group
    else
        if isempty(tok); continue; end     % skip any stray rollup for a fixed-dim suite
        dim = str2double(tok{1});
    end

    T = read_csv(fullfile(summary_dir, name));
    if isempty(T); continue; end
    fcol = T.Properties.VariableNames{1};
    funcs = normalize_ids(T.(fcol));
    mcol = find_col(T, {'Mean', 'mean'});
    if isempty(mcol); continue; end
    means = T.(mcol);

    r.optimizer = string(optimizer);
    r.suite = char(suite);
    r.dim = dim;
    r.functions = funcs(:)';
    mp = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for q = 1:numel(funcs)
        if ~isnan(funcs(q)); mp(funcs(q)) = means(q); end
    end
    r.means = mp;
    r.mean_for = @(fn) lookup_mean(mp, fn);
    r.convergence = load_curves(fullfile(opt_dir, char(suite), 'curves'), dim);
    runs(end + 1) = r; %#ok<AGROW>
end
end

function v = lookup_mean(mp, fn)
if isKey(mp, fn); v = mp(fn); else; v = NaN; end
end

function curves = load_curves(curves_dir, dim)
% Map function id -> [Eval, BestError] from curves/Figure_F<f>_D<dim>_Run#*.csv
% (the median-run convergence trace written by run_experiment). dim = 0 means
% "any dimension" (the native-dim rollup group, whose curves carry their own
% per-function native dims).
curves = containers.Map('KeyType', 'double', 'ValueType', 'any');
if ~exist(curves_dir, 'dir'); return; end
if dim == 0
    pattern = 'Figure_F*_D*_Run#*.csv';
else
    pattern = sprintf('Figure_F*_D%d_Run#*.csv', dim);
end
listing = dir(fullfile(curves_dir, pattern));
for i = 1:numel(listing)
    tok = regexp(listing(i).name, 'Figure_F(\d+)_D\d+_Run#\d+\.csv$', 'tokens', 'once');
    if isempty(tok); continue; end
    fn = str2double(tok{1});
    T = read_csv(fullfile(listing(i).folder, listing(i).name));
    if isempty(T) || ~any(strcmpi(T.Properties.VariableNames, 'Eval')); continue; end
    ec = find_col(T, {'Eval'});
    bc = find_col(T, {'BestError'});
    curves(fn) = [T.(ec), T.(bc)];
end
end

function ref = load_reference_means(reference_root, suite, optimizer, dim, funcs)
% Map optimizer name to the reference folder/file token and read its mean
% column for the requested functions; NaN where unavailable.
algo = char(optimizer);
ref = nan(numel(funcs), 1);
folder = fullfile(reference_root, suite, algo);
if ~exist(folder, 'dir'); return; end
cand = dir(fullfile(folder, sprintf('*_D%02d.csv', dim)));
if isempty(cand); cand = dir(fullfile(folder, sprintf('*_D%d.csv', dim))); end
if isempty(cand); cand = dir(fullfile(folder, '*.csv')); end   % dimensionless (cec2011)
if isempty(cand); return; end
T = read_csv(fullfile(cand(1).folder, cand(1).name));
% Normalize the function column (handles 1 / F1 / f1) and find a Mean column.
fcol = T.Properties.VariableNames{1};
ids = normalize_ids(T.(fcol));
mcol = find_col(T, {'Mean', 'mean', 'MEAN'});
if isempty(mcol); return; end
means = T.(mcol);
for q = 1:numel(funcs)
    hit = find(ids == funcs(q), 1);
    if ~isempty(hit) && ~isnan(means(hit)); ref(q) = means(hit); end
end
end

function ids = normalize_ids(col)
if isnumeric(col)
    ids = col(:);
else
    ids = nan(numel(col), 1);
    for i = 1:numel(col)
        t = regexprep(char(string(col(i))), '^[Ff]', '');
        v = str2double(t);
        if ~isnan(v); ids(i) = v; end
    end
end
end

function name = find_col(T, candidates)
name = '';
for i = 1:numel(candidates)
    if any(strcmpi(T.Properties.VariableNames, candidates{i}))
        hit = find(strcmpi(T.Properties.VariableNames, candidates{i}), 1);
        name = T.Properties.VariableNames{hit};
        return;
    end
end
end

function s = num_or_blank(v)
if isnan(v); s = ''; else; s = sprintf('%.10e', v); end
end
