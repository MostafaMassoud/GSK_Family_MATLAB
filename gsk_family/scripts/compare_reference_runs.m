function report = compare_reference_runs(generated, reference, varargin)
%COMPARE_REFERENCE_RUNS Per-cell statistical comparison of two per_run.csv result sets.
%
%   report = compare_reference_runs(generated, reference)
%   report = compare_reference_runs(..., 'alpha', 0.05, 'out', 'comparison.csv', ...
%                                   'zero_tol', 1e-8, 'decades', 1, 'sig_digits', 11)
%
% generated / reference: a per_run.csv path, or a folder containing
% summary/per_run.csv or per_run.csv (schema in docs/reference/result_schema.md:
% optimizer,suite,function,dimension,run,seed,best_fitness,error,...).
% Typical use: compare a MATLAB campaign with an imported reference campaign
% of the same optimizer, e.g. DT-GSK against the reference implementation's
% runs in benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv.
%
% Options: 'alpha' (0.05) rank-sum test level; 'out' ('') CSV file for the
% table; 'zero_tol' (1e-8) |v| below it counts as 0; 'decades' (1) allowed
% gap in orders of magnitude; 'sig_digits' (11) significant digits both sides
% are rounded to before comparing (0 = no rounding); 'verbose' (true) prints
% the table. The default 11 is the precision of reference per_run.csv files
% (written with %.10e): without it, a plateau cell such as 100.00000000000045
% vs 1.0000000000e+02 looks like a complete separation to the rank-sum test.
%
% For every (dimension, function) cell present in both sets it reports the
% Best / Median / Mean of the per-run values (errors for known-optimum suites;
% best_fitness where the error is not finite) and checks agreement two ways:
%   magnitude : Best, Median and Mean each agree within 'decades' orders of
%               magnitude (values with |v| < zero_tol count as 0; two zeros
%               agree); best_ok / median_ok / mean_ok show which one failed
%   rank-sum  : two-sided Wilcoxon rank-sum test (ranksum) at level alpha; a
%               cell whose values are identical on both sides gets p = 1
% verdict = MATCH when both checks pass, else DIFFERS. When both sets use the
% same seed for each run, the paired signed-rank p-value (p_signrank) is
% reported too, for information only. p_holm holds Holm-adjusted rank-sum
% p-values across all cells (counted in holm_significant, not in the verdict).
%
% report: struct with table, alpha, cells, matches, differs, holm_significant.
%
% Duplicate rows for one (dimension, function, run), left by append/resume in
% per_run.csv, keep the LAST row, as run_experiment's resume rules do.
% Requires the Statistics and Machine Learning Toolbox (ranksum, signrank).
% Errors: compare_reference_runs:toolbox (no ranksum), :missing (no
% per_run.csv found), :schema (a required column is missing).
%
% Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
% Cairo University: this framework code only; each algorithm belongs to its
% original authors. Licensing: gsk_family/LICENSES.md. Cite gsk_family/CITATION.cff.

