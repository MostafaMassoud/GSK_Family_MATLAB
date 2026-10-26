function names = make_study_aliases(kind, base, spec, varargin)
%MAKE_STUDY_ALIASES Write the algorithms.ini aliases of a sensitivity or ablation study.
%
%   names = make_study_aliases('sensitivity', 'gsk', {'kf', [0.3 0.5 0.7]})
%   names = make_study_aliases('sensitivity', 'gsk', {'kf', [0.3 0.5 0.7], 'kr', [0.8 0.9 1]})
%   names = make_study_aliases('ablation', 'my-gsk', {'use_step_a', 'use_step_b'})
%
% 'sensitivity': one alias per value (one parameter) or per combination (two
% parameters) of base, named <base>-<param>-<value>[-<param>-<value>], e.g.
% gsk-kf-0p7-kr-0p8 ("p" for the decimal point, "m" for a minus sign; an
% underscore in a parameter name is dropped: np_init -> npinit).
% 'ablation': one alias per switch, <base>-no-<switch> (underscores become
% hyphens), with that switch = false and the others left at their default.
% The base's file must read each switch, e.g.
%   use_step_a = local_option(options, 'use_step_a', true);
%
% The aliases are appended to algorithms.ini (default: the repository root,
% one level above project_root) under a comment line that names the study;
% the file is created if missing. Nothing is written if one of the names is
% already an alias. Returns the alias names (for sensitivity: in grid order,
% the first parameter varying slowest), and prints the launcher line to run
% them. Run them, then plot_sensitivity or plot_ablation with the same base
% and spec.
%
% Options: 'file' (aliases file), 'project_root' (default pwd, the gsk_family
% folder), 'extra' (cell of name-value settings added to every alias, e.g.
% {'np_init', 50}), 'dry_run' (true: only return the names, write nothing).
%
% Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
% Cairo University. GPL-3.0-or-later; see gsk_family/LICENSES.md and cite
% gsk_family/CITATION.cff.

p = inputParser;
p.addRequired('kind', @(x) any(strcmpi(char(x), {'sensitivity', 'ablation'})));
p.addRequired('base', @(x) ischar(x) || isstring(x));
p.addRequired('spec', @iscell);
p.addParameter('file', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.addParameter('extra', {}, @iscell);
p.addParameter('dry_run', false, @(x) islogical(x) || isnumeric(x));
p.parse(kind, base, spec, varargin{:});
a = p.Results;
kind = lower(char(a.kind));
base = lower(strtrim(char(a.base)));
file = char(a.file);
if isempty(file)
    file = fullfile(fileparts(regexprep(char(a.project_root), '[\\/]+$', '')), 'algorithms.ini');
end
[names, settings, title_text] = study_aliases(kind, base, a.spec);
if logical(a.dry_run); return; end   % names only (used by plot_sensitivity and plot_ablation)
extra = a.extra;
for k = 1:2:numel(extra)
    for n = 1:numel(settings)
        settings{n}{end + 1} = {lower(char(extra{k})), extra{k + 1}};
    end
end

addpath(fullfile(char(a.project_root), 'src', 'runners'));
existing = read_algorithm_aliases(file);
clash = names(cellfun(@(n) isKey(existing, n), names));
assert(isempty(clash), 'make_study_aliases:exists', ...
       'already in %s (nothing written): %s', file, strjoin(clash, ', '));

lines = {'', sprintf('; ---- %s (make_study_aliases, %s) ----', title_text, datestr(now, 'yyyy-mm-dd'))};
for n = 1:numel(names)
    lines{end + 1} = sprintf('[%s]', names{n}); %#ok<AGROW>
    lines{end + 1} = sprintf('base = %s', base); %#ok<AGROW>
    for s = 1:numel(settings{n})
        lines{end + 1} = sprintf('%s = %s', settings{n}{s}{1}, value_text(settings{n}{s}{2})); %#ok<AGROW>
    end
end
fid = fopen(file, 'a');
assert(fid > 0, 'make_study_aliases:io', 'cannot write %s', file);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
read_algorithm_aliases(file);   % the file must still read cleanly
fprintf('make_study_aliases: added %d alias(es) to %s\n', numel(names), file);
fprintf('  run them, e.g. in run_all_cec2017.m:\n  optimizers = {''%s'', %s};\n', base, ...
        strjoin(cellfun(@(n) ['''' n ''''], names, 'UniformOutput', false), ', '));
end

function [names, settings, title_text] = study_aliases(kind, base, spec)
% Names and settings ({{name, value}, ...} per alias) of the study.
names = {}; settings = {};
if strcmp(kind, 'ablation')
    sw = cellstr(spec);
    for k = 1:numel(sw)
        names{end + 1} = sprintf('%s-no-%s', base, strrep(lower(sw{k}), '_', '-')); %#ok<AGROW>
        settings{end + 1} = {{lower(sw{k}), false}}; %#ok<AGROW>
    end
    title_text = sprintf('ablation study of %s: %s', base, strjoin(sw, ', '));
    return;
end
assert(any(numel(spec) == [2 4]), 'make_study_aliases:args', ...
       'sensitivity spec is {param, values} or {param1, values1, param2, values2}');
p1 = lower(char(spec{1})); v1 = spec{2};
if numel(spec) == 2
    for x = v1(:)'
        names{end + 1} = sprintf('%s-%s-%s', base, pname(p1), vtext(x)); %#ok<AGROW>
        settings{end + 1} = {{p1, x}}; %#ok<AGROW>
    end
    title_text = sprintf('sensitivity study of %s: %s', base, p1);
else
    p2 = lower(char(spec{3})); v2 = spec{4};
    for x = v1(:)'
        for y = v2(:)'
            names{end + 1} = sprintf('%s-%s-%s-%s-%s', base, pname(p1), vtext(x), pname(p2), vtext(y)); %#ok<AGROW>
            settings{end + 1} = {{p1, x}, {p2, y}}; %#ok<AGROW>
        end
    end
    title_text = sprintf('sensitivity study of %s: %s x %s', base, p1, p2);
end
end

function s = pname(p)
s = strrep(p, '_', '');
end

function s = vtext(x)
s = sprintf('%g', x);
s = strrep(strrep(strrep(s, '.', 'p'), '-', 'm'), '+', '');
end

function s = value_text(v)
if islogical(v)
    if v; s = 'true'; else; s = 'false'; end
elseif isscalar(v)
    s = sprintf('%.15g', v);
else
    s = ['[' strjoin(arrayfun(@(x) sprintf('%.15g', x), v, 'UniformOutput', false), ' ') ']'];
end
end
