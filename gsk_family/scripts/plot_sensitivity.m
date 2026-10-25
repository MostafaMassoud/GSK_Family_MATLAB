function report = plot_sensitivity(varargin)
%PLOT_SENSITIVITY Parameter sensitivity of one optimizer: Friedman ranks over a grid of settings.
%
%   plot_sensitivity('suite','cec2017', 'base','gsk', 'spec',{'kf',[0.3 0.5 0.7]})
%   plot_sensitivity('suite','cec2017', 'base','gsk', 'spec',{'kf',[0.3 0.5 0.7],'kr',[0.8 0.9 1]})
%
% First write the grid of aliases with make_study_aliases('sensitivity',
% base, spec) and run them (a launcher with optimizers = the printed names).
% plot_sensitivity then compares the grid points with compare_algorithms
% (Friedman mean ranks over the functions of each dimension and overall;
% 1 = best) and draws:
%   one parameter   sensitivity_<suite>_<base>.*: mean rank against the
%                   parameter value, one line per dimension and a thick one
%                   for all dimensions together
%   two parameters  sensitivity_<suite>_<base>.*: heatmap of the overall
%                   mean rank, the value in every cell, the best cell framed;
%                   plus one heatmap per dimension (..._<tag>.*)
% and writes sensitivity_<suite>_<base>.csv (one row per grid point and
% group: the parameter values and the mean rank). The compare_algorithms
% tables of the grid go to <output_dir>/compare.
%
% Options: suite, base, spec (required; the same base and spec as in
% make_study_aliases); functions, dimensions; formats ({'png','pdf'});
% results_root (results/_run_all); output_dir
% (results/analysis/sensitivity/<suite>/<base>); project_root (pwd);
% visible (false).

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('base', '', @(x) ischar(x) || isstring(x));
p.addParameter('spec', {}, @iscell);
p.addParameter('functions', [], @isnumeric);
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('formats', {'png', 'pdf'}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('results_root', '', @(x) ischar(x) || isstring(x));
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite)); a.base = lower(char(a.base));
assert(~isempty(a.suite) && ~isempty(a.base) && any(numel(a.spec) == [2 4]), 'plot_sensitivity:args', ...
       'suite, base and spec ({param, values} or {p1, v1, p2, v2}) are required');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
if isempty(a.output_dir)
    a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'sensitivity', a.suite, a.base);
end
a.results_root = char(a.results_root); a.output_dir = char(a.output_dir);
a.formats = lower(cellstr(a.formats));
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end

names = make_study_aliases('sensitivity', a.base, a.spec, 'dry_run', true);
missing = names(cellfun(@(n) ~exist(fullfile(a.results_root, n, a.suite, 'summary', 'per_run.csv'), 'file'), names));
assert(isempty(missing), 'plot_sensitivity:noResults', 'no results yet for: %s', strjoin(missing, ', '));
rep = compare_algorithms('suite', a.suite, 'optimizers', names, 'results_root', a.results_root, ...
    'output_dir', fullfile(a.output_dir, 'compare'), 'project_root', a.project_root, ...
    'functions', a.functions, 'dimensions', a.dimensions);
