function report = compare_algorithms(varargin)
%COMPARE_ALGORITHMS Statistics tables and tests that compare optimizers with each other.
%
%   compare_algorithms('suite','cec2017', 'optimizers',{'my-gsk','gsk'})
%   report = compare_algorithms('suite','cec2011', 'optimizers',{'my-gsk','gsk','agsk'}, ...
%                               'proposed','my-gsk', 'alpha',0.05)
%
% Works for every suite (cec2011, cec2013, cec2013lsgo, cec2017, cec2020) and
% every optimizer with results, including one you added yourself. Run it from
% the gsk_family folder (or pass project_root) after the runs have finished.
% It reads each optimizer's summary/per_run.csv. Values are the per-run errors
% f(x) - f(x*) when the suite has known optima, else the raw objective values
% (cec2011, cec2013lsgo). Lower is better.
%
% Options (all optional except suite):
%   suite         suite id, e.g. 'cec2017'.
%   optimizers    cell of optimizer ids, in table order. Default: every
%                 optimizer folder under results_root that holds this suite.
%   proposed      the optimizer every other one is tested against. Default:
%                 the first of optimizers.
%   labels        display names, same order as optimizers (as in
%                 plot_convergence).
%   functions, dimensions   restrict the comparison. Default: all found.
%   alpha         significance level. Default 0.05.
%   tex_digits    digits after the decimal point in the LaTeX tables. Default 2.
%   results_root  Default <project_root>/results/_run_all.
%   output_dir    Default <project_root>/results/analysis/compare/<suite>.
%   project_root  Default pwd.
%
% A "group" is one dimension (fixed-dimension suites) or the whole suite
% (cec2011, cec2013lsgo: every problem at its own dimension; tag "all").
% Only functions that every optimizer has in a group are compared; the others
% are listed in report.skipped. Writes to output_dir:
%   statistics_<suite>.csv     Best, Median, Mean, Worst, SD and the run count
%                              per (dimension, function, optimizer)
%   table_<suite>_<tag>.csv    Mean and SD of every optimizer per function,
%   table_<suite>_<tag>.tex    with the rank-sum sign of each competitor; the
%                              best mean in bold in the LaTeX table
%   ranksum_<suite>.csv        per function: two-sided Wilcoxon rank-sum test
%                              of the proposed optimizer's runs against each
%                              competitor's runs, p-value and sign
%   wilcoxon_<suite>.csv       per group: Wilcoxon signed-rank test over the
%                              function means (R+, R-, p), and the +/=/- counts
%   friedman_<suite>.csv       per group and overall: Friedman mean ranks,
%                              chi-square and p-value
%   settings_<suite>.csv/.tex  per optimizer: the code it ran (the base of
%                              an algorithms.ini alias), its initial and
%                              final population sizes and any other changed
%                              settings ("original" = published value), from
%                              its summary/environment.json
% Optimizer names may be algorithms.ini aliases (e.g. gsk-np50): each is read
% from its own results folder like any optimizer.
% Signs are from the proposed optimizer's side: "+" it is significantly
% better than that competitor (p < alpha and lower ranks), "-" significantly
% worse, "=" no significant difference. R+ sums the ranks of the functions on
% which the proposed optimizer has the lower mean, R- the others; equal means
% split their ranks evenly (Derrac et al. 2011, Swarm Evol. Comput. 1:3-18).
%
% Base MATLAB only; no toolbox needed. The tests follow the Statistics and
% Machine Learning Toolbox definitions (ranksum, signrank, friedman):
% tie-corrected normal approximations (with continuity correction for the
% rank-sum test only, as ranksum does), and exact p-values for small samples
% (rank-sum when the smaller sample has < 10 runs and both have < 20
% together; signed-rank for <= 15 nonzero differences).

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('optimizers', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('proposed', '', @(x) ischar(x) || isstring(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('alpha', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
p.addParameter('tex_digits', 2, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('results_root', '', @(x) ischar(x) || isstring(x));
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite));
assert(~isempty(a.suite), 'compare_algorithms:args', 'suite is required, e.g. ''cec2017''');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
a.results_root = char(a.results_root);
if isempty(a.output_dir); a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'compare', a.suite); end
a.output_dir = char(a.output_dir);

opts = resolve_optimizers(a.results_root, a.suite, a.optimizers);
assert(numel(opts) >= 2, 'compare_algorithms:args', 'need at least two optimizers (found %d)', numel(opts));
if isempty(a.proposed); prop = opts{1}; else; prop = canonical_id(a.proposed); end
ip = find(strcmp(opts, prop), 1);
assert(~isempty(ip), 'compare_algorithms:args', 'proposed optimizer %s is not in optimizers', prop);
labels = resolve_labels(opts, a.labels);
native = any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));
known_optimum = ~native;
comp = setdiff(1:numel(opts), ip, 'stable');

