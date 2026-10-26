function report = plot_performance(varargin)
%PLOT_PERFORMANCE Success rates, ERT tables and ECDF data profiles of several optimizers.
%
%   plot_performance('suite','cec2017', 'optimizers',{'my-gsk','gsk','agsk'})
%   report = plot_performance('suite','cec2017', 'targets',[1e2 1 1e-2 1e-8], 'ert_target',1e-2)
%
% Works for every suite and every optimizer with results (also your own and
% algorithms.ini aliases). Reads, per optimizer, the best-so-far value of
% every run over the budget from gen_logs/: BestTrace_<name>_F<f>_D<d>.csv
% when the runs were made with trace_points (dense, log-spaced budgets), else
% the 14 CEC checkpoints of CheckpointErrors_<name>_F<f>_D<d>.csv (the
% results then step at those budgets). 'source' forces one.
%
% For a target t (an error f(x) - f(x*) <= t), a run succeeds at the first
% recorded budget where it reaches t. Per (dimension, function, optimizer,
% target), following COCO (Hansen et al.):
%   success rate  successful runs / runs
%   ERT           (evaluations of the successful runs until success + the
%                 full budget of each unsuccessful run) / successful runs;
%                 Inf when no run succeeds
%   ECDF          fraction of (function, target, run) triples reached
%                 within each budget, pooled over the functions of a group
% Suites without known optima (cec2011, cec2013lsgo) use the distance to the
% best value found by any compared optimizer in any run, divided by
% max(|that value|, 1), with targets 1e-1 ... 1e-6 by default.
%
% Writes to output_dir (default results/analysis/performance/<suite>):
%   performance_<suite>.csv   dimension, function, optimizer, target, runs,
%                             successes, success_rate, ert
%   ert_<suite>_<tag>.tex     ERT (success rate) per function at ert_target,
%                             smallest ERT in bold
%   ecdf_<suite>_<tag>.*      ECDF per dimension (x = evaluations), and
%   ecdf_<suite>_overall.*    all dimensions pooled (x = fraction of budget)
%
% Options (all optional except suite): optimizers, labels, functions,
% dimensions (as in compare_algorithms); targets (default 1e2 1e1 1 1e-1 1e-2
% 1e-4 1e-6 1e-8; relative 1e-1 1e-2 1e-3 1e-4 1e-6 without known optima);
% ert_target (default the smallest target); source ('auto' | 'trace' |
% 'checkpoints'); formats ({'png','pdf'}); results_root
% (results/_run_all); output_dir; project_root (pwd); visible (false).
%
% Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
% Cairo University: this framework code only; each algorithm belongs to its
% original authors. Licensing: gsk_family/LICENSES.md. Cite gsk_family/CITATION.cff.

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('optimizers', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('targets', [], @isnumeric);
p.addParameter('ert_target', [], @isnumeric);
p.addParameter('source', 'auto', @(x) any(strcmpi(char(x), {'auto', 'trace', 'checkpoints'})));
p.addParameter('formats', {'png', 'pdf'}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('results_root', '', @(x) ischar(x) || isstring(x));
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite));
assert(~isempty(a.suite), 'plot_performance:args', 'suite is required, e.g. ''cec2017''');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
if isempty(a.output_dir); a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'performance', a.suite); end
a.results_root = char(a.results_root); a.output_dir = char(a.output_dir);
a.formats = lower(cellstr(a.formats)); a.source = lower(char(a.source));
native = any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));
relative = native;   % no known optimum: distance to the best value found
if isempty(a.targets)
    if relative; a.targets = [1e-1 1e-2 1e-3 1e-4 1e-6]; else; a.targets = [1e2 1e1 1 1e-1 1e-2 1e-4 1e-6 1e-8]; end
