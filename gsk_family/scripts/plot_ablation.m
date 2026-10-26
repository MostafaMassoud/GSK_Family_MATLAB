function report = plot_ablation(varargin)
%PLOT_ABLATION Ablation study: the full variant against versions with one component switched off.
%
%   plot_ablation('suite','cec2017', 'base','my-gsk', 'switches',{'use_step_a','use_step_b'})
%
% First make the base read one on/off switch per new component, e.g.
%   use_step_a = local_option(options, 'use_step_a', true);
%   if use_step_a, ... end
% then write the ablated aliases with make_study_aliases('ablation', base,
% switches) and run the base and the aliases (a launcher with the printed
% optimizers line). plot_ablation compares them with compare_algorithms, with
% the full base as the proposed optimizer, and writes:
%   ablation_<suite>_<base>.csv/.tex   one row per version: the component
%                       switched off, the overall Friedman mean rank (1 =
%                       best), and the +/=/- counts of the full version
%                       against it (rank-sum per function, all dimensions)
%                       with the signed-rank p-value per dimension
%   ablation_<suite>_<base>.*          bar chart of the mean ranks, full
%                       version first; the label of each ablated bar shows
%                       its +/=/- counts
% A component helps when switching it off makes the mean rank worse and the
% full version wins more functions than it loses.
%
% Options: suite, base, switches (required); labels (display names: full
% version first, then one per switch; default "Full" and "without <switch>");
% functions, dimensions; formats ({'png','pdf'}); results_root
% (results/_run_all); output_dir (results/analysis/ablation/<suite>/<base>);
% project_root (pwd); visible (false).
%
% Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
% Cairo University: this framework code only; each algorithm belongs to its
% original authors. Licensing: gsk_family/LICENSES.md. Cite gsk_family/CITATION.cff.

p = inputParser;
p.addParameter('suite', '', @(x) ischar(x) || isstring(x));
p.addParameter('base', '', @(x) ischar(x) || isstring(x));
p.addParameter('switches', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
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
sw = cellstr(a.switches);
assert(~isempty(a.suite) && ~isempty(a.base) && ~isempty(sw) && ~isempty(sw{1}), 'plot_ablation:args', ...
       'suite, base and switches are required');
a.project_root = char(a.project_root);
if isempty(a.results_root); a.results_root = fullfile(a.project_root, 'results', '_run_all'); end
if isempty(a.output_dir)
    a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'ablation', a.suite, a.base);
end
a.results_root = char(a.results_root); a.output_dir = char(a.output_dir);
a.formats = lower(cellstr(a.formats));
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end

names = [{a.base}, make_study_aliases('ablation', a.base, sw, 'dry_run', true)];
if isempty(a.labels)
    labels = [{'Full'}, cellfun(@(s) ['without ' s], sw, 'UniformOutput', false)];
else
    labels = cellstr(a.labels);
    assert(numel(labels) == numel(names), 'plot_ablation:args', 'labels: the full version, then one per switch');
end
missing = names(cellfun(@(n) ~exist(fullfile(a.results_root, n, a.suite, 'summary', 'per_run.csv'), 'file'), names));
assert(isempty(missing), 'plot_ablation:noResults', 'no results yet for: %s', strjoin(missing, ', '));
rep = compare_algorithms('suite', a.suite, 'optimizers', names, 'labels', labels, 'proposed', a.base, ...
    'results_root', a.results_root, 'output_dir', fullfile(a.output_dir, 'compare'), ...
    'project_root', a.project_root, 'functions', a.functions, 'dimensions', a.dimensions);
if isfield(rep, 'overall_friedman'); mr = rep.overall_friedman.mean_rank; else; mr = rep.groups(1).friedman.mean_rank; end
k = numel(names);
wtl = zeros(k, 3);
pvals = nan(k, numel(rep.groups));
for g = 1:numel(rep.groups)
    for w = rep.groups(g).wilcoxon
        i = find(strcmp(names, w.competitor), 1);
        wtl(i, :) = wtl(i, :) + w.wtl;
        pvals(i, g) = w.p;
    end
end
tags = {rep.groups.tag};

