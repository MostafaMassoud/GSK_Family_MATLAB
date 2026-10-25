function report = plot_convergence(varargin)
%PLOT_CONVERGENCE Convergence curves of several optimizers in one figure per function.
%
%   plot_convergence('suite','cec2017', 'optimizers',{'gsk','my-gsk'})
%   report = plot_convergence('suite','cec2011', 'optimizers',{'gsk','agsk'}, ...
%                             'curve','mean', 'formats',{'png','pdf','fig'})
%
% Works for every suite (cec2011, cec2013, cec2013lsgo, cec2017, cec2020) and
% every optimizer with results, including one you added yourself. Run it from
% the gsk_family folder (or pass project_root) after the runs have finished.
%
% Options (all optional except suite):
%   suite         suite id, e.g. 'cec2017'.
%   optimizers    cell of optimizer ids, in legend order. Default: every
%                 optimizer folder under results_root that holds this suite.
%                 algorithms.ini aliases (e.g. 'gsk-np50') work the same way:
%                 each has its own results folder.
%   labels        legend names, same order as optimizers. Default: the usual
%                 names (GSK, AGSK, APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK),
%                 or the id in upper case for any other optimizer.
%   functions     function ids to plot. Default: all found.
%   dimensions    dimensions to plot (fixed-dimension suites). Default: all
%                 found. Native-dimension suites (cec2011, cec2013lsgo) plot
%                 each function at its own dimension and ignore this.
%   curve         'median_run' (default): the full trace of each optimizer's
%                 median run, from curves/Figure_F<f>_D<d>_Run#<r>.csv.
%                 'mean': the mean over all runs of the best-so-far value at
%                 the 14 CEC checkpoints, from gen_logs/CheckpointErrors_*.csv.
%                 'median': the median over all runs at those checkpoints.
%   band          'none' (default) or 'iqr': a shaded band per optimizer from
%                 the 25th to the 75th percentile of all runs at the 14 CEC
%                 checkpoints (gen_logs), under any curve type. Quartiles use
%                 linear interpolation.
%   yscale       'auto' (default): log when every plotted value is > 0, or
%                 when the suite has known optima (values below error_floor
%                 are drawn at error_floor); otherwise linear (raw objectives
%                 can be negative). 'log' or 'linear' force one.
%   error_floor   1e-8 (the CEC zero threshold). Used only on a log axis.
%   formats       cell of 'png', 'pdf', 'eps', 'fig'. Default {'png','pdf'}.
%   overview      true (default): also one tiled figure per dimension with
%                 every function (<suite>_D<d>_overview.*).
%   results_root  folder that holds <optimizer>/<suite>/. Default
%                 <project_root>/results/_run_all (where the launchers write).
%                 Use <project_root>/results for gsk_run output.
%   output_dir    Default <project_root>/results/analysis/convergence/<suite>.
%   project_root  Default pwd.
%   visible       false (default). true shows each figure while it is saved.
%
% Writes <suite>_F<f>_D<d>.<ext> per (function, dimension). A function that
% some optimizer lacks is still drawn with the optimizers that have it, and
% listed in report.incomplete. The returned report has fields figures (paths
% written), incomplete (cells missing an optimizer) and optimizers.
%
% The median run is chosen by the runner separately for each optimizer (the
% run whose final value is nearest the median of all runs). The runner always
% writes the curves and checkpoint logs; write_graphs only controls its own
% single-optimizer PNGs.

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('optimizers', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('curve', 'median_run', @(x) any(strcmpi(char(x), {'median_run', 'mean', 'median'})));
p.addParameter('band', 'none', @(x) any(strcmpi(char(x), {'none', 'iqr'})));
p.addParameter('yscale', 'auto', @(x) any(strcmpi(char(x), {'auto', 'log', 'linear'})));
p.addParameter('error_floor', 1e-8, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('formats', {'png', 'pdf'}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('overview', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('results_root', '', @(x) ischar(x) || isstring(x));
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite));
assert(~isempty(a.suite), 'plot_convergence:args', 'suite is required, e.g. ''cec2017''');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
a.results_root = char(a.results_root);
if isempty(a.output_dir); a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'convergence', a.suite); end
a.output_dir = char(a.output_dir);
a.formats = lower(cellstr(a.formats));
bad = setdiff(a.formats, {'png', 'pdf', 'eps', 'fig'});
assert(isempty(bad), 'plot_convergence:args', 'unknown format(s): %s', strjoin(bad, ', '));
a.curve = lower(char(a.curve));
a.band = lower(char(a.band));
a.yscale = lower(char(a.yscale));

opts = resolve_optimizers(a.results_root, a.suite, a.optimizers);
labels = resolve_labels(opts, a.labels);
native = is_native_suite(a.suite);
known_optimum = ~native;

% data{i}: containers.Map 'f|D' -> [x y] for optimizer i; bands{i}: 'f|D'
% -> [x q25 q75] when band = 'iqr', else empty.
data = cell(1, numel(opts));
bands = cell(1, numel(opts));
for i = 1:numel(opts)
    folder = fullfile(a.results_root, opts{i}, a.suite);
    stats = containers.Map('KeyType', 'char', 'ValueType', 'any');
    if ~strcmp(a.curve, 'median_run') || strcmp(a.band, 'iqr')
        stats = load_checkpoint_stats(fullfile(folder, 'gen_logs'));
    end
    switch a.curve
        case 'median_run'; data{i} = load_median_curves(fullfile(folder, 'curves'));
        case 'mean';       data{i} = pick_columns(stats, 2);
        case 'median';     data{i} = pick_columns(stats, 3);
    end
    if strcmp(a.band, 'iqr'); bands{i} = pick_columns(stats, [4 5]); end
    fprintf('plot_convergence: %-12s %3d curve(s) in %s\n', labels{i}, data{i}.Count, folder);
end

% Every (function, dimension) cell that at least one optimizer has.
cells = zeros(0, 2);
for i = 1:numel(opts)
    k = keys(data{i});
    for j = 1:numel(k)
        cells(end + 1, :) = sscanf(k{j}, '%d|%d')'; %#ok<AGROW>
    end
end
cells = unique(cells, 'rows');
if ~isempty(a.functions); cells = cells(ismember(cells(:, 1), a.functions), :); end
if ~isempty(a.dimensions) && ~native; cells = cells(ismember(cells(:, 2), a.dimensions), :); end
if native; cells = sortrows(cells, 1); else; cells = sortrows(cells, [2 1]); end
if isempty(cells)
    error('plot_convergence:noData', ['no convergence data for %s under %s. Check suite, ' ...
          'optimizers and results_root (launchers write to results/_run_all).'], a.suite, a.results_root);
end
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end

style = line_styles(numel(opts));
report = struct('figures', {{}}, 'incomplete', {{}}, 'optimizers', {opts});
for c = 1:size(cells, 1)
    f = cells(c, 1); D = cells(c, 2);
    fig = new_figure(a.visible, [100 100 640 460]);
    ax = axes(fig);
    missing = draw_cell(ax, data, bands, labels, style, f, D, a, known_optimum, true);
    title(ax, sprintf('%s  F%d  (D = %d)', suite_title(a.suite), f, D), 'FontWeight', 'normal');
    base = fullfile(a.output_dir, sprintf('%s_F%d_D%d', a.suite, f, D));
    report.figures = [report.figures, save_figure(fig, base, a.formats)];
    close(fig);
    if ~isempty(missing)
        report.incomplete{end + 1} = sprintf('F%d D%d: no data for %s', f, D, strjoin(missing, ', '));
    end
end

if logical(a.overview)
    if native; groups = {cells}; tags = {'all'};   % every problem at its own dimension
    else
        ud = unique(cells(:, 2))';
        groups = arrayfun(@(d) cells(cells(:, 2) == d, :), ud, 'UniformOutput', false);
        tags = arrayfun(@(d) sprintf('D%d', d), ud, 'UniformOutput', false);
    end
    for g = 1:numel(groups)
        report.figures = [report.figures, ...
            draw_overview(groups{g}, tags{g}, data, bands, labels, style, a, known_optimum)];
    end
end

for k = 1:numel(report.incomplete)
    fprintf('plot_convergence: incomplete %s\n', report.incomplete{k});
end
fprintf('plot_convergence: wrote %d file(s) to %s\n', numel(report.figures), a.output_dir);
end

% ---- drawing ----------------------------------------------------------------

function missing = draw_cell(ax, data, bands, labels, style, f, D, a, known_optimum, with_labels)
% Draw every optimizer's curve of cell (f, D) on ax; return the labels that
% have no data for it.
hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
key = sprintf('%d|%d', f, D);
missing = {};
curves = cell(1, numel(data));
for i = 1:numel(data)
    if isKey(data{i}, key); curves{i} = data{i}(key); else; missing{end + 1} = labels{i}; end %#ok<AGROW>
end
vals = cell2mat(cellfun(@(m) m(:, 2), curves(~cellfun('isempty', curves)), 'UniformOutput', false)');
band = cell(1, numel(data));
for i = 1:numel(data)
    if ~isempty(bands{i}) && isKey(bands{i}, key); band{i} = bands{i}(key); end
end
bvals = cell2mat(cellfun(@(m) reshape(m(:, 2:3), [], 1), band(~cellfun('isempty', band)), ...
                 'UniformOutput', false)');
vals = [vals; bvals];
use_log = strcmp(a.yscale, 'log') || (strcmp(a.yscale, 'auto') && ...
          (all(vals > 0) || (known_optimum && all(vals >= 0))));
% IQR bands first, so every curve stays on top of every band.
for i = 1:numel(data)
    b = band{i};
    if isempty(b) || isempty(curves{i}); continue; end
    lo = b(:, 2); hi = b(:, 3);
    if use_log; lo = max(lo, a.error_floor); hi = max(hi, a.error_floor); end
    fill(ax, [b(:, 1); flipud(b(:, 1))], [lo; flipud(hi)], style(i).color, 'FaceAlpha', 0.15, ...
         'EdgeColor', 'none', 'HandleVisibility', 'off');
end
for i = 1:numel(data)
    m = curves{i};
    if isempty(m); continue; end
    y = m(:, 2);
    if use_log; y = max(y, a.error_floor); end
    n = size(m, 1);
    marks = unique(round(linspace(1, n, min(n, 10))));
    plot(ax, m(:, 1), y, 'LineStyle', style(i).line, 'Color', style(i).color, ...
         'Marker', style(i).marker, 'MarkerIndices', marks, 'MarkerSize', 5, ...
         'LineWidth', 1.3, 'DisplayName', labels{i});
end
if use_log; set(ax, 'YScale', 'log'); end
if with_labels
    xlabel(ax, 'Function evaluations');
    ylabel(ax, y_label(a, known_optimum, use_log));
    legend(ax, 'Location', 'northeast', 'Interpreter', 'none');
end
end

function paths = draw_overview(cells, tag, data, bands, labels, style, a, known_optimum)
% One tiled figure with every function of a group and one shared legend.
n = size(cells, 1);
ncol = min(n, 5);
nrow = ceil(n / ncol);
fig = new_figure(a.visible, [50 50 300 * ncol, 240 * nrow + 80]);
t = tiledlayout(fig, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');
for c = 1:n
    ax = nexttile(t);
    draw_cell(ax, data, bands, labels, style, cells(c, 1), cells(c, 2), a, known_optimum, false);
    title(ax, sprintf('F%d (D = %d)', cells(c, 1), cells(c, 2)), 'FontWeight', 'normal');
    set(ax, 'FontSize', 8);
end
% Legend entries come from the first tile that has every optimizer.
lg = legend(nexttile(t, 1), 'Orientation', 'horizontal', 'Interpreter', 'none');
lg.Layout.Tile = 'north';
xlabel(t, 'Function evaluations');
ylabel(t, y_label(a, known_optimum, false));   % the y scale can differ by tile
if strcmp(tag, 'all'); group_text = 'all problems'; else; group_text = tag; end
title(t, sprintf('%s  %s  (%s)', suite_title(a.suite), group_text, curve_text(a.curve, a.band)));
paths = save_figure(fig, fullfile(a.output_dir, sprintf('%s_%s_overview', a.suite, tag)), a.formats);
close(fig);
end

function s = y_label(a, known_optimum, use_log)
if known_optimum; s = 'Error  f(x) - f(x*)'; else; s = 'Objective value  f(x)'; end
if use_log; s = [s ' (log scale)']; end
if strcmp(a.curve, 'mean'); s = ['Mean ' lower(s(1)) s(2:end)]; end
if strcmp(a.curve, 'median'); s = ['Median ' lower(s(1)) s(2:end)]; end
end

function s = curve_text(curve, band)
switch curve
    case 'mean';   s = 'mean of all runs';
    case 'median'; s = 'median of all runs';
    otherwise;     s = 'median run';
end
if strcmp(band, 'iqr'); s = [s ', band = 25-75% of all runs']; end
end

function paths = save_figure(fig, base, formats)
paths = {};
for k = 1:numel(formats)
    path = [base '.' formats{k}];
    switch formats{k}
        case 'png'; exportgraphics(fig, path, 'Resolution', 300, 'BackgroundColor', 'white');
        case 'pdf'; exportgraphics(fig, path, 'ContentType', 'vector', 'BackgroundColor', 'white');
        case 'eps'; exportgraphics(fig, path, 'ContentType', 'vector', 'BackgroundColor', 'white');
        case 'fig'; savefig(fig, path);
    end
    paths{end + 1} = path; %#ok<AGROW>
end
end

function style = line_styles(n)
% Distinct color, line style and marker per optimizer, so curves stay
% readable in grayscale print.
colors = lines(max(n, 7));
ls = {'-', '--', '-.', ':'};
mk = {'o', 's', '^', 'd', 'v', 'x', '+', '*', 'p', 'h'};
style = struct('color', {}, 'line', {}, 'marker', {});
for i = 1:n
    style(i).color = colors(i, :);
    style(i).line = ls{mod(i - 1, numel(ls)) + 1};
    style(i).marker = mk{mod(i - 1, numel(mk)) + 1};
end
end

function fig = new_figure(visible, position)
% White figure with the light theme, so a dark MATLAB desktop theme never
% reaches a manuscript figure (theme exists from R2025a; older releases are
% light by default).
fig = figure('Visible', on_off(visible), 'Color', 'w', 'Position', position);
if exist('theme', 'file') || exist('theme', 'builtin')
    theme(fig, 'light');
end
end

function s = on_off(tf)
if logical(tf); s = 'on'; else; s = 'off'; end
end

% ---- data loading -------------------------------------------------------------

function m = load_median_curves(curves_dir)
% Map 'f|D' -> [Eval BestError] from Figure_F<f>_D<d>_Run#<r>.csv. Older
% median curves of a resumed cell sit in curves/_archive and are not read.
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~exist(curves_dir, 'dir'); return; end
L = dir(fullfile(curves_dir, 'Figure_F*_D*_Run#*.csv'));
[~, order] = sort([L.datenum]);   % newest last, so it wins a duplicate
for q = order
    tok = regexp(L(q).name, '^Figure_F(\d+)_D(\d+)_Run#\d+\.csv$', 'tokens', 'once');
    if isempty(tok); continue; end
    M = readmatrix(fullfile(L(q).folder, L(q).name), 'NumHeaderLines', 1);
    if isempty(M) || size(M, 2) < 2; continue; end
    m(sprintf('%s|%s', tok{1}, tok{2})) = M(:, 1:2);
end
end

function m = load_checkpoint_stats(genlogs_dir)
% Map 'f|D' -> [nfes mean median q25 q75] over all runs at each checkpoint,
% from CheckpointErrors_<opt>_F<f>_D<d>.csv (columns Run,Seed,E<nfes>...). A
% run id that appears more than once (resumed sessions) keeps its last row.
% Quartiles use linear interpolation (quantile_local).
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~exist(genlogs_dir, 'dir'); return; end
L = dir(fullfile(genlogs_dir, 'CheckpointErrors_*_F*_D*.csv'));
for q = 1:numel(L)
    tok = regexp(L(q).name, '_F(\d+)_D(\d+)\.csv$', 'tokens', 'once');
    if isempty(tok); continue; end
    path = fullfile(L(q).folder, L(q).name);
    fid = fopen(path, 'r');
    header = fgetl(fid);
    fclose(fid);
    cols = strsplit(strtrim(header), ',');
    nfes = str2double(regexprep(cols(3:end), '^E', ''));
    M = readmatrix(path, 'NumHeaderLines', 1);
    if isempty(M) || size(M, 2) < numel(cols); continue; end
    [~, last] = unique(M(:, 1), 'last');
    E = M(last, 3:numel(cols));
    Q = zeros(size(E, 2), 3);
    for c = 1:size(E, 2); Q(c, :) = quantile_local(E(:, c), [0.5 0.25 0.75]); end
    m(sprintf('%s|%s', tok{1}, tok{2})) = [nfes(:), mean(E, 1)', Q];
end
end

function m = pick_columns(stats, cols)
% Map 'f|D' -> [nfes stats(:, cols)] (cols of [nfes mean median q25 q75]).
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
k = keys(stats);
for i = 1:numel(k)
    s = stats(k{i});
    m(k{i}) = s(:, [1 cols]);
end
end

function q = quantile_local(v, pr)
% Quantiles with linear interpolation (toolbox-free quantile of a vector).
v = sort(v(:));
n = numel(v);
pos = 1 + (n - 1) * pr(:)';
lo = floor(pos); hi = min(lo + 1, n);
q = v(lo)' + (pos - lo) .* (v(hi)' - v(lo)');
end

function opts = resolve_optimizers(results_root, suite, requested)
% Requested ids (normalized to the hyphenated public form), or every folder
% under results_root that has a <suite> subfolder.
if ~isempty(requested)
    opts = cellfun(@canonical_id, cellstr(requested), 'UniformOutput', false);
    for i = 1:numel(opts)
        folder = fullfile(results_root, opts{i}, suite);
        assert(exist(folder, 'dir') == 7, 'plot_convergence:noResults', ...
               'no results for %s on %s: %s does not exist', opts{i}, suite, folder);
    end
    return;
end
d = dir(results_root);
opts = {};
for k = 1:numel(d)
    if d(k).isdir && d(k).name(1) ~= '.' && d(k).name(1) ~= '_' && ...
            exist(fullfile(results_root, d(k).name, suite), 'dir') == 7
        opts{end + 1} = d(k).name; %#ok<AGROW>
    end
end
assert(~isempty(opts), 'plot_convergence:noResults', 'no optimizer has %s results under %s', suite, results_root);
end

function labels = resolve_labels(opts, given)
if ~isempty(given)
    labels = cellstr(given);
    assert(numel(labels) == numel(opts), 'plot_convergence:args', ...
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
% Same mapping as run_experiment: lower case, hyphenated public ids.
id = lower(strtrim(char(name)));
switch id
    case 'atmals_gsk'; id = 'atmals-gsk';
    case 'fdb_agsk';   id = 'fdb-agsk';
    case 'dt_gsk';     id = 'dt-gsk';
end
end

function tf = is_native_suite(suite)
tf = any(strcmp(suite, {'cec2011', 'cec2013lsgo'}));
end

function s = suite_title(suite)
switch suite
    case 'cec2013lsgo'; s = 'CEC2013-LSGO';
    otherwise;          s = upper(suite);
end
end