% runs{i}: containers.Map 'f|D' -> per-run values of optimizer i.
runs = cell(1, numel(opts));
for i = 1:numel(opts)
    runs{i} = load_runs(fullfile(a.results_root, opts{i}, a.suite, 'summary', 'per_run.csv'), known_optimum);
    fprintf('compare_algorithms: %-12s %3d (function, dimension) cell(s)\n', labels{i}, runs{i}.Count);
end

% Groups: one per dimension, or one for the whole native-dimension suite.
cells = zeros(0, 2);
for i = 1:numel(opts)
    k = keys(runs{i});
    for j = 1:numel(k); cells(end + 1, :) = sscanf(k{j}, '%d|%d')'; end %#ok<AGROW>
end
cells = unique(cells, 'rows');
if ~isempty(a.functions); cells = cells(ismember(cells(:, 1), a.functions), :); end
if ~isempty(a.dimensions) && ~native; cells = cells(ismember(cells(:, 2), a.dimensions), :); end
assert(~isempty(cells), 'compare_algorithms:noData', 'no runs found for %s under %s', a.suite, a.results_root);
if native
    gid = zeros(size(cells, 1), 1); gdims = 0;
else
    gid = cells(:, 2); gdims = unique(gid)';
end
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end
report.settings = write_settings_table(a, opts, labels);

fst = fopen(fullfile(a.output_dir, sprintf('statistics_%s.csv', a.suite)), 'w');
frs = fopen(fullfile(a.output_dir, sprintf('ranksum_%s.csv', a.suite)), 'w');
fwx = fopen(fullfile(a.output_dir, sprintf('wilcoxon_%s.csv', a.suite)), 'w');
ffr = fopen(fullfile(a.output_dir, sprintf('friedman_%s.csv', a.suite)), 'w');
closer = onCleanup(@() close_open([fst frs fwx ffr]));
fprintf(fst, 'dimension,function,optimizer,runs,best,median,mean,worst,sd\n');
fprintf(frs, 'dimension,function,proposed,competitor,p_value,sign\n');
fprintf(fwx, ['dimension,proposed,competitor,n_functions,r_plus,r_minus,p_value,decision,' ...
              'wins,ties,losses\n']);
fprintf(ffr, 'dimension,optimizer,mean_rank,position,n_functions,chi2,df,p_value\n');