p = inputParser;
p.addParameter('alpha', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
p.addParameter('out', '', @(x) ischar(x) || isstring(x));
p.addParameter('zero_tol', 1e-8, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('decades', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('sig_digits', 11, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x == round(x));
p.addParameter('verbose', true, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
o = p.Results;
if exist('ranksum', 'file') == 0
    error('compare_reference_runs:toolbox', ...
          'ranksum (Statistics and Machine Learning Toolbox) is required.');
end

G = read_per_run(resolve_path(generated));
R = read_per_run(resolve_path(reference));
keys = intersect(unique(G(:, 1:2), 'rows'), unique(R(:, 1:2), 'rows'), 'rows');

rows = struct('dim', {}, 'func', {}, 'n_gen', {}, 'n_ref', {}, ...
              'best_gen', {}, 'best_ref', {}, 'median_gen', {}, 'median_ref', {}, ...
              'mean_gen', {}, 'mean_ref', {}, 'best_ok', {}, 'median_ok', {}, ...
              'mean_ok', {}, 'magnitude_ok', {}, 'p_ranksum', {}, ...
              'p_signrank', {}, 'verdict', {});
for k = 1:size(keys, 1)
    g = G(G(:, 1) == keys(k, 1) & G(:, 2) == keys(k, 2), :);
    r = R(R(:, 1) == keys(k, 1) & R(:, 2) == keys(k, 2), :);
    g(:, 5) = round_sig(g(:, 5), o.sig_digits);
    r(:, 5) = round_sig(r(:, 5), o.sig_digits);
    gv = zero_cut(g(:, 5), o.zero_tol);
    rv = zero_cut(r(:, 5), o.zero_tol);
    s = struct();
    s.dim = keys(k, 1);
    s.func = keys(k, 2);
    s.n_gen = numel(gv);
    s.n_ref = numel(rv);
    s.best_gen = min(gv);       s.best_ref = min(rv);
    s.median_gen = median(gv);  s.median_ref = median(rv);
    s.mean_gen = zero_cut(mean(gv), o.zero_tol);
    s.mean_ref = zero_cut(mean(rv), o.zero_tol);
    s.best_ok = same_magnitude(s.best_gen, s.best_ref, o.decades);
    s.median_ok = same_magnitude(s.median_gen, s.median_ref, o.decades);
    s.mean_ok = same_magnitude(s.mean_gen, s.mean_ref, o.decades);
    s.magnitude_ok = s.best_ok && s.median_ok && s.mean_ok;
    if isequal(sort(gv), sort(rv))
        s.p_ranksum = 1;
    else
        s.p_ranksum = ranksum(gv, rv);
    end
    s.p_signrank = NaN;
    [common, ig, ir] = intersect(g(:, 3), r(:, 3));
    if ~isempty(common) && isequal(g(ig, 4), r(ir, 4))
        dpair = zero_cut(g(ig, 5), o.zero_tol) - zero_cut(r(ir, 5), o.zero_tol);
        if any(dpair ~= 0)
            s.p_signrank = signrank(dpair);
        else
            s.p_signrank = 1;
        end
    end
    if s.magnitude_ok && s.p_ranksum >= o.alpha
        s.verdict = 'MATCH';
    else
        s.verdict = 'DIFFERS';
    end
    rows(end + 1) = s; %#ok<AGROW>
end

T = struct2table(rows);
% Holm step-down adjustment across all cells: with many cells, about
% alpha * cells raw rank-sum rejections are expected by chance.
T.p_holm = holm(T.p_ranksum);
report = struct('table', T, 'alpha', o.alpha, 'cells', height(T), ...
                'matches', sum(strcmp(T.verdict, 'MATCH')), ...
                'differs', sum(strcmp(T.verdict, 'DIFFERS')), ...
                'holm_significant', sum(T.p_holm < o.alpha));
if strlength(string(o.out)) > 0
    writetable(T, char(o.out));
end
if logical(o.verbose)
    print_report(T, report, o);
end
end

% ---- helpers ------------------------------------------------------------------

function path = resolve_path(x)
% x is a per_run.csv file, or a folder holding summary/per_run.csv or
% per_run.csv (tried in that order).
x = char(x);
if isfile(x)
    path = x;
    return;
end
for cand = {fullfile(x, 'summary', 'per_run.csv'), fullfile(x, 'per_run.csv')}
    if isfile(cand{1})
        path = cand{1};
        return;
    end
end
error('compare_reference_runs:missing', 'No per_run.csv found at %s', x);
end

function M = read_per_run(path)
% Columns of M: dimension, function, run, seed, value (error if finite, else best).
T = readtable(path, 'Delimiter', ',', 'TextType', 'char', 'VariableNamingRule', 'preserve');
names = lower(T.Properties.VariableNames);
col = @(n) column(T, names, n, path);
value = col('error');
best = col('best_fitness');
value(~isfinite(value)) = best(~isfinite(value));
M = [col('dimension'), col('function'), col('run'), col('seed'), value];
% Resume history: keep the last row per (dimension, function, run).
[~, last] = unique(M(:, 1:3), 'rows', 'last');
M = M(sort(last), :);
end

function adj = holm(pv)
% Holm-Bonferroni adjusted p-values (same order as the input).
m = numel(pv);
[ps, order] = sort(pv(:));
a = min(1, (m - (1:m)' + 1) .* ps);
a = cummax(a);
adj = zeros(m, 1);
adj(order) = a;
end

function v = column(T, names, n, path)
k = find(strcmp(names, n), 1);
if isempty(k)
    error('compare_reference_runs:schema', 'per_run.csv column "%s" missing in %s', n, path);
end
v = double(T{:, k});
end

function v = zero_cut(v, tol)
v(abs(v) < tol) = 0;
end

function v = round_sig(v, n)
% Round to n significant digits (n = 0: unchanged). Zeros and non-finite
% values pass through.
if n > 0
    ok = isfinite(v) & v ~= 0;
    v(ok) = round(v(ok), n, 'significant');
end
end

function tf = same_magnitude(a, b, decades)
% True if a and b are both 0, or share a sign and differ by <= decades in log10.
if a == 0 && b == 0
    tf = true;
elseif a == 0 || b == 0 || sign(a) ~= sign(b)
    tf = false;
else
    tf = abs(log10(abs(a)) - log10(abs(b))) <= decades;
end
end

function print_report(T, report, o)
fprintf('\n%-5s %-4s %4s  %11s %11s  %11s %11s  %11s %11s  %3s %8s %8s  %s\n', 'Dim', 'Func', 'n', ...
        'Best(gen)', 'Best(ref)', 'Median(gen)', 'Median(ref)', 'Mean(gen)', 'Mean(ref)', ...
        'BMm', 'p_rank', 'p_pair', 'verdict');
flag = 'xo';   % magnitude flags per statistic: o = agrees, x = differs
for i = 1:height(T)
    fprintf('%-5d F%-3d %4d  %11.3e %11.3e  %11.3e %11.3e  %11.3e %11.3e  %3s %8.3g %8.3g  %s\n', ...
            T.dim(i), T.func(i), T.n_gen(i), T.best_gen(i), T.best_ref(i), ...
            T.median_gen(i), T.median_ref(i), T.mean_gen(i), T.mean_ref(i), ...
            flag([T.best_ok(i), T.median_ok(i), T.mean_ok(i)] + 1), ...
            T.p_ranksum(i), T.p_signrank(i), T.verdict{i});
end
fprintf('\n%d cell(s): %d MATCH, %d DIFFERS (rank-sum alpha = %g, Best/Median/Mean within %g decade(s), zero_tol = %g, %d significant digits)\n', ...
        report.cells, report.matches, report.differs, o.alpha, o.decades, o.zero_tol, o.sig_digits);
fprintf('Holm-adjusted rank-sum: %d of %d cell(s) significant at alpha = %g (about %.1f raw rejections expected by chance)\n', ...
        report.holm_significant, report.cells, o.alpha, o.alpha * report.cells);
end
