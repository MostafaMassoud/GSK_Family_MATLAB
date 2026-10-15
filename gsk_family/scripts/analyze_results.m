function analyze_results(varargin)
%ANALYZE_RESULTS Statistics and figures comparing generated runs to references.
%
%   analyze_results('project_root','<root>', 'results_root','<root>/results', ...
%                   'reference_root','<root>/benchmarks/cec_reference_results', ...
%                   'output_dir','<root>/results/analysis')
%
% All arguments are optional. project_root defaults to pwd; the other
% defaults are shown above (output_dir is <results_root>/analysis).
%
% Reads the summary table of each (optimizer, suite, dimension) under
% results_root: <optimizer>/<suite>/summary/<optimizer>_<suite>_D<dim>.csv,
% or the rollup <optimizer>_<suite>.csv for the native-dimension suites
% (CEC2011, CEC2013-LSGO). Each one is compared only with the reference table
% of the SAME dimension; with no such table the reference stays blank. Fewer
% than 5 reference values gives the verdict insufficient_reference.
% Writes to output_dir:
%   comparison_table.csv                per-function generated vs reference mean
%   friedman_ranks.csv                  average Friedman rank per optimizer
%   wilcoxon_vs_reference.csv           signed-rank p-value per optimizer
%   fig_<suite>_D<dim>_boxplot.pdf      error spread per optimizer
%   fig_<suite>_D<dim>_convergence.pdf  median-run curves of one function,
%                                       if curves exist
%
% Skips archived trees below results_root (_archive/<stamp>/ refresh copies
% and the launchers' _overwrite_archive/<suite>_<stamp>/). If one (optimizer,
% suite, dimension) appears under several layouts (e.g. results/<opt>/<suite>
% from gsk_run and results/_run_all/<opt>/<suite> from the launchers), it
% prints a warning and labels each copy in the tables and figures by its path
% below results_root (e.g. "_run_all/gsk" vs "gsk"). Point results_root at
% one layout to avoid this.
%
% Base MATLAB only (no Statistics and Machine Learning Toolbox): local
% tie-aware ranks (rank_with_ties, not tiedrank), gammainc for the Friedman
% p-value and erfc for the Wilcoxon normal approximation. Methods follow
% Derrac et al. (2011), Swarm and Evol. Comput.
%
% Lower error is better. Analyzes whatever optimizers/suites are present;
% missing data is reported, never invented.

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
% Close the three tables on any exit, including an error.
csv_closer = onCleanup(@() close_open_fids([comp_fid, fri_fid, wil_fid]));
fprintf(comp_fid, 'suite,dimension,optimizer,function,generated_mean,reference_mean\n');
fprintf(fri_fid,  'suite,dimension,optimizer,avg_friedman_rank,n_functions,chi2,df,p_value\n');
fprintf(wil_fid,  'suite,dimension,optimizer,n_functions,wilcoxon_W,z,p_value,verdict_vs_reference\n');

for g = 1:numel(ukeys)
    group = runs(idx == g);
    suite = group(1).suite;
    dim = group(1).dim;
    fprintf('\n== %s D%d : %d optimizer(s) ==\n', suite, dim, numel(group));

    % Mean-error matrix over the functions that every optimizer in this
    % group has.
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
    names = strings(1, k);   % display labels (optimizer, or path for duplicates)
    for i = 1:k
        names(i) = group(i).label;
        for f = 1:nF
            M(f, i) = group(i).mean_for(common_funcs(f));
        end
    end

    % Per optimizer: generated vs reference mean per function, then a Wilcoxon
    % signed-rank test of its means against the reference means across
    % functions (needs >= 5 reference values).
    for i = 1:k
        ref = load_reference_means(a.reference_root, suite, group(i).optimizer, dim, common_funcs);
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

function close_open_fids(fids)
% onCleanup target: close any output file still open (a no-op after the
% normal fclose at the end of analyze_results).
for h = fids
    if h > 2 && ~isempty(fopen(h)); fclose(h); end