tags = {rep.groups.tag};
R = cell2mat(arrayfun(@(g) g.friedman.mean_rank(:)', rep.groups(:), 'UniformOutput', false));   % groups x points
if isfield(rep, 'overall_friedman')
    tags{end + 1} = 'overall'; R(end + 1, :) = rep.overall_friedman.mean_rank(:)';
end
p1 = lower(char(a.spec{1})); v1 = a.spec{2}(:)';
two = numel(a.spec) == 4;
if two; p2 = lower(char(a.spec{3})); v2 = a.spec{4}(:)'; end

% CSV.
fid = fopen(fullfile(a.output_dir, sprintf('sensitivity_%s_%s.csv', a.suite, a.base)), 'w');
c1 = onCleanup(@() fclose(fid));
if two; fprintf(fid, 'group,%s,%s,alias,mean_rank\n', p1, p2); else; fprintf(fid, 'group,%s,alias,mean_rank\n', p1); end
for g = 1:numel(tags)
    for n = 1:numel(names)
        if two
            [i2, i1] = ind2sub([numel(v2), numel(v1)], n);
            fprintf(fid, '%s,%g,%g,%s,%.4f\n', tags{g}, v1(i1), v2(i2), names{n}, R(g, n));
        else
            fprintf(fid, '%s,%g,%s,%.4f\n', tags{g}, v1(n), names{n}, R(g, n));
        end
    end
end

report = struct('figures', {{}}, 'names', {names}, 'tags', {tags}, 'mean_rank', R);
k = numel(names);
if ~two
    fig = new_figure(a.visible, [100 100 640 440]);
    ax = axes(fig); hold(ax, 'on'); box(ax, 'off');
    col = lines(max(numel(tags), 7));
    for g = 1:numel(tags)
        if strcmp(tags{g}, 'overall')
            plot(ax, v1, R(g, :), '-o', 'Color', [0.15 0.15 0.15], 'LineWidth', 2.4, ...
                 'MarkerFaceColor', [0.15 0.15 0.15], 'DisplayName', 'all dimensions');
        else
            plot(ax, v1, R(g, :), '-o', 'Color', col(g, :), 'LineWidth', 1.3, 'MarkerFaceColor', 'w', ...
                 'DisplayName', group_text(tags{g}));
        end
    end
    if all(v1 > 0) && max(v1) / min(v1) >= 10; set(ax, 'XScale', 'log'); end
    set(ax, 'XTick', v1, 'YGrid', 'on', 'XGrid', 'off', 'GridAlpha', 0.12, 'TickDir', 'out', 'LineWidth', 0.8);
    ylim(ax, [1 - 0.2, k + 0.2]);
    xlabel(ax, p1, 'Interpreter', 'none');
    ylabel(ax, 'Friedman mean rank (lower is better)');
    legend(ax, 'Location', 'best', 'Box', 'off');
    title(ax, sprintf('%s  %s: sensitivity to %s', suite_title(a.suite), upper(a.base), p1), ...
          'FontWeight', 'normal', 'Interpreter', 'none');
    report.figures = save_figure(fig, fullfile(a.output_dir, sprintf('sensitivity_%s_%s', a.suite, a.base)), a.formats);
    close(fig);
else
    for g = 1:numel(tags)
        H = reshape(R(g, :), numel(v2), numel(v1));   % rows p2, columns p1
        fig = new_figure(a.visible, [100 100 120 + 80 * numel(v1), 120 + 60 * numel(v2)]);
        ax = axes(fig);
        imagesc(ax, H); axis(ax, 'tight');
        colormap(ax, blues(256)); caxis(ax, [1 k]);
        cb = colorbar(ax); cb.Label.String = 'Friedman mean rank (lower is better)';
        set(ax, 'XTick', 1:numel(v1), 'XTickLabel', compose('%g', v1), 'YTick', 1:numel(v2), ...
                'YTickLabel', compose('%g', v2), 'YDir', 'normal', 'TickDir', 'out', 'TickLength', [0 0]);
        hold(ax, 'on');
        for r = 1:numel(v2)
            for c = 1:numel(v1)
                tc = ternary(H(r, c) < 1 + 0.55 * (k - 1), [0.1 0.1 0.1], [1 1 1]);
                text(ax, c, r, sprintf('%.2f', H(r, c)), 'HorizontalAlignment', 'center', 'Color', tc, 'FontSize', 9);
            end
        end
        [~, b] = min(H(:)); [br, bc] = ind2sub(size(H), b);
        rectangle(ax, 'Position', [bc - 0.5, br - 0.5, 1, 1], 'EdgeColor', [0.85 0.1 0.1], 'LineWidth', 2);
        xlabel(ax, p1, 'Interpreter', 'none'); ylabel(ax, p2, 'Interpreter', 'none');
        title(ax, sprintf('%s  %s  %s', suite_title(a.suite), upper(a.base), group_text(tags{g})), ...
              'FontWeight', 'normal', 'Interpreter', 'none');
        if strcmp(tags{g}, 'overall') || numel(tags) == 1
            base_name = sprintf('sensitivity_%s_%s', a.suite, a.base);
        else
            base_name = sprintf('sensitivity_%s_%s_%s', a.suite, a.base, tags{g});
        end
        report.figures = [report.figures, save_figure(fig, fullfile(a.output_dir, base_name), a.formats)];
        close(fig);
    end
end
fprintf('plot_sensitivity: wrote %d figure file(s) and sensitivity_%s_%s.csv to %s\n', ...
        numel(report.figures), a.suite, a.base, a.output_dir);
end

function c = blues(n)
% White (best, rank 1) to dark blue (worst): a light sequential map.
t = linspace(0, 1, n)';
c = [1 - 0.85 * t, 1 - 0.62 * t, 1 - 0.25 * t];
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