end
a.targets = sort(a.targets(:)', 'descend');
if isempty(a.ert_target); a.ert_target = a.targets(end); end

opts = resolve_optimizers(a.results_root, a.suite, a.optimizers);
labels = resolve_labels(opts, a.labels);
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end

% Data: data{i}('f|D') = struct('budgets', 1 x B, 'values', runs x B).
use_trace = ~strcmp(a.source, 'checkpoints');
data = cell(1, numel(opts));
for i = 1:numel(opts)
    gl = fullfile(a.results_root, opts{i}, a.suite, 'gen_logs');
    data{i} = load_traces(gl, 'BestTrace');
    if strcmp(a.source, 'trace') && data{i}.Count == 0
        error('plot_performance:noTrace', ['no BestTrace files for %s: run it with trace_points ' ...
              '(launcher CONFIG trace_points = 50) or use ''source'',''checkpoints'''], opts{i});
    end
    if data{i}.Count == 0 || ~use_trace; use_trace = false; end
end
if ~use_trace
    for i = 1:numel(opts)
        data{i} = load_traces(fullfile(a.results_root, opts{i}, a.suite, 'gen_logs'), 'CheckpointErrors');
    end
end
src_text = ternary(use_trace, 'dense trace', '14 CEC checkpoints');
fprintf('plot_performance: %s, budgets from the %s\n', suite_title(a.suite), src_text);

% Cells every optimizer has.
cells = cell2mat(cellfun(@(s) sscanf(s, '%d|%d')', keys(data{1})', 'UniformOutput', false));
for i = 2:numel(opts)
    if isempty(cells); break; end
    ki = cellfun(@(s) sscanf(s, '%d|%d')', keys(data{i})', 'UniformOutput', false);
    if isempty(ki); cells = zeros(0, 2); break; end
    cells = intersect(cells, cell2mat(ki), 'rows');
end
if ~isempty(a.functions); cells = cells(ismember(cells(:, 1), a.functions), :); end
if ~isempty(a.dimensions) && ~native; cells = cells(ismember(cells(:, 2), a.dimensions), :); end
assert(~isempty(cells), 'plot_performance:noData', 'no gen_logs data common to all optimizers for %s', a.suite);
cells = sortrows(cells, [2 1]);

% Errors to targets: e = value (known optimum), or (value - best) / max(|best|, 1).
fid = fopen(fullfile(a.output_dir, sprintf('performance_%s.csv', a.suite)), 'w');
c1 = onCleanup(@() fclose(fid));
fprintf(fid, 'dimension,function,optimizer,target,runs,successes,success_rate,ert\n');
res = struct('cell', {}, 'opt', {}, 'target', {}, 'sr', {}, 'ert', {}, 'hit_frac', {}, 'budgets', {});
for c = 1:size(cells, 1)
    key = sprintf('%d|%d', cells(c, 1), cells(c, 2));
    if relative
        best = min(cellfun(@(d) min(d(key).values(:)), data));
        scale = max(abs(best), 1);
    end
    dtext = ternary(native, 'native', sprintf('%d', cells(c, 2)));
    for i = 1:numel(opts)
        s = data{i}(key);
        E = s.values;
        if relative; E = (E - best) / scale; end
        nmax = s.budgets(end);
        for t = a.targets
            hit = E <= t;                                     % runs x budgets, monotone in budgets
            first = arrayfun(@(r) first_true(hit(r, :)), 1:size(E, 1));
            ok = first > 0;
            ev = nmax * ones(1, size(E, 1));
            ev(ok) = s.budgets(first(ok));
            ns = nnz(ok);
            ert = ternary(ns > 0, sum(ev) / max(ns, 1), Inf);
            fprintf(fid, '%s,%d,%s,%g,%d,%d,%.4f,%.6g\n', dtext, cells(c, 1), opts{i}, t, size(E, 1), ns, ...
                    ns / size(E, 1), ert);
            res(end + 1) = struct('cell', cells(c, :), 'opt', i, 'target', t, 'sr', ns / size(E, 1), ...
                'ert', ert, 'hit_frac', mean(hit, 1), 'budgets', s.budgets); %#ok<AGROW>
        end
    end
end

style = line_styles(numel(opts));
report = struct('figures', {{}}, 'optimizers', {opts}, 'source', src_text, 'results', res);
if native; groups = {cells}; tags = {'all'};
else
    ud = unique(cells(:, 2))';
    groups = arrayfun(@(d) cells(cells(:, 2) == d, :), ud, 'UniformOutput', false);
    tags = arrayfun(@(d) sprintf('D%d', d), ud, 'UniformOutput', false);
end
for g = 1:numel(groups)
    write_ert_table(fullfile(a.output_dir, sprintf('ert_%s_%s.tex', a.suite, tags{g})), groups{g}, ...
                    res, labels, a, tags{g}, native, relative);
    report.figures = [report.figures, ecdf_figure(groups{g}, res, labels, style, a, tags{g}, false, src_text, relative)];
end
if numel(groups) > 1
    report.figures = [report.figures, ecdf_figure(cells, res, labels, style, a, 'overall', true, src_text, relative)];
end
fprintf('plot_performance: wrote performance_%s.csv, ERT tables and %d figure file(s) to %s\n', ...
        a.suite, numel(report.figures), a.output_dir);
end

% ---- figures and tables ----------------------------------------------------------

function paths = ecdf_figure(cells, res, labels, style, a, tag, normalized, src_text, relative)
% ECDF of (function, target, run) triples reached by each budget, one step
% curve per optimizer. normalized = true: x is the fraction of the budget,
% so dimensions with different budgets can be pooled.
fig = new_figure(a.visible, [100 100 640 460]);
ax = axes(fig); hold(ax, 'on'); box(ax, 'off');
in = arrayfun(@(r) ismember(r.cell, cells, 'rows'), res);
for i = 1:numel(labels)
    sel = res(in & [res.opt] == i);
    if isempty(sel); continue; end
    if normalized
        grid_x = logspace(-4, 0, 200);
        y = zeros(size(grid_x));
        for r = sel
            frac = r.budgets / r.budgets(end);
            y = y + interp_step(frac, r.hit_frac, grid_x);
        end
    else
        grid_x = unique([sel.budgets]);
        y = zeros(size(grid_x));
        for r = sel
            y = y + interp_step(r.budgets, r.hit_frac, grid_x);
        end
    end
    y = y / numel(sel);
    stairs(ax, grid_x, y, 'LineStyle', style(i).line, 'Color', style(i).color, 'LineWidth', 1.6, ...
           'DisplayName', labels{i});
end
set(ax, 'XScale', 'log', 'XGrid', 'on', 'YGrid', 'on', 'GridAlpha', 0.12, 'XMinorGrid', 'off', ...
        'TickDir', 'out', 'LineWidth', 0.8);
ylim(ax, [0 1]);
if normalized; xlabel(ax, 'Fraction of the evaluation budget'); else; xlabel(ax, 'Function evaluations'); end
ylabel(ax, 'Fraction of (function, target, run) reached');
legend(ax, 'Location', 'northwest', 'Interpreter', 'none', 'Box', 'off');
tt = sprintf('%s  %s  ECDF, %d targets', suite_title(a.suite), group_text(tag), numel(a.targets));
if relative; tt = [tt ' (relative to the best value found)']; end
title(ax, {tt, sprintf('budgets from the %s', src_text)}, 'FontWeight', 'normal', 'FontSize', 10);
paths = save_figure(fig, fullfile(a.output_dir, sprintf('ecdf_%s_%s', a.suite, tag)), a.formats);
close(fig);
end

function y = interp_step(x, v, xq)
% Value of the right-continuous step function (x, v) at xq (0 before x(1)).
y = zeros(size(xq));
for q = 1:numel(xq)
    j = find(x <= xq(q) * (1 + 1e-12), 1, 'last');
    if ~isempty(j); y(q) = v(j); end
end
end

function write_ert_table(path, cells, res, labels, a, tag, native, relative)
fid = fopen(path, 'w');
c = onCleanup(@() fclose(fid));
k = numel(labels);
fprintf(fid, '%% %s %s: ERT (evaluations) and success rate at target %g; "--" = no successful run.\n', ...
        suite_title(a.suite), tag, a.ert_target);
if relative
    fprintf(fid, '%% Target relative to the best value found by any compared optimizer.\n');
end
fprintf(fid, '\\begin{tabular}{l%s%s}\n\\hline\n', repmat('r', 1, native), repmat('c', 1, k));
fprintf(fid, 'Func.');
if native; fprintf(fid, ' & $D$'); end
for i = 1:k; fprintf(fid, ' & %s', strrep(labels{i}, '_', '\_')); end
fprintf(fid, ' \\\\\n\\hline\n');
for r = 1:size(cells, 1)
    sel = res(arrayfun(@(x) isequal(x.cell, cells(r, :)), res) & abs([res.target] - a.ert_target) <= 1e-12 * a.ert_target);
    erts = inf(1, k); srs = zeros(1, k);
    for s = sel; erts(s.opt) = s.ert; srs(s.opt) = s.sr; end
    fprintf(fid, 'F%d', cells(r, 1));
    if native; fprintf(fid, ' & %d', cells(r, 2)); end
    best = min(erts);
    for i = 1:k
        if isinf(erts(i))
            cellv = sprintf('-- (%.2f)', srs(i));
        else
            cellv = sprintf('%.0f (%.2f)', erts(i), srs(i));
            if erts(i) == best; cellv = ['\textbf{' cellv '}']; end
        end
        fprintf(fid, ' & %s', cellv);
    end
    fprintf(fid, ' \\\\\n');
end
fprintf(fid, '\\hline\n\\end{tabular}\n');
end

% ---- data loading -------------------------------------------------------------

function m = load_traces(genlogs_dir, prefix)
% Map 'f|D' -> struct(budgets, values) from <prefix>_*_F<f>_D<d>.csv
% (Run,Seed,E<budget>...); a run id that appears more than once keeps its
% last row.
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~exist(genlogs_dir, 'dir'); return; end
L = dir(fullfile(genlogs_dir, sprintf('%s_*_F*_D*.csv', prefix)));
for q = 1:numel(L)
    tok = regexp(L(q).name, '_F(\d+)_D(\d+)\.csv$', 'tokens', 'once');
    if isempty(tok); continue; end
    path = fullfile(L(q).folder, L(q).name);
    fid = fopen(path, 'r'); header = fgetl(fid); fclose(fid);
    cols = strsplit(strtrim(header), ',');
    budgets = str2double(regexprep(cols(3:end), '^E', ''));
    M = readmatrix(path, 'NumHeaderLines', 1);
    if isempty(M) || size(M, 2) < numel(cols); continue; end
    [~, last] = unique(M(:, 1), 'last');
    m(sprintf('%s|%s', tok{1}, tok{2})) = struct('budgets', budgets(:)', 'values', M(last, 3:numel(cols)));
end
end

function j = first_true(v)
j = find(v, 1);
if isempty(j); j = 0; end
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
            exist(fullfile(results_root, d(k).name, suite, 'gen_logs'), 'dir') == 7
        opts{end + 1} = d(k).name; %#ok<AGROW>
    end
end
end

function labels = resolve_labels(opts, given)
if ~isempty(given)
    labels = cellstr(given);
    assert(numel(labels) == numel(opts), 'plot_performance:args', 'labels must have one entry per optimizer');
    return;
end
labels = cellfun(@(id) ternary(strcmp(id, 'egsk'), 'eGSK', upper(id)), opts, 'UniformOutput', false);
end

function id = canonical_id(name)
id = lower(strtrim(char(name)));
switch id
    case 'atmals_gsk'; id = 'atmals-gsk';
    case 'fdb_agsk';   id = 'fdb-agsk';
    case 'dt_gsk';     id = 'dt-gsk';
end
end

function style = line_styles(n)
% The colours and line styles of plot_convergence.
colors = lines(max(n, 7));
ls = {'-', '--', '-.', ':'};
style = struct('color', {}, 'line', {});
for i = 1:n
    style(i).color = colors(i, :);
    style(i).line = ls{mod(i - 1, numel(ls)) + 1};
end
end

function s = group_text(tag)
switch tag
    case 'all';     s = 'all problems';
    case 'overall'; s = 'all dimensions';
    otherwise;      s = tag;
end
end

function fig = new_figure(visible, position)
if logical(visible); v = 'on'; else; v = 'off'; end
fig = figure('Visible', v, 'Color', 'w', 'Position', position);
if exist('theme', 'file') || exist('theme', 'builtin')
    theme(fig, 'light');
end
end

function paths = save_figure(fig, base, formats)
paths = {};
for k = 1:numel(formats)
    path = [base '.' formats{k}];
    switch formats{k}
        case 'png'; exportgraphics(fig, path, 'Resolution', 300, 'BackgroundColor', 'white');
        case {'pdf', 'eps'}; exportgraphics(fig, path, 'ContentType', 'vector', 'BackgroundColor', 'white');
        case 'fig'; savefig(fig, path);
    end
    paths{end + 1} = path; %#ok<AGROW>
end
end

function out = ternary(c, x, y)
if c; out = x; else; out = y; end
end

function s = suite_title(suite)
switch suite
    case 'cec2013lsgo'; s = 'CEC2013-LSGO';
    otherwise;          s = upper(suite);
end
end