end
end

% ---- statistics (toolbox-free) ---------------------------------------------

function r = rank_with_ties(x)
% Ranks with ties averaged (1 = smallest); NaN gets rank NaN; same shape as x.
% Base-MATLAB replacement for the Statistics Toolbox tiedrank on a vector.
[sx, ix] = sort(x(:));   % ascending; NaN sorts last
nn = nnz(~isnan(sx));
r = nan(size(x));
i = 1;
while i <= nn
    j = i;
    while j < nn && sx(j + 1) == sx(i); j = j + 1; end
    r(ix(i:j)) = (i + j) / 2;
    i = j + 1;
end
end

function [avg_rank, chi2, df, pv] = friedman_ranks(M)
% Friedman test. M is nF x k (rows = functions, cols = optimizers); lower is
% better. Returns the average rank per optimizer, chi2, df = k - 1 and p.
[nF, k] = size(M);
R = zeros(nF, k);
for f = 1:nF
    R(f, :) = rank_with_ties(M(f, :));  % 1 = best (smallest error)
end
avg_rank = mean(R, 1);
chi2 = 12 * nF / (k * (k + 1)) * sum((avg_rank - (k + 1) / 2) .^ 2);
df = k - 1;
% Upper-tail chi-square p-value: chi2cdf(x,df) = gammainc(x/2,df/2)
pv = 1 - gammainc(chi2 / 2, df / 2);
end

function [W, z, pv] = wilcoxon_signed_rank(x, y)
% Paired Wilcoxon signed-rank test of x vs y (base MATLAB only). Zero
% differences are dropped; the p-value uses the normal approximation with
% continuity correction. All differences zero -> W = 0, z = 0, pv = 1.
d = x - y;
d = d(d ~= 0);
n = numel(d);
if n == 0
    W = 0; z = 0; pv = 1; return;
end
r = rank_with_ties(abs(d));
W = sum(r(d > 0));                 % sum of positive ranks
mu = n * (n + 1) / 4;
sigma = sqrt(n * (n + 1) * (2 * n + 1) / 24);
z = (W - mu - 0.5 * sign(W - mu)) / sigma;
pv = erfc(abs(z) / sqrt(2));       % two-sided normal p-value
end

% ---- figures ----------------------------------------------------------------

function make_boxplot(M, names, suite, dim, out_dir)
% Box plot of each optimizer's mean errors (log y-axis when all are > 0).
% A plotting error is printed and the figure skipped.
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
% Median-run convergence curves (log y-axis) for one function. A plotting
% error is printed and the figure skipped.
try
    % Use the lowest function id whose curve exists for every optimizer.
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
        plot(ax, M(:, 1), max(M(:, 2), realmin), 'DisplayName', char(group(i).label));
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
% readtable with the original headers, except 'function' (a MATLAB keyword)
% becomes 'func' so T.func works. Text after # on a line is ignored.
T = readtable(path, 'CommentStyle', '#', 'VariableNamingRule', 'preserve');
vn = T.Properties.VariableNames;
hit = find(strcmp(vn, 'function'), 1);
if ~isempty(hit)
    vn{hit} = 'func';
    T.Properties.VariableNames = vn;
end
end

