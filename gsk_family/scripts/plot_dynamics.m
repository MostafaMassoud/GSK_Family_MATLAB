function report = plot_dynamics(varargin)
%PLOT_DYNAMICS Diversity, exploration/exploitation, population size and parameter trajectories.
%
%   plot_dynamics('suite','cec2017', 'optimizers',{'my-gsk','gsk','agsk'})
%
% Needs runs made with the opt-in trace: run_experiment(..., 'log_trace',
% true), or log_trace = true in a launcher's CONFIG. Each optimizer then
% records, per generation, its evaluations, population size, population
% diversity and its own adaptive parameters in
% trace/Dynamics_<name>_F<f>_D<d>.csv (tracing does not change the runs).
%
% Diversity (Hussain et al. 2019): for each dimension, the mean absolute
% distance of the population from the dimension's median, divided by the
% dimension's range, averaged over the dimensions. Exploration and
% exploitation of a run: XPL% = 100 Div / max(Div) and XPT% = 100 - XPL%
% (= 100 |Div - max(Div)| / max(Div)), max over that run.
%
% Writes to output_dir (default results/analysis/dynamics/<suite>), PNG/PDF:
%   diversity_<suite>_F<f>_D<d>    diversity against evaluations: the median
%                                  over all runs and a 25-75% band, one
%                                  line per optimizer (log axis when the
%                                  values span at least a decade)
%   xplxpt_<suite>_F<f>_D<d>       exploration/exploitation of each
%                                  optimizer's median run as stacked areas,
%                                  one panel per optimizer
%   xplxpt_<suite>.csv             mean XPL% and XPT% over each run, averaged
%                                  over the runs, per function and optimizer
%   population_<suite>_D<d>        population size against evaluations (the
%                                  median run of the first function)
%   parameters_<suite>_<name>_D<d> each traced parameter of an adaptive
%                                  optimizer against evaluations: one light
%                                  line per function (its median run) and
%                                  the median over the functions (thick)
% The median run is the one whose final value (per_run.csv) is closest to
% the median of the optimizer's runs on that function.
%
% Options: suite (required), optimizers, labels, functions, dimensions,
% figures ({'diversity','xplxpt','population','parameters'}), formats
% ({'png','pdf'}), results_root (results/_run_all), output_dir, project_root
% (pwd), visible (false).
%
% Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
% Cairo University. GPL-3.0-or-later; see gsk_family/LICENSES.md and cite
% gsk_family/CITATION.cff.

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('optimizers', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('figures', {'diversity', 'xplxpt', 'population', 'parameters'}, ...
               @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('formats', {'png', 'pdf'}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('results_root', '', @(x) ischar(x) || isstring(x));
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite));
assert(~isempty(a.suite), 'plot_dynamics:args', 'suite is required, e.g. ''cec2017''');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
if isempty(a.output_dir); a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'dynamics', a.suite); end
a.results_root = char(a.results_root); a.output_dir = char(a.output_dir);
a.formats = lower(cellstr(a.formats)); a.figures = lower(cellstr(a.figures));
native = any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));

opts = resolve_optimizers(a.results_root, a.suite, a.optimizers);
labels = resolve_labels(opts, a.labels);
data = cell(1, numel(opts));
for i = 1:numel(opts)
    folder = fullfile(a.results_root, opts{i}, a.suite);
    data{i} = load_dynamics(fullfile(folder, 'trace'), fullfile(folder, 'summary', 'per_run.csv'), native);
    if data{i}.Count == 0
        error('plot_dynamics:noTrace', ['no trace for %s in %s: run it with log_trace = true ' ...
              '(launcher CONFIG) or run_experiment(..., ''log_trace'', true)'], opts{i}, fullfile(folder, 'trace'));
    end
end
cells = zeros(0, 2);
for i = 1:numel(opts)
    k = keys(data{i});
    for j = 1:numel(k); cells(end + 1, :) = sscanf(k{j}, '%d|%d')'; end %#ok<AGROW>
end
cells = unique(cells, 'rows');
if ~isempty(a.functions); cells = cells(ismember(cells(:, 1), a.functions), :); end
if ~isempty(a.dimensions) && ~native; cells = cells(ismember(cells(:, 2), a.dimensions), :); end
cells = sortrows(cells, [2 1]);
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end
style = line_styles(numel(opts));
report = struct('figures', {{}}, 'optimizers', {opts});