settings_rows = report.settings;
report = struct('optimizers', {opts}, 'proposed', prop, 'groups', struct([]), 'skipped', {{}});
report.settings = settings_rows;
all_means = zeros(0, numel(opts));   % every compared cell, for the overall Friedman row
for g = gdims
    gc = cells(gid == g, :);
    keep = true(size(gc, 1), 1);
    for c = 1:size(gc, 1)
        key = sprintf('%d|%d', gc(c, 1), gc(c, 2));
        have = cellfun(@(m) isKey(m, key), runs);
        if ~all(have)
            keep(c) = false;
            report.skipped{end + 1} = sprintf('F%d D%d: no runs for %s', gc(c, 1), gc(c, 2), ...
                                              strjoin(labels(~have), ', '));
        end
    end
    gc = gc(keep, :);
    if isempty(gc); continue; end
    nf = size(gc, 1);
    if native; tag = 'all'; dtext = 'native'; else; tag = sprintf('D%d', g); dtext = sprintf('%d', g); end

    S = repmat(struct('best', 0, 'median', 0, 'mean', 0, 'worst', 0, 'sd', 0, 'n', 0), nf, numel(opts));
    sgn = repmat('=', nf, numel(opts));
    pval = nan(nf, numel(opts));
    for c = 1:nf
        key = sprintf('%d|%d', gc(c, 1), gc(c, 2));
        for i = 1:numel(opts)
            S(c, i) = cell_stats(runs{i}(key), known_optimum);
            fprintf(fst, '%s,%d,%s,%d,%.10e,%.10e,%.10e,%.10e,%.10e\n', dtext, gc(c, 1), opts{i}, ...
                    S(c, i).n, S(c, i).best, S(c, i).median, S(c, i).mean, S(c, i).worst, S(c, i).sd);
        end
        x = runs{ip}(key);
        for i = comp
            [pv, lower_x] = ranksum_test(x, runs{i}(key));
            pval(c, i) = pv;
            if pv < a.alpha
                if lower_x; sgn(c, i) = '+'; else; sgn(c, i) = '-'; end
            end
            fprintf(frs, '%s,%d,%s,%s,%.6g,%s\n', dtext, gc(c, 1), prop, opts{i}, pv, sgn(c, i));
        end
    end
    means = reshape([S.mean], nf, numel(opts));
    all_means = [all_means; means]; %#ok<AGROW>

    fprintf('\n== %s %s: %d function(s), proposed %s ==\n', suite_title(a.suite), tag, nf, labels{ip});
    fprintf('   %-12s %10s %10s %10s   %s\n', 'vs', 'R+', 'R-', 'p', '+ / = / -');
    wx = struct('competitor', {}, 'r_plus', {}, 'r_minus', {}, 'p', {}, 'decision', {}, 'wtl', {});
    for i = comp
        [rp, rm, pv] = signed_rank_test(means(:, i), means(:, ip));
        if pv >= a.alpha
            dec = 'no significant difference';
        elseif rp > rm
            dec = sprintf('%s better', labels{ip});
        else
            dec = sprintf('%s better', labels{i});
        end
        wtl = [nnz(sgn(:, i) == '+'), nnz(sgn(:, i) == '='), nnz(sgn(:, i) == '-')];
        fprintf(fwx, '%s,%s,%s,%d,%.1f,%.1f,%.6g,%s,%d,%d,%d\n', dtext, prop, opts{i}, nf, ...
                rp, rm, pv, dec, wtl);
        fprintf('   %-12s %10.1f %10.1f %10.4g   %d / %d / %d   %s\n', labels{i}, rp, rm, pv, wtl, dec);
        wx(end + 1) = struct('competitor', opts{i}, 'r_plus', rp, 'r_minus', rm, 'p', pv, ...
                             'decision', dec, 'wtl', wtl); %#ok<AGROW>
    end

    [mr, chi2, df, pv] = friedman_test(means);
    write_friedman(ffr, dtext, opts, mr, nf, chi2, df, pv);
    print_friedman(labels, mr, chi2, df, pv);

    write_wide_table(fullfile(a.output_dir, sprintf('table_%s_%s.csv', a.suite, tag)), ...
                     gc, opts, ip, S, sgn, pval);
    write_tex_table(fullfile(a.output_dir, sprintf('table_%s_%s.tex', a.suite, tag)), ...
                    gc, labels, ip, comp, S, sgn, a, tag, native);
    report.groups(end + 1).tag = tag;
    report.groups(end).functions = gc(:, 1)';
    report.groups(end).wilcoxon = wx;
    report.groups(end).friedman = struct('mean_rank', mr, 'chi2', chi2, 'df', df, 'p', pv);
end

if numel(report.groups) > 1
    [mr, chi2, df, pv] = friedman_test(all_means);
    write_friedman(ffr, 'overall', opts, mr, size(all_means, 1), chi2, df, pv);
    fprintf('\n== %s overall: %d (function, dimension) cell(s) ==\n', suite_title(a.suite), size(all_means, 1));
    print_friedman(labels, mr, chi2, df, pv);
    report.overall_friedman = struct('mean_rank', mr, 'chi2', chi2, 'df', df, 'p', pv);
