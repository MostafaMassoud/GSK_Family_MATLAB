function report = plot_statistics(varargin)
%PLOT_STATISTICS CD diagrams, box/violin plots and rank charts of several optimizers.
%
%   plot_statistics('suite','cec2017', 'optimizers',{'my-gsk','gsk','agsk'}, 'proposed','my-gsk')
%   report = plot_statistics('suite','cec2011', 'figures',{'cd','box'})
%
% Works for every suite and every optimizer with results (also your own and
% algorithms.ini aliases). Run it from the gsk_family folder (or pass
% project_root) after the runs have finished. It calls compare_algorithms
% (same options) for the Friedman ranks and the Nemenyi critical difference,
% so the figures always match the tables, and reads each optimizer's
% summary/per_run.csv for the box and violin plots.
%
% Figures (option 'figures', default {'cd','box','ranks'}; 'violin' on request):
%   'cd'      critical difference diagram per group and overall
%             (cd_<suite>_<tag>.*): optimizers on their Friedman mean rank
%             (1 = best); a bar joins optimizers whose ranks differ by less
%             than the Nemenyi CD, i.e. not significantly different (Demsar
%             2006).
%   'box'     box plots of the final values of every run, one figure per
%             (function, dimension) with all optimizers (box_<suite>_F<f>_D<d>.*),
%             plus one overview per group (box_<suite>_<tag>_overview.*).
%   'violin'  the same as violin plots (violin_...): the outline is a Gaussian
%             kernel density of the runs (Silverman bandwidth), on the log
%             axis when the values are log-scaled; the white dot is the median.
%   'ranks'   Friedman mean ranks as grouped bars per group and overall
%             (ranks_<suite>_bars.*), and a radar chart over the groups when
%             there are at least three (ranks_<suite>_radar.*).
% Groups are the dimensions (fixed-dimension suites) or 'all' (cec2011,
% cec2013lsgo).
%
% Other options: suite (required), optimizers, labels, proposed, functions,
% dimensions, alpha (0.05), correction ('none') as in compare_algorithms; formats ({'png','pdf'};
% also 'eps', 'fig'); yscale ('auto' | 'log' | 'linear'; auto = log when the
% suite has known optima or every value is > 0); error_floor (1e-8, used on
% a log axis); results_root (results/_run_all); output_dir
% (results/analysis/statistics/<suite>); compare_dir (where the
% compare_algorithms tables go; results/analysis/compare/<suite>);
% project_root (pwd); visible (false).
%
% Base MATLAB only (boxchart, polarplot, tiledlayout: R2020b or newer).

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('optimizers', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
p.addParameter('proposed', '', @(x) ischar(x) || isstring(x));
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('alpha', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
p.addParameter('correction', 'none', @(x) any(strcmpi(char(x), {'none', 'holm'})));
p.addParameter('figures', {'cd', 'box', 'ranks'}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('formats', {'png', 'pdf'}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('yscale', 'auto', @(x) any(strcmpi(char(x), {'auto', 'log', 'linear'})));
p.addParameter('error_floor', 1e-8, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('results_root', '', @(x) ischar(x) || isstring(x));
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('compare_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite));
assert(~isempty(a.suite), 'plot_statistics:args', 'suite is required, e.g. ''cec2017''');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
if isempty(a.output_dir); a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'statistics', a.suite); end
if isempty(a.compare_dir); a.compare_dir = fullfile(a.project_root, 'results', 'analysis', 'compare', a.suite); end
a.results_root = char(a.results_root); a.output_dir = char(a.output_dir); a.compare_dir = char(a.compare_dir);
a.figures = lower(cellstr(a.figures));
a.formats = lower(cellstr(a.formats));
a.yscale = lower(char(a.yscale));
bad = setdiff(a.figures, {'cd', 'box', 'violin', 'ranks'});
assert(isempty(bad), 'plot_statistics:args', 'unknown figure(s): %s', strjoin(bad, ', '));
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end

cmp = {'suite', a.suite, 'results_root', a.results_root, 'output_dir', a.compare_dir, ...
       'project_root', a.project_root, 'functions', a.functions, 'dimensions', a.dimensions, 'alpha', a.alpha, 'correction', a.correction};
if ~isempty(a.optimizers); cmp = [cmp, {'optimizers', a.optimizers}]; end
if ~isempty(a.labels);     cmp = [cmp, {'labels', a.labels}]; end
if ~isempty(a.proposed);   cmp = [cmp, {'proposed', a.proposed}]; end
rep = compare_algorithms(cmp{:});
opts = rep.optimizers;
labels = cellfun(@(r) r, {rep.settings.label}, 'UniformOutput', false);
native = any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'}));
known_optimum = ~native;
style = palette(numel(opts));

report = struct('figures', {{}}, 'optimizers', {opts});
groups = rep.groups;
if isfield(rep, 'overall_friedman')
    groups(end + 1).tag = 'overall';
    groups(end).friedman = rep.overall_friedman;
    groups(end).posthoc = rep.overall_posthoc;
end
n_cells = cellfun(@numel, {rep.groups.functions});

if any(strcmp(a.figures, 'cd'))
    for g = 1:numel(groups)
        ph = groups(g).posthoc;
        if isempty(ph); continue; end
        if strcmp(groups(g).tag, 'overall'); n = sum(n_cells); else; n = n_cells(g); end
        report.figures = [report.figures, cd_diagram(groups(g).friedman.mean_rank, labels, ...
            ph(1).cd, a, groups(g).tag, n)];
    end
end

if any(strcmp(a.figures, 'box')) || any(strcmp(a.figures, 'violin'))
    runs = cell(1, numel(opts));
    for i = 1:numel(opts)
        runs{i} = load_runs(fullfile(a.results_root, opts{i}, a.suite, 'summary', 'per_run.csv'), known_optimum);
    end
    for kind = intersect({'box', 'violin'}, a.figures, 'stable')
        for g = 1:numel(rep.groups)
            cells = group_cells(rep.groups(g), runs{1}, native);
            for c = 1:size(cells, 1)
                fig = new_figure(a.visible, [100 100 620 440]);
                ax = axes(fig);
                draw_spread(ax, runs, cells(c, :), labels, style, kind{1}, a, known_optimum, true);
                ttl = sprintf('%s  F%d  (D = %d)', suite_title(a.suite), cells(c, 1), cells(c, 2));
                key = sprintf('%d|%d', cells(c, 1), cells(c, 2));
                if strcmp(kind{1}, 'violin') && any(cellfun(@(m) numel(m(key)) < 20, runs))
                    ttl = [ttl '  [box: fewer than 20 runs for a violin]'];
                end
                title(ax, ttl, 'FontWeight', 'normal');
                base = fullfile(a.output_dir, sprintf('%s_%s_F%d_D%d', kind{1}, a.suite, cells(c, 1), cells(c, 2)));
                report.figures = [report.figures, save_figure(fig, base, a.formats)];
                close(fig);
            end
            report.figures = [report.figures, spread_overview(runs, cells, labels, style, kind{1}, a, ...
                known_optimum, rep.groups(g).tag)];
        end
    end
end

if any(strcmp(a.figures, 'ranks'))
    report.figures = [report.figures, rank_charts(groups, labels, style, a)];
end
fprintf('plot_statistics: wrote %d file(s) to %s\n', numel(report.figures), a.output_dir);
end

% ---- critical difference diagram -------------------------------------------

function paths = cd_diagram(mr, labels, cd, a, tag, n)
% Demsar-style CD diagram: rank axis 1..k on top, each optimizer joined to
% its label (best half left, rest right), thick bars for groups whose mean
% ranks differ by less than CD.
k = numel(mr);
[r, o] = sort(mr(:)');
names = labels(o);
half = ceil(k / 2);
h_lab = 0.42 * max(half, k - half) + 0.9;
W = 760;   % figure width in pixels
fig = new_figure(a.visible, [100 100 W, 170 + 40 * max(half, k - half)]);
ax = axes(fig, 'Position', [0.01 0.02 0.98 0.86]);
hold(ax, 'on'); axis(ax, 'off');
lo = 1; hi = k;
% Side margin L (rank units) wide enough for the longest label: a label of
% n characters at about 7.5 px each must fit in L - 0.35 rank units, where
% one rank unit is 0.98*W/(k - 1 + 2L) px.
nch = max(cellfun(@numel, names)) + 8;
cpx = 7.5 * nch / (0.98 * W);
L = (0.35 + cpx * (k - 1)) / max(1 - 2 * cpx, 0.2);
xlim(ax, [lo - L, hi + L]);
ylim(ax, [-h_lab - 0.3, 1.2]);
% Axis with ticks.
plot(ax, [lo hi], [0 0], 'k-', 'LineWidth', 1);
for t = lo:hi
    plot(ax, [t t], [0 0.1], 'k-', 'LineWidth', 1);
    text(ax, t, 0.22, sprintf('%d', t), 'HorizontalAlignment', 'center', 'FontSize', 10);
end
for t = lo + 0.5:1:hi - 0.5
    plot(ax, [t t], [0 0.05], 'k-', 'LineWidth', 0.6);
end
% CD bar.
plot(ax, [lo, lo + cd], [0.78 0.78], 'k-', 'LineWidth', 1.6);
plot(ax, [lo lo], [0.72 0.84], 'k-', 'LineWidth', 1.2);
plot(ax, [lo + cd, lo + cd], [0.72 0.84], 'k-', 'LineWidth', 1.2);
text(ax, lo + cd / 2, 0.98, sprintf('CD = %.2f', cd), 'HorizontalAlignment', 'center', 'FontSize', 10);
% Optimizers.
for i = 1:k
    if i <= half
        yl = -0.42 * i - 0.35;
        plot(ax, [r(i) r(i) lo - 0.25], [0 yl yl], 'k-', 'LineWidth', 0.9);
        text(ax, lo - 0.32, yl, sprintf('%s (%.2f)', names{i}, r(i)), 'HorizontalAlignment', 'right', ...
             'FontSize', 10, 'Interpreter', 'none');
    else
        yl = -0.42 * (k - i + 1) - 0.35;
        plot(ax, [r(i) r(i) hi + 0.25], [0 yl yl], 'k-', 'LineWidth', 0.9);
        text(ax, hi + 0.32, yl, sprintf('(%.2f) %s', r(i), names{i}), 'HorizontalAlignment', 'left', ...
             'FontSize', 10, 'Interpreter', 'none');
    end
end
% Cliques: maximal runs of optimizers within CD of each other.
cliques = zeros(0, 2);
for i = 1:k
    j = find(r - r(i) < cd, 1, 'last');
    if j > i && (isempty(cliques) || j > cliques(end, 2))
        cliques(end + 1, :) = [i j]; %#ok<AGROW>
    end
end
for c = 1:size(cliques, 1)
    y = -0.12 - 0.09 * (c - 1);
    plot(ax, [r(cliques(c, 1)) - 0.05, r(cliques(c, 2)) + 0.05], [y y], 'k-', 'LineWidth', 3);
end
title(ax, sprintf('%s  %s  (Nemenyi, alpha = %g, N = %d)', suite_title(a.suite), group_text(tag), a.alpha, n), ...
      'FontWeight', 'normal', 'Visible', 'on');
paths = save_figure(fig, fullfile(a.output_dir, sprintf('cd_%s_%s', a.suite, tag)), a.formats);
close(fig);
end

% ---- box and violin plots ------------------------------------------------------

function draw_spread(ax, runs, cel, labels, style, kind, a, known_optimum, with_labels)
% Box or violin plot of one (function, dimension) cell with every run shown
% as a dot. Log axis ('auto') only when the values span at least a decade.
% A violin needs enough runs to estimate a density: with fewer than 20 runs
% the violin figure draws a box instead (and says so in its title).
hold(ax, 'on'); box(ax, 'off');
key = sprintf('%d|%d', cel(1), cel(2));
vals = cell2mat(cellfun(@(m) m(key), runs(:), 'UniformOutput', false));
pos = vals(vals > 0);
spans_decade = ~isempty(pos) && max(pos) / min(pos) >= 10;
use_log = strcmp(a.yscale, 'log') || (strcmp(a.yscale, 'auto') && spans_decade && ...
          (all(vals > 0) || (known_optimum && all(vals >= 0))));
for i = 1:numel(runs)
    v = runs{i}(key);
    if use_log; v = max(v, a.error_floor); end
    t = v(:);
    if use_log; t = log10(t); end
    if strcmp(kind, 'box') || numel(t) < 20
        box_shape(ax, i, t, style(i, :), use_log);
    else
        violin_shape(ax, i, t, style(i, :), use_log);
    end
    run_dots(ax, i, t, style(i, :), use_log, kind);
end
set(ax, 'XTick', 1:numel(runs), 'XTickLabel', labels, 'TickLabelInterpreter', 'none', ...
        'XGrid', 'off', 'YGrid', 'on', 'YMinorGrid', 'off', 'XMinorGrid', 'off', ...
        'GridAlpha', 0.12, 'TickDir', 'out', 'LineWidth', 0.8);
xlim(ax, [0.4, numel(runs) + 0.6]);
if use_log
    set(ax, 'YScale', 'log', 'YMinorTick', 'off');
end
% A little room above and below the data.
yl = [min(vals), max(vals)];
if use_log
    yl = log10(max(yl, a.error_floor)); pad = 0.06 * max(diff(yl), 0.1);
    ylim(ax, 10 .^ [yl(1) - pad, yl(2) + pad]);
else
    pad = 0.06 * max(diff(yl), eps(max(abs(yl))) * 100);
    ylim(ax, [yl(1) - pad, yl(2) + pad]);
end
if with_labels
    if known_optimum; s = 'Final error  f(x) - f(x*)'; else; s = 'Final objective value  f(x)'; end
    if use_log; s = [s '  (log scale)']; end
    ylabel(ax, s);
end
end

function box_shape(ax, x, t, color, use_log)
% Box from the 25th to the 75th percentile, median line, whiskers to the
% most extreme runs within 1.5 IQR (Tukey). Values t are log10 when use_log.
q = quantile_local(t, [0.25 0.5 0.75]);
iqr_t = q(3) - q(1);
lo = min(t(t >= q(1) - 1.5 * iqr_t)); hi = max(t(t <= q(3) + 1.5 * iqr_t));
w = 0.26;
Y = @(y) back(y, use_log);
patch(ax, x + [-w w w -w], Y([q(1) q(1) q(3) q(3)]), color, 'FaceAlpha', 0.18, ...
      'EdgeColor', color, 'LineWidth', 1.1);
plot(ax, x + [-w w], Y([q(2) q(2)]), '-', 'Color', color * 0.55, 'LineWidth', 2);
plot(ax, [x x], Y([q(3) hi]), '-', 'Color', color, 'LineWidth', 1);
plot(ax, [x x], Y([lo q(1)]), '-', 'Color', color, 'LineWidth', 1);
plot(ax, x + [-w w] / 2, Y([hi hi]), '-', 'Color', color, 'LineWidth', 1);
plot(ax, x + [-w w] / 2, Y([lo lo]), '-', 'Color', color, 'LineWidth', 1);
end

function violin_shape(ax, x, t, color, use_log)
% Gaussian kernel density (Silverman bandwidth) drawn only over the observed
% range of the runs (no tails past the data), with a slim 25-75% box and a
% median line inside. Values t are log10 when use_log.
q = quantile_local(t, [0.25 0.5 0.75]);
Y = @(y) back(y, use_log);
if max(t) - min(t) <= eps(max(abs(t))) * 100 || numel(t) < 3
    plot(ax, x + [-0.2 0.2], Y([q(2) q(2)]), '-', 'Color', color, 'LineWidth', 2);   % all runs equal
    return;
end
s = std(t);
iq = q(3) - q(1);
spread = min(s, iq / 1.34); if ~(spread > 0); spread = s; end
bw = 0.9 * spread * numel(t) ^ (-1 / 5);
grid_t = linspace(min(t), max(t), 200)';
dens = mean(exp(-0.5 * ((grid_t - t(:)') / bw) .^ 2), 2);
w = 0.34 * dens / max(dens);
patch(ax, [x - w; flipud(x + w)], Y([grid_t; flipud(grid_t)]), color, 'FaceAlpha', 0.18, ...
      'EdgeColor', color, 'LineWidth', 1.1);
bw2 = 0.045;
patch(ax, x + [-bw2 bw2 bw2 -bw2], Y([q(1) q(1) q(3) q(3)]), color * 0.55, 'EdgeColor', 'none');
plot(ax, x + [-bw2 bw2] * 1.6, Y([q(2) q(2)]), '-', 'Color', 'w', 'LineWidth', 2);
end

function run_dots(ax, x, t, color, use_log, kind)
% Every run as a small dot, spread sideways by a fixed (not random) offset
% so the figure is reproducible.
n = numel(t);
if n > 300; return; end
off = mod((0:n - 1)' * 0.6180339887, 1) - 0.5;   % golden-ratio spacing in [-0.5, 0.5)
if strcmp(kind, 'box'); half = 0.18; else; half = 0.10; end
scatter(ax, x + 0.9 * half * 2 * off, back(t, use_log), 9, color * 0.6, 'filled', ...
        'MarkerFaceAlpha', 0.55, 'MarkerEdgeColor', 'none');
end

function y = back(t, use_log)
% Values on the plotted axis (t are log10 values when use_log).
if use_log; y = 10 .^ t; else; y = t; end
end

function q = quantile_local(v, pr)
% Quantiles with linear interpolation (the toolbox-free equivalent of
% quantile(v, p) for a vector).
v = sort(v(:));
n = numel(v);
pos = 1 + (n - 1) * pr(:)';
lo = floor(pos); hi = min(lo + 1, n);
q = v(lo)' + (pos - lo) .* (v(hi)' - v(lo)');
end

function paths = spread_overview(runs, cells, labels, style, kind, a, known_optimum, tag)
n = size(cells, 1);
if n == 0; paths = {}; return; end
ncol = min(n, 5); nrow = ceil(n / ncol);
fig = new_figure(a.visible, [50 50 300 * ncol, 240 * nrow + 60]);
t = tiledlayout(fig, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');
for c = 1:n
    ax = nexttile(t);
    draw_spread(ax, runs, cells(c, :), labels, style, kind, a, known_optimum, false);
    title(ax, sprintf('F%d (D = %d)', cells(c, 1), cells(c, 2)), 'FontWeight', 'normal');
    set(ax, 'FontSize', 7);
end
title(t, sprintf('%s  %s  (%s plots of the final values)', suite_title(a.suite), group_text(tag), kind));
paths = save_figure(fig, fullfile(a.output_dir, sprintf('%s_%s_%s_overview', kind, a.suite, tag)), a.formats);
close(fig);
end

function cells = group_cells(group, runs1, native)
% (function, dimension) pairs of a compare_algorithms group.
if native
    k = keys(runs1);
    all_cells = cell2mat(cellfun(@(s) sscanf(s, '%d|%d')', k(:), 'UniformOutput', false));
    cells = all_cells(ismember(all_cells(:, 1), group.functions), :);
    cells = sortrows(cells, 1);
else
    d = sscanf(group.tag, 'D%d');
    cells = [group.functions(:), repmat(d, numel(group.functions), 1)];
end
end

% ---- rank charts ---------------------------------------------------------------

function paths = rank_charts(groups, labels, style, a)
tags = {groups.tag};
R = cell2mat(arrayfun(@(g) g.friedman.mean_rank(:)', groups(:), 'UniformOutput', false));   % groups x k
k = size(R, 2);
fig = new_figure(a.visible, [100 100 max(620, 130 * numel(tags) + 260), 440]);
ax = axes(fig); hold(ax, 'on'); box(ax, 'off');
% Same look as the box plots: light fill, coloured edge, the rank on top.
b = bar(ax, R, 'grouped', 'BarWidth', 0.82);
for i = 1:k
    b(i).FaceColor = style(i, :); b(i).FaceAlpha = 0.25;
    b(i).EdgeColor = style(i, :); b(i).LineWidth = 1.2; b(i).DisplayName = labels{i};
    text(ax, b(i).XEndPoints, b(i).YEndPoints + 0.06 * k / 5, compose('%.2f', b(i).YData), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8, ...
         'Color', style(i, :) * 0.7);
end
set(ax, 'XTick', 1:numel(tags), 'XTickLabel', cellfun(@group_text, tags, 'UniformOutput', false), ...
        'XGrid', 'off', 'YGrid', 'on', 'GridAlpha', 0.12, 'TickDir', 'out', 'LineWidth', 0.8);
ylabel(ax, 'Friedman mean rank (lower is better)');
ylim(ax, [0, k + 0.6]);
legend(ax, 'Location', 'northoutside', 'Orientation', 'horizontal', 'Interpreter', 'none', 'Box', 'off');
title(ax, sprintf('%s  Friedman mean ranks', suite_title(a.suite)), 'FontWeight', 'normal');
paths = save_figure(fig, fullfile(a.output_dir, sprintf('ranks_%s_bars', a.suite)), a.formats);
close(fig);
spokes = ~strcmp(tags, 'overall');
if nnz(spokes) >= 3
    th = linspace(0, 2 * pi, nnz(spokes) + 1);
    fig = new_figure(a.visible, [100 100 560 520]);
    pax = polaraxes(fig); hold(pax, 'on');
    Rs = R(spokes, :);
    for i = 1:k
        polarplot(pax, th, [Rs(:, i); Rs(1, i)], '-o', 'Color', style(i, :), 'LineWidth', 1.5, ...
                  'MarkerFaceColor', style(i, :), 'DisplayName', labels{i});
    end
    pax.ThetaTick = rad2deg(th(1:end - 1));
    pax.ThetaTickLabel = cellfun(@group_text, tags(spokes), 'UniformOutput', false);
    pax.RLim = [0 k];
    legend(pax, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Interpreter', 'none');
    title(pax, sprintf('%s  Friedman mean rank per dimension (closer to the centre is better)', ...
          suite_title(a.suite)), 'FontWeight', 'normal');
    paths = [paths, save_figure(fig, fullfile(a.output_dir, sprintf('ranks_%s_radar', a.suite)), a.formats)];
    close(fig);
end
end

% ---- helpers ---------------------------------------------------------------------

function s = group_text(tag)
switch tag
    case 'all';     s = 'all problems';
    case 'overall'; s = 'overall';
    otherwise;      s = tag;
end
end

function style = palette(n)
style = lines(max(n, 7));
style = style(1:n, :);
end

function fig = new_figure(visible, position)
% White figure with the light theme (theme exists from R2025a).
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

function m = load_runs(path, known_optimum)
% Map 'f|D' -> per-run values (error, or best_fitness without known optima);
% a run id that appears more than once keeps its last row.
assert(isfile(path), 'plot_statistics:noResults', 'missing %s', path);
T = readtable(path, 'VariableNamingRule', 'preserve', 'Delimiter', ',');
if known_optimum; vcol = 'error'; else; vcol = 'best_fitness'; end
F = T.('function'); D = T.dimension; R = T.run; V = T.(vcol);
[~, last] = unique([F D R], 'rows', 'last');
F = F(last); D = D(last); V = V(last);
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
[cells, ~, g] = unique([F D], 'rows');
for c = 1:size(cells, 1)
    m(sprintf('%d|%d', cells(c, 1), cells(c, 2))) = V(g == c);
end
end

function s = suite_title(suite)
switch suite
    case 'cec2013lsgo'; s = 'CEC2013-LSGO';
    otherwise;          s = upper(suite);
end
end