% XPL/XPT table.
fid = fopen(fullfile(a.output_dir, sprintf('xplxpt_%s.csv', a.suite)), 'w');
c1 = onCleanup(@() fclose(fid));
fprintf(fid, 'dimension,function,optimizer,runs,mean_xpl_percent,mean_xpt_percent\n');
for c = 1:size(cells, 1)
    key = sprintf('%d|%d', cells(c, 1), cells(c, 2));
    for i = 1:numel(opts)
        if ~isKey(data{i}, key); continue; end
        d = data{i}(key);
        xs = cellfun(@(r) mean(xpl_of(r.diversity)), d.runs);
        fprintf(fid, '%s,%d,%s,%d,%.2f,%.2f\n', ternary(native, 'native', sprintf('%d', cells(c, 2))), ...
                cells(c, 1), opts{i}, numel(xs), mean(xs), 100 - mean(xs));
    end
end

for c = 1:size(cells, 1)
    f = cells(c, 1); D = cells(c, 2);
    key = sprintf('%d|%d', f, D);
    if any(strcmp(a.figures, 'diversity'))
        report.figures = [report.figures, diversity_figure(data, key, labels, style, a, f, D)];
    end
    if any(strcmp(a.figures, 'xplxpt'))
        report.figures = [report.figures, xplxpt_figure(data, key, labels, a, f, D)];
    end
end
if native; dims = 0; else; dims = unique(cells(:, 2))'; end
for D = dims
    dc = cells(native | cells(:, 2) == D, :);
    if any(strcmp(a.figures, 'population'))
        report.figures = [report.figures, population_figure(data, dc, labels, style, a, D, native)];
    end
    if any(strcmp(a.figures, 'parameters'))
        for i = 1:numel(opts)
            report.figures = [report.figures, parameter_figure(data{i}, dc, labels{i}, opts{i}, style(i), a, D, native)];
        end
    end
end
fprintf('plot_dynamics: wrote xplxpt_%s.csv and %d figure file(s) to %s\n', a.suite, numel(report.figures), a.output_dir);
end

% ---- figures ---------------------------------------------------------------------

function paths = diversity_figure(data, key, labels, style, a, f, D)
fig = new_figure(a.visible, [100 100 640 460]);
ax = axes(fig); hold(ax, 'on'); box(ax, 'off');
allv = [];
xmax_all = 0;
for i = 1:numel(data)
    if ~isKey(data{i}, key); continue; end
    d = data{i}(key);
    [x, Y] = on_grid(d.runs, 'diversity');
    xmax_all = max([xmax_all, x]);
    allv = [allv; Y(:)]; %#ok<AGROW>
    q = quantiles_rows(Y, [0.25 0.5 0.75]);
    fill(ax, [x, fliplr(x)], [max(q(1, :), 1e-12), fliplr(max(q(3, :), 1e-12))], style(i).color, ...
         'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(ax, x, max(q(2, :), 1e-12), 'LineStyle', style(i).line, 'Color', style(i).color, ...
         'LineWidth', 1.5, 'DisplayName', labels{i});
end
pos = allv(allv > 0);
if ~isempty(pos) && max(pos) / min(pos) >= 10; set(ax, 'YScale', 'log'); end
set(ax, 'YGrid', 'on', 'XGrid', 'off', 'YMinorGrid', 'off', 'GridAlpha', 0.12, ...
        'TickDir', 'out', 'LineWidth', 0.8);
xlim(ax, [0, xmax_all]);
xlabel(ax, 'Function evaluations'); ylabel(ax, 'Population diversity (scaled to the bounds)');
legend(ax, 'Location', 'northeast', 'Interpreter', 'none', 'Box', 'off');
title(ax, sprintf('%s  F%d  (D = %d)  median and 25-75%% of all runs', suite_title(a.suite), f, D), ...
      'FontWeight', 'normal');
paths = save_figure(fig, fullfile(a.output_dir, sprintf('diversity_%s_F%d_D%d', a.suite, f, D)), a.formats);
close(fig);
end