end
for k = 1:numel(report.skipped)
    fprintf('compare_algorithms: skipped %s\n', report.skipped{k});
end
fprintf('\ncompare_algorithms: wrote tables to %s\n', a.output_dir);
end

% ---- statistics (base MATLAB) -------------------------------------------------

function r = tied_ranks(x)
% Ranks 1..n of a vector, ties averaged.
[sx, ix] = sort(x(:));
n = numel(sx);
r = zeros(n, 1);
i = 1;
while i <= n
    j = i;
    while j < n && sx(j + 1) == sx(i); j = j + 1; end
    r(ix(i:j)) = (i + j) / 2;
    i = j + 1;
end
r = reshape(r, size(x));
end

function t = tie_sizes(x)
% Sizes of the groups of equal values (groups of 1 included).
s = sort(x(:));
t = diff([0; find(diff(s) ~= 0); numel(s)]);
end

function [pv, lower_x] = ranksum_test(x, y)
% Two-sided Wilcoxon rank-sum (Mann-Whitney) test of x vs y, as ranksum.
% lower_x is true when x has the lower ranks (smaller values).
x = x(:); y = y(:);
nx = numel(x); ny = numel(y); N = nx + ny;
r = tied_ranks([x; y]);
w = sum(r(1:nx));
w_mean = nx * (N + 1) / 2;
lower_x = w < w_mean;
if min(nx, ny) < 10 && N < 20
    % Exact: distribution of the rank sum of nx of the N (tied) ranks.
    pv = exact_tail(2 * r, nx, 2 * w);
else
    t = tie_sizes([x; y]);
    v = nx * ny / 12 * ((N + 1) - sum(t .^ 3 - t) / (N * (N - 1)));
    if v <= 0; pv = 1; return; end
    z = (w - w_mean - 0.5 * sign(w - w_mean)) / sqrt(v);
    pv = erfc(abs(z) / sqrt(2));
end
end

function pv = exact_tail(r2, k, s2)
% Two-sided exact p-value for the sum s2 of k values chosen from the
% integer vector r2 (doubled ranks): 2 * min(P(S <= s2), P(S >= s2)), <= 1.
smax = sum(r2);
cnt = zeros(k + 1, smax + 1);   % cnt(j+1, s+1): subsets of size j with sum s
cnt(1, 1) = 1;
for v = r2(:)'
    for j = k:-1:1
        cnt(j + 1, v + 1:end) = cnt(j + 1, v + 1:end) + cnt(j, 1:end - v);
    end
end
dist = cnt(k + 1, :) / sum(cnt(k + 1, :));
s2 = round(s2);
pv = min(1, 2 * min(sum(dist(1:s2 + 1)), sum(dist(s2 + 1:end))));
end

function [r_plus, r_minus, pv] = signed_rank_test(y, x)
% Wilcoxon signed-rank test of the differences d = y - x (d > 0: x, the
% proposed optimizer, is better). As in signrank, a difference within
% eps(x) + eps(y) counts as zero. r_plus/r_minus split the ranks of zero
% differences evenly (Derrac et al. 2011); the p-value drops them, as
% signrank does.
d = y(:) - x(:);
d(abs(d) <= eps(x(:)) + eps(y(:))) = 0;
ra = tied_ranks(abs(d));
r_plus = sum(ra(d > 0)) + sum(ra(d == 0)) / 2;
r_minus = sum(ra(d < 0)) + sum(ra(d == 0)) / 2;
nz = d(d ~= 0);
n = numel(nz);
if n == 0; pv = 1; return; end
r = tied_ranks(abs(nz));
w = sum(r(nz > 0));
if n <= 15
    % Exact: every sign assignment of the (tied) ranks is equally likely.
    r2 = round(2 * r);
    smax = sum(r2);
    cnt = zeros(1, smax + 1); cnt(1) = 1;
    for v = r2(:)'
        cnt(v + 1:end) = cnt(v + 1:end) + cnt(1:end - v);
    end
    dist = cnt / sum(cnt);
    s2 = round(2 * w);
    pv = min(1, 2 * min(sum(dist(1:s2 + 1)), sum(dist(s2 + 1:end))));