function runs = load_all_summaries(results_root)
% Load every results_root/.../<optimizer>/<suite>/summary/*.csv
% (Function,Best,Median,Mean,Worst,SD); optimizer and suite come from the path.
% Fixed-dimension suites (CEC2013, CEC2017, CEC2020) use the per-dimension
% files <opt>_<suite>_D<dim>.csv (dim from the file name). Native-dimension
% suites (CEC2011, CEC2013-LSGO) have a different dimension per function, so
% each per-dim file holds only a few functions and would not give a useful
% comparison group. They use the rollup <opt>_<suite>.csv (all functions,
% each once) as dim = 0, so the whole suite forms one group.
% Skips per_run.csv and anything below an _archive or _overwrite_archive
% folder (relative to results_root). label is the optimizer name, or the
% layout (path from results_root to the optimizer folder) when the same
% (optimizer, suite, dim) appears under several layouts.
runs = struct('optimizer', {}, 'label', {}, 'layout', {}, 'suite', {}, 'dim', {}, ...
              'functions', {}, 'means', {}, 'mean_for', {}, 'convergence', {});
root_info = dir(results_root);
if isempty(root_info); root_abs = ''; else; root_abs = root_info(1).folder; end
listing = dir(fullfile(results_root, '**', 'summary', '*.csv'));
for i = 1:numel(listing)
    name = listing(i).name;
    if strcmpi(name, 'per_run.csv'); continue; end
    summary_dir = listing(i).folder;
    rel = path_parts_below(summary_dir, root_abs);
    if any(strcmpi(rel, '_archive') | strcmpi(rel, '_overwrite_archive')); continue; end
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
    r.label = string(optimizer);
    r.layout = string(strjoin(rel(1:max(end - 2, 0)), '/'));   % e.g. "_run_all/gsk"
    if strlength(r.layout) == 0; r.layout = r.label; end
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

% Label each duplicate by its layout; otherwise the same (optimizer, suite,
% dim) from several layouts would enter one Friedman group twice under one
% name.
if isempty(runs); return; end
ids = arrayfun(@(q) sprintf('%s|%s|%d', q.optimizer, q.suite, q.dim), runs, 'UniformOutput', false);
[~, ~, j] = unique(ids);
for u = find(accumarray(j(:), 1) > 1)'
    dup = find(j(:)' == u);
    for d = dup
        runs(d).label = runs(d).layout;
    end
    fprintf(['analyze_results: WARNING duplicate %s/%s D%d from multiple layouts (%s); ' ...
             'labeled by path\n'], runs(dup(1)).optimizer, runs(dup(1)).suite, runs(dup(1)).dim, ...
            strjoin(cellstr([runs(dup).layout]), ', '));
end
end

function parts = path_parts_below(folder, root_abs)
% Path components of folder below root_abs (all of them if it is not below).
f = strrep(folder, '\', '/');
r = regexprep(strrep(root_abs, '\', '/'), '/+$', '');
if ~isempty(r) && strncmpi(f, [r '/'], numel(r) + 1)
    f = f(numel(r) + 2:end);
end
parts = strsplit(f, '/');
parts = parts(~cellfun('isempty', parts));
end

function v = lookup_mean(mp, fn)
if isKey(mp, fn); v = mp(fn); else; v = NaN; end
end

function curves = load_curves(curves_dir, dim)
% Map function id -> [Eval, BestError] from curves/Figure_F<f>_D<dim>_Run#*.csv
% (the median-run convergence trace written by run_experiment). dim = 0 means
% any dimension (the native-dimension rollup group, where each function's
% curve uses its own native dimension).
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
% Reference mean for each requested function, read from
% reference_root/<suite>/<optimizer>/ (numel(funcs) x 1, NaN where missing).
% Uses only the table of this dimension (*_D<dim>.csv, two-digit form tried
% first; dim = 0 -> the rollup <opt>_<suite>.csv). A dimension without its
% own table stays NaN; it never borrows another dimension's table.
algo = char(optimizer);
ref = nan(numel(funcs), 1);
folder = fullfile(reference_root, suite, algo);
if ~exist(folder, 'dir'); return; end
if dim == 0
    cand = dir(fullfile(folder, sprintf('%s_%s.csv', algo, suite)));   % native-dim rollup
else
    cand = dir(fullfile(folder, sprintf('*_D%02d.csv', dim)));
    if isempty(cand); cand = dir(fullfile(folder, sprintf('*_D%d.csv', dim))); end
end
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
% Function ids as a numeric column; accepts 1, 'F1' or 'f1' (NaN if unreadable).
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
% Column name for the first candidate that matches (case-insensitive), or ''.
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