function paths = xplxpt_figure(data, key, labels, a, f, D)
have = find(cellfun(@(m) isKey(m, key), data));
n = numel(have);
ncol = min(n, 4); nrow = ceil(n / ncol);
fig = new_figure(a.visible, [50 50 300 * ncol, 230 * nrow + 70]);
t = tiledlayout(fig, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');
for j = 1:n
    d = data{have(j)}(key);
    r = d.runs{d.median_run};
    xpl = xpl_of(r.diversity);
    ax = nexttile(t); hold(ax, 'on'); box(ax, 'off');
    h = area(ax, r.nfes, [xpl, 100 - xpl], 'LineStyle', 'none');
    h(1).FaceColor = [0.30 0.55 0.85]; h(1).FaceAlpha = 0.55; h(1).DisplayName = 'Exploration %';
    h(2).FaceColor = [0.95 0.60 0.25]; h(2).FaceAlpha = 0.55; h(2).DisplayName = 'Exploitation %';
    ylim(ax, [0 100]); xlim(ax, [r.nfes(1), r.nfes(end)]);
    set(ax, 'TickDir', 'out', 'FontSize', 8, 'Layer', 'top');
    title(ax, sprintf('%s  (XPL %.0f%%, XPT %.0f%%)', labels{have(j)}, mean(xpl), 100 - mean(xpl)), ...
          'FontWeight', 'normal', 'Interpreter', 'none');
    if j == 1
        lg = legend(ax, 'Orientation', 'horizontal', 'Box', 'off');
        lg.Layout.Tile = 'north';
    end
end
xlabel(t, 'Function evaluations'); ylabel(t, 'Share of the run (%)');
title(t, sprintf('%s  F%d  (D = %d)  exploration and exploitation, median run', suite_title(a.suite), f, D));
paths = save_figure(fig, fullfile(a.output_dir, sprintf('xplxpt_%s_F%d_D%d', a.suite, f, D)), a.formats);
close(fig);
end

function paths = population_figure(data, dc, labels, style, a, D, native)
fig = new_figure(a.visible, [100 100 640 440]);
ax = axes(fig); hold(ax, 'on'); box(ax, 'off');
xmax_all = 0;
for i = 1:numel(data)
    key = '';
    for c = 1:size(dc, 1)
        kk = sprintf('%d|%d', dc(c, 1), dc(c, 2));
        if isKey(data{i}, kk); key = kk; break; end
    end
    if isempty(key); continue; end
    d = data{i}(key);
    r = d.runs{d.median_run};
    x = r.nfes; if native; x = x / x(end); end
    stairs(ax, x, r.np, 'LineStyle', style(i).line, 'Color', style(i).color, 'LineWidth', 1.6, ...
           'DisplayName', labels{i});
    xmax_all = max([0, xmax_all(:)', x(:)']);
end
xlim(ax, [0, xmax_all]);
set(ax, 'YGrid', 'on', 'XGrid', 'off', 'GridAlpha', 0.12, 'TickDir', 'out', 'LineWidth', 0.8);
if native; xlabel(ax, 'Fraction of the evaluation budget'); else; xlabel(ax, 'Function evaluations'); end
ylabel(ax, 'Population size');
legend(ax, 'Location', 'eastoutside', 'Interpreter', 'none', 'Box', 'off');
tag = ternary(native, 'all problems', sprintf('D = %d', D));
title(ax, sprintf('%s  %s  population size (median run)', suite_title(a.suite), tag), 'FontWeight', 'normal');
paths = save_figure(fig, fullfile(a.output_dir, sprintf('population_%s_%s', a.suite, ...
                    ternary(native, 'all', sprintf('D%d', D)))), a.formats);
close(fig);
end

function paths = parameter_figure(dmap, dc, label, name, sty, a, D, native)
% One tile per parameter column; light line per function (median run), thick median.
paths = {};
k = keys(dmap);
sel = k(cellfun(@(s) ismember(sscanf(s, '%d|%d')', dc, 'rows'), k));
if isempty(sel); return; end
first = dmap(sel{1});
pn = first.param_names;
if isempty(pn); return; end
np = numel(pn);
ncol = min(np, 3); nrow = ceil(np / ncol);
fig = new_figure(a.visible, [50 50 330 * ncol, 240 * nrow + 70]);
t = tiledlayout(fig, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');
grid_x = linspace(0, 1, 101);
for j = 1:np
    ax = nexttile(t); hold(ax, 'on'); box(ax, 'off');
    Y = nan(numel(sel), numel(grid_x));
    for s = 1:numel(sel)
        d = dmap(sel{s});
        r = d.runs{d.median_run};
        if ~isfield(r.params, pn{j}); continue; end
        frac = r.nfes / r.nfes(end);
        y = r.params.(pn{j});
        Y(s, :) = step_interp(frac, y, grid_x);
        plot(ax, grid_x, Y(s, :), '-', 'Color', [sty.color, 0.25], 'LineWidth', 0.6, 'HandleVisibility', 'off');
    end
    plot(ax, grid_x, median(Y, 1, 'omitnan'), '-', 'Color', sty.color * 0.8, 'LineWidth', 2.2);
    v = Y(~isnan(Y));
    if ~isempty(v) && all(v == 0 | v == 1); ylim(ax, [-0.05 1.05]); set(ax, 'YTick', [0 1]); end
    set(ax, 'YGrid', 'on', 'XGrid', 'off', 'GridAlpha', 0.12, 'TickDir', 'out', 'FontSize', 8);
    title(ax, strrep(pn{j}, '_', ' '), 'FontWeight', 'normal');
end
xlabel(t, 'Fraction of the evaluation budget');
tag = ternary(native, 'all problems', sprintf('D = %d', D));
title(t, sprintf('%s  %s  %s parameters (light: each function''s median run; thick: median)', ...
      suite_title(a.suite), tag, label), 'Interpreter', 'none');
paths = save_figure(fig, fullfile(a.output_dir, sprintf('parameters_%s_%s_%s', a.suite, name, ...
                    ternary(native, 'all', sprintf('D%d', D)))), a.formats);
close(fig);
end

% ---- computations ------------------------------------------------------------------

function x = xpl_of(div)
% XPL% = 100 Div / max(Div) of one run (0 where max(Div) is 0).
m = max(div);
if ~(m > 0); x = zeros(size(div)); else; x = 100 * div / m; end
end

function [x, Y] = on_grid(runs, field)
% All runs of a cell on a common evaluation grid (step interpolation).
xmax = max(cellfun(@(r) r.nfes(end), runs));
x = linspace(0, xmax, 151);
Y = zeros(numel(runs), numel(x));
for r = 1:numel(runs)
    Y(r, :) = step_interp(runs{r}.nfes, runs{r}.(field), x);
end
end

function y = step_interp(x, v, xq)
% Value of the step function (x, v) at xq: the last recorded value at or
% before xq (the first value before the first record).
x = x(:)'; v = v(:)';
y = zeros(size(xq));
for q = 1:numel(xq)
    j = find(x <= xq(q) * (1 + 1e-12), 1, 'last');
    if isempty(j); j = 1; end
    y(q) = v(j);
end
end

function q = quantiles_rows(Y, pr)
% Column-wise quantiles (linear interpolation) of a runs x grid matrix.
q = zeros(numel(pr), size(Y, 2));
for c = 1:size(Y, 2)
    v = sort(Y(:, c));
    n = numel(v);
    pos = 1 + (n - 1) * pr(:);
    lo = floor(pos); hi = min(lo + 1, n);
    q(:, c) = v(lo) + (pos - lo) .* (v(hi) - v(lo));
end
end

% ---- data loading ----------------------------------------------------------------------

function m = load_dynamics(trace_dir, per_run_path, native)
% Map 'f|D' -> struct(runs (cell of struct: nfes, np, diversity, params),
% run_ids, median_run (index into runs), param_names).
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~exist(trace_dir, 'dir'); return; end
finals = containers.Map('KeyType', 'char', 'ValueType', 'double');
if isfile(per_run_path)
    T = readtable(per_run_path, 'VariableNamingRule', 'preserve', 'Delimiter', ',');
    if native; v = T.best_fitness; else; v = T.error; end
    for r = 1:height(T)
        finals(sprintf('%d|%d|%d', T.('function')(r), T.dimension(r), T.run(r))) = v(r);
    end
end
L = dir(fullfile(trace_dir, 'Dynamics_*_F*_D*.csv'));
for q = 1:numel(L)
    tok = regexp(L(q).name, '_F(\d+)_D(\d+)\.csv$', 'tokens', 'once');
    if isempty(tok); continue; end
    path = fullfile(L(q).folder, L(q).name);
    fid = fopen(path, 'r'); header = strtrim(fgetl(fid)); fclose(fid);
    cols = strsplit(header, ',');
    M = readmatrix(path, 'NumHeaderLines', 1);
    if isempty(M); continue; end
    pn = cols(6:end);
    ids = unique(M(:, 1), 'stable');
    runs = cell(1, numel(ids)); fin = nan(1, numel(ids));
    for r = 1:numel(ids)
        R = M(M(:, 1) == ids(r), :);
        [~, last_block] = max(flipud(R(:, 2) == 0));   % a resumed run id keeps its last block
        start = size(R, 1) - last_block + 1;
        R = R(start:end, :);
        s = struct('nfes', R(:, 3), 'np', R(:, 4), 'diversity', R(:, 5), 'params', struct());
        for j = 1:numel(pn); s.params.(pn{j}) = R(:, 5 + j); end
        runs{r} = s;
        kk = sprintf('%s|%s|%d', tok{1}, tok{2}, ids(r));
        if isKey(finals, kk); fin(r) = finals(kk); end
    end
    if all(isnan(fin)); med = 1; else; [~, med] = min(abs(fin - median(fin, 'omitnan'))); end
    m(sprintf('%s|%s', tok{1}, tok{2})) = struct('runs', {runs}, 'run_ids', ids', 'median_run', med, ...
                                                 'param_names', {pn});
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
            exist(fullfile(results_root, d(k).name, suite, 'trace'), 'dir') == 7
        opts{end + 1} = d(k).name; %#ok<AGROW>
    end
end
assert(~isempty(opts), 'plot_dynamics:noTrace', 'no optimizer under %s has a %s trace', results_root, suite);
end

function labels = resolve_labels(opts, given)
if ~isempty(given)
    labels = cellstr(given);
    assert(numel(labels) == numel(opts), 'plot_dynamics:args', 'labels must have one entry per optimizer');
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