else
    % Two-sided normal approximation without continuity correction, as in
    % signrank.
    t = tie_sizes(abs(nz));
    sigma = sqrt((n * (n + 1) * (2 * n + 1) - sum(t .^ 3 - t) / 2) / 24);
    z = (w - n * (n + 1) / 4) / sigma;
    pv = erfc(abs(z) / sqrt(2));
end
end

function [mean_rank, chi2, df, pv] = friedman_test(M)
% Friedman test on M (rows = functions, columns = optimizers; lower is
% better, rank 1 = best), with the tie correction friedman uses.
[n, k] = size(M);
R = zeros(n, k);
tie_sum = 0;
for f = 1:n
    R(f, :) = tied_ranks(M(f, :));
    t = tie_sizes(M(f, :));
    tie_sum = tie_sum + sum(t .^ 3 - t);
end
mean_rank = mean(R, 1);
denom = 1 - tie_sum / (n * (k ^ 3 - k));
if denom <= 0
    chi2 = 0;
else
    chi2 = (12 / (n * k * (k + 1)) * sum(sum(R, 1) .^ 2) - 3 * n * (k + 1)) / denom;
end
df = k - 1;
pv = 1 - gammainc(chi2 / 2, df / 2);   % chi-square upper tail
end

function s = cell_stats(v, known_optimum)
% Summary statistics of one cell, with the runner's 1e-8 zero cutoff when
% the suite has known optima (same as summary/<opt>_<suite>_D<d>.csv).
s = struct('best', min(v), 'median', median(v), 'mean', mean(v), ...
           'worst', max(v), 'sd', std(v), 'n', numel(v));
if known_optimum
    for f = {'best', 'median', 'mean', 'worst', 'sd'}
        if abs(s.(f{1})) < 1e-8; s.(f{1}) = 0; end
    end
end
end

% ---- output -----------------------------------------------------------------

function write_friedman(fid, dtext, opts, mr, nf, chi2, df, pv)
[~, order] = sort(mr);
pos = zeros(size(mr)); pos(order) = 1:numel(mr);
for i = 1:numel(opts)
    fprintf(fid, '%s,%s,%.4f,%d,%d,%.6g,%d,%.6g\n', dtext, opts{i}, mr(i), pos(i), nf, chi2, df, pv);
end
end

function print_friedman(labels, mr, chi2, df, pv)
[~, order] = sort(mr);
fprintf('   Friedman mean ranks (1 = best):');
for i = order; fprintf('  %s %.3f', labels{i}, mr(i)); end
fprintf('\n   Friedman chi2 = %.4g, df = %d, p = %.4g\n', chi2, df, pv);
end

function write_wide_table(path, gc, opts, ip, S, sgn, pval)
fid = fopen(path, 'w');
c = onCleanup(@() fclose(fid));
fprintf(fid, 'function,dimension');
for i = 1:numel(opts)
    fprintf(fid, ',%s_mean,%s_sd', opts{i}, opts{i});
    if i ~= ip; fprintf(fid, ',%s_p,%s_sign', opts{i}, opts{i}); end
end
fprintf(fid, '\n');
for r = 1:size(gc, 1)
    fprintf(fid, '%d,%d', gc(r, 1), gc(r, 2));
    for i = 1:numel(opts)
        fprintf(fid, ',%.10e,%.10e', S(r, i).mean, S(r, i).sd);
        if i ~= ip; fprintf(fid, ',%.6g,%s', pval(r, i), sgn(r, i)); end
    end
    fprintf(fid, '\n');
end
end

function write_tex_table(path, gc, labels, ip, comp, S, sgn, a, tag, native)
% Mean (SD) per optimizer; best mean in bold; competitor cells carry the
% rank-sum sign; a last row counts +/=/-.
fid = fopen(path, 'w');
c = onCleanup(@() fclose(fid));
k = numel(labels);
order = [ip, comp];
fmt = sprintf('%%.%dE', a.tex_digits);
fprintf(fid, '%% %s %s: Mean (SD) over the runs; best mean in bold.\n', suite_title(a.suite), tag);
fprintf(fid, ['%% +/=/-: %s is significantly better / not significantly different / ' ...
              'significantly worse (two-sided Wilcoxon rank-sum, alpha = %g).\n'], labels{ip}, a.alpha);