fid = fopen(fullfile(a.output_dir, sprintf('ablation_%s_%s.csv', a.suite, a.base)), 'w');
c1 = onCleanup(@() fclose(fid));
fprintf(fid, 'version,label,switched_off,mean_rank,full_wins,ties,full_losses%s\n', ...
        sprintf(',signed_rank_p_%s', tags{:}));
for i = 1:k
    off = ternary(i == 1, '', sw{max(i - 1, 1)});
    fprintf(fid, '%s,%s,%s,%.4f,%d,%d,%d%s\n', names{i}, labels{i}, off, mr(i), wtl(i, :), ...
            sprintf(',%.6g', pvals(i, :)));
end
fid2 = fopen(fullfile(a.output_dir, sprintf('ablation_%s_%s.tex', a.suite, a.base)), 'w');
c2 = onCleanup(@() fclose(fid2));
fprintf(fid2, ['%% %s ablation of %s: Friedman mean rank over all functions and dimensions (1 = best); ' ...
               '+/=/-: full version better / no significant difference / worse (rank-sum per function).\n'], ...
        suite_title(a.suite), a.base);
fprintf(fid2, '\\begin{tabular}{llrc%s}\n\\hline\n', repmat('r', 1, numel(tags)));
fprintf(fid2, 'Version & Switched off & Mean rank & +/=/-%s \\\\\n\\hline\n', ...
        sprintf(' & $p$ (%s)', tags{:}));
for i = 1:k
    off = ternary(i == 1, '--', strrep(sw{max(i - 1, 1)}, '_', '\_'));
    if i == 1
        fprintf(fid2, '%s & %s & %.2f & --%s \\\\\n', tex(labels{i}), off, mr(i), repmat(' & --', 1, numel(tags)));
    else
        fprintf(fid2, '%s & %s & %.2f & %d/%d/%d%s \\\\\n', tex(labels{i}), off, mr(i), wtl(i, :), ...
                sprintf(' & %.3g', pvals(i, :)));
    end
end
fprintf(fid2, '\\hline\n\\end{tabular}\n');

% Bar chart in the style of the rank chart of plot_statistics.
fig = new_figure(a.visible, [100 100 max(560, 110 * k + 200), 420]);
ax = axes(fig); hold(ax, 'on'); box(ax, 'off');
col = lines(max(k, 7));
for i = 1:k
    bar(ax, i, mr(i), 0.6, 'FaceColor', col(i, :), 'FaceAlpha', 0.25, 'EdgeColor', col(i, :), 'LineWidth', 1.2);
    text(ax, i, mr(i) + 0.05 * k / 4, sprintf('%.2f', mr(i)), 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom', 'FontSize', 9, 'Color', col(i, :) * 0.7);
end
xt = strrep(labels, '_', '\_');   % TeX tick labels: keep underscores
for i = 2:k; xt{i} = sprintf('%s\\newline(%d/%d/%d)', xt{i}, wtl(i, :)); end
set(ax, 'XTick', 1:k, 'XTickLabel', xt, 'TickLabelInterpreter', 'tex', 'XGrid', 'off', 'YGrid', 'on', ...
        'GridAlpha', 0.12, 'TickDir', 'out', 'LineWidth', 0.8);
ylim(ax, [0, k + 0.5]); xlim(ax, [0.4, k + 0.6]);
ylabel(ax, 'Friedman mean rank (lower is better)');
title(ax, sprintf('%s  ablation of %s  (+/=/-: full version vs each)', suite_title(a.suite), display_name(a.base)), ...
      'FontWeight', 'normal', 'Interpreter', 'none');
report = struct('names', {names}, 'mean_rank', mr, 'wtl', wtl, 'signed_rank_p', pvals, ...
    'figures', {save_figure(fig, fullfile(a.output_dir, sprintf('ablation_%s_%s', a.suite, a.base)), a.formats)});
close(fig);
fprintf('plot_ablation: wrote ablation_%s_%s.csv/.tex and the chart to %s\n', a.suite, a.base, a.output_dir);
end

function s = display_name(id)
switch id
    case 'egsk'; s = 'eGSK';
    otherwise;   s = upper(id);
end
end

function s = tex(s)
s = strrep(strrep(s, '_', '\_'), '&', '\&');
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