fprintf(fid, '\\begin{tabular}{l%s%s}\n\\hline\n', repmat('r', 1, native), repmat('c', 1, k));
fprintf(fid, 'Func.');
if native; fprintf(fid, ' & $D$'); end
for i = order; fprintf(fid, ' & %s', tex_escape(labels{i})); end
fprintf(fid, ' \\\\\n\\hline\n');
means = reshape([S.mean], size(S));
for r = 1:size(gc, 1)
    fprintf(fid, 'F%d', gc(r, 1));
    if native; fprintf(fid, ' & %d', gc(r, 2)); end
    best = min(means(r, :));
    for i = order
        cellv = sprintf(['%s (' fmt ')'], sprintf(fmt, S(r, i).mean), S(r, i).sd);
        if means(r, i) == best; cellv = ['\textbf{' cellv '}']; end
        if i ~= ip; cellv = [cellv ' ' sgn(r, i)]; end
        fprintf(fid, ' & %s', cellv);
    end
    fprintf(fid, ' \\\\\n');
end
fprintf(fid, '\\hline\n+/=/-');
if native; fprintf(fid, ' &'); end
fprintf(fid, ' & --');
for i = comp
    fprintf(fid, ' & %d/%d/%d', nnz(sgn(:, i) == '+'), nnz(sgn(:, i) == '='), nnz(sgn(:, i) == '-'));
end
fprintf(fid, ' \\\\\n\\hline\n\\end{tabular}\n');
end

function rows = write_settings_table(a, opts, labels)
% settings_<suite>.csv and .tex: for each compared name, the algorithm code
% it ran (base), its starting and final population sizes and any other
% changed settings, read from <results_root>/<name>/<suite>/summary/
% environment.json (written by run_experiment). "original" means the
% algorithm's published value.
rows = struct('name', {}, 'label', {}, 'base', {}, 'np_init', {}, 'min_pop_size', {}, 'other', {});
for i = 1:numel(opts)
    env = struct();
    path = fullfile(a.results_root, opts{i}, a.suite, 'summary', 'environment.json');
    if isfile(path)
        try env = jsondecode(fileread(path)); catch; end
    end
    base = opts{i};
    if isfield(env, 'base_optimizer') && ~isempty(env.base_optimizer); base = env.base_optimizer; end
    other = 'original';
    if isfield(env, 'alias_settings') && ~isempty(env.alias_settings)
        parts = strtrim(strsplit(env.alias_settings, ','));
        parts = parts(~startsWith(parts, {'np_init', 'np ', 'min_pop_size'}));
        if ~isempty(parts); other = strjoin(parts, ', '); end
    end
    rows(end + 1) = struct('name', opts{i}, 'label', labels{i}, 'base', base, ...
        'np_init', np_text(env, base), 'min_pop_size', min_text(env, base), 'other', other); %#ok<AGROW>
end
fid = fopen(fullfile(a.output_dir, sprintf('settings_%s.csv', a.suite)), 'w');
c1 = onCleanup(@() fclose(fid));
fprintf(fid, 'name,label,base,np_init,min_pop_size,other_settings\n');
for r = rows
    fprintf(fid, '%s,%s,%s,"%s","%s","%s"\n', r.name, r.label, r.base, r.np_init, r.min_pop_size, r.other);
end
fid2 = fopen(fullfile(a.output_dir, sprintf('settings_%s.tex', a.suite)), 'w');
c2 = onCleanup(@() fclose(fid2));
fprintf(fid2, '%% %s: settings of each compared algorithm ("original" = published value).\n', suite_title(a.suite));
fprintf(fid2, '\\begin{tabular}{lllll}\n\\hline\n');
fprintf(fid2, 'Algorithm & Code & Initial NP & Final NP & Other settings \\\\\n\\hline\n');
for r = rows
    fprintf(fid2, '%s & %s & %s & %s & %s \\\\\n', tex_escape(r.label), tex_escape(display_name(r.base)), ...
            tex_escape(r.np_init), tex_escape(r.min_pop_size), tex_escape(r.other));
end
fprintf(fid2, '\\hline\n\\end{tabular}\n');
end

function s = np_text(env, base)
% Starting population size: the run's value, or the base's original.
if isfield(env, 'np_init') && ~isempty(env.np_init)
    s = sprintf('%g', env.np_init);
elseif strcmp(base, 'dt-gsk')
    s = '5D (original)';
elseif any(strcmp(base, {'gsk', 'agsk', 'apgsk', 'fdb-agsk', 'atmals-gsk', 'egsk'}))
    s = '100 (original)';
else
    s = 'original';   % a user-added optimizer: its own default
end
end

function s = min_text(env, base)
% Final population size: the run's value, the base's original, or "fixed".
if any(strcmp(base, {'gsk', 'egsk', 'atmals-gsk'}))
    s = 'fixed';
elseif isfield(env, 'min_pop_size') && ~isempty(env.min_pop_size)
    s = sprintf('%g', env.min_pop_size);
elseif strcmp(base, 'dt-gsk')
    s = '12; 25 for D >= 50 (original)';
elseif any(strcmp(base, {'agsk', 'apgsk', 'fdb-agsk'}))
    s = '12 (original)';
else
    s = 'original';
end
end

function s = tex_escape(s)
s = strrep(s, '_', '\_');
s = strrep(s, '&', '\&');
s = strrep(s, '%', '\%');
end

function close_open(fids)
for h = fids
    if h > 2 && ~isempty(fopen(h)); fclose(h); end
end
end

% ---- data loading -------------------------------------------------------------

function m = load_runs(path, known_optimum)
% Map 'f|D' -> per-run values from per_run.csv (the error column, or
% best_fitness when the suite has no known optimum). A run id that appears
% more than once (resumed sessions) keeps its last row.
assert(isfile(path), 'compare_algorithms:noResults', 'missing %s', path);
T = readtable(path, 'VariableNamingRule', 'preserve', 'Delimiter', ',');
if known_optimum; vcol = 'error'; else; vcol = 'best_fitness'; end
F = T.('function'); D = T.dimension; R = T.run; V = T.(vcol);
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
[~, last] = unique([F D R], 'rows', 'last');
F = F(last); D = D(last); R = R(last); V = V(last);
[cells, ~, g] = unique([F D], 'rows');
for c = 1:size(cells, 1)
    sel = g == c;
    [~, o] = sort(R(sel));
    v = V(sel);
    m(sprintf('%d|%d', cells(c, 1), cells(c, 2))) = v(o);
end
end

function opts = resolve_optimizers(results_root, suite, requested)
if ~isempty(requested)
    opts = cellfun(@canonical_id, cellstr(requested), 'UniformOutput', false);
    return;
end
d = dir(results_root);
opts = {};
for k = 1:numel(d)
    if d(k).isdir && d(k).name(1) ~= '.' && d(k).name(1) ~= '_' && ...
            isfile(fullfile(results_root, d(k).name, suite, 'summary', 'per_run.csv'))
        opts{end + 1} = d(k).name; %#ok<AGROW>
    end
end
end

function labels = resolve_labels(opts, given)
if ~isempty(given)
    labels = cellstr(given);
    assert(numel(labels) == numel(opts), 'compare_algorithms:args', ...
           'labels must have one entry per optimizer (%d)', numel(opts));
    return;
end
labels = cellfun(@display_name, opts, 'UniformOutput', false);
end

function s = display_name(id)
switch id
    case 'egsk'; s = 'eGSK';
    otherwise;   s = upper(id);
end
end

function id = canonical_id(name)
id = lower(strtrim(char(name)));
switch id
    case 'atmals_gsk'; id = 'atmals-gsk';
    case 'fdb_agsk';   id = 'fdb-agsk';
    case 'dt_gsk';     id = 'dt-gsk';
end
end

function s = suite_title(suite)
switch suite
    case 'cec2013lsgo'; s = 'CEC2013-LSGO';
    otherwise;          s = upper(suite);
end
end
