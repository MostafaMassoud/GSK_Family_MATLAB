function aliases = read_algorithm_aliases(path)
%READ_ALGORITHM_ALIASES Read the algorithm aliases of an algorithms.ini file.
%
%   aliases = read_algorithm_aliases(path)
%
% Returns a containers.Map from alias name to a struct with fields
%   name      the alias, e.g. 'gsk-np100'
%   base      the optimizer whose code it runs, e.g. 'gsk'
%   settings  struct of the other settings, e.g. struct('np_init', 100)
%   text      the settings as one canonical line, e.g. 'np_init = 100'
%             (sorted by name; used to label results and to detect a change)
%   line      line number of the [name] header in the file
% A missing file gives an empty map.
%
% File format (see algorithms.ini in the repository root):
%   ; comment            (also # comment, and after a value: kf = 0.7 ; note)
%   [gsk-np100]          an alias: lower-case letters, digits and hyphens
%   base    = gsk        required: the optimizer it runs
%   np_init = 100        any other setting of that optimizer
% Values: a number (0.7, 1e-3, 100), a list ([0.3 0.5 0.7] or [0.3, 0.5]), a
% range (0.2:0.1:0.8 or 8:30), true or false. Nothing in the file is
% evaluated as MATLAB code. Errors (read_algorithm_aliases:file) name the
% file and the line.
%
% Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud (ORCID 0009-0003-8415-2158),
% Cairo University. GPL-3.0-or-later; see gsk_family/LICENSES.md and cite
% gsk_family/CITATION.cff.

aliases = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~isfile(path)
    return;
end
lines = regexp(fileread(path), '\r?\n', 'split');
cur = '';
for n = 1:numel(lines)
    raw = lines{n};
    s = strtrim(regexprep(raw, '\s[;#].*$', ''));   % comment after a value
    if isempty(s) || any(s(1) == ';#'); continue; end
    hdr = regexp(s, '^\[\s*([^\]]*?)\s*\]$', 'tokens', 'once');
    if ~isempty(hdr)
        name = lower(hdr{1});
        if isempty(regexp(name, '^[a-z][a-z0-9-]*[a-z0-9]$', 'once'))
            fail(path, n, sprintf(['alias name [%s] must use lower-case letters, digits and ' ...
                 'hyphens, start with a letter and not end with a hyphen'], hdr{1}));
        end
        if isKey(aliases, name)
            fail(path, n, sprintf('alias [%s] is defined twice (first on line %d)', ...
                 name, aliases(name).line));
        end
        aliases(name) = struct('name', name, 'base', '', 'settings', struct(), 'text', '', 'line', n);
        cur = name;
        continue;
    end
    kv = regexp(s, '^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*)$', 'tokens', 'once');
    if isempty(kv)
        fail(path, n, sprintf('cannot read "%s"; expected [alias name] or setting = value', strtrim(raw)));
    end
    if isempty(cur)
        fail(path, n, 'a setting must come after an [alias name] line');
    end
    key = lower(kv{1});
    val = strtrim(kv{2});
    al = aliases(cur);
    if strcmp(key, 'base')
        if ~isempty(al.base)
            fail(path, n, sprintf('[%s] sets base twice', cur));
        end
        al.base = canonical_name(val);
    else
        if isfield(al.settings, key)
            fail(path, n, sprintf('[%s] sets %s twice', cur, key));
        end
        v = parse_value(val);
        if isempty(v) && ~islogical(v)
            fail(path, n, sprintf(['[%s] %s = %s: the value must be a number, a list such as ' ...
                 '[0.3 0.5], a range such as 0.2:0.1:0.8, true or false'], cur, key, val));
        end
        al.settings.(key) = v;
    end
    aliases(cur) = al;
end

names = keys(aliases);
for i = 1:numel(names)
    al = aliases(names{i});
    if isempty(al.base)
        fail(path, al.line, sprintf('[%s] has no base = ... line (the optimizer it runs)', al.name));
    end
    al.text = settings_text(al.settings);
    aliases(names{i}) = al;
end
end

function v = parse_value(s)
% Number, [list], a:b or a:b:c range, true/false; [] when unreadable.
v = [];
t = lower(s);
if strcmp(t, 'true'); v = true; return; end
if strcmp(t, 'false'); v = false; return; end
if numel(s) >= 2 && s(1) == '[' && s(end) == ']'
    parts = regexp(strtrim(s(2:end - 1)), '[\s,]+', 'split');
    parts = parts(~cellfun('isempty', parts));
    x = str2double(parts);
    if ~isempty(x) && all(isfinite(x)); v = x; end
    return;
end
if contains(s, ':')
    x = str2double(strsplit(s, ':'));
    if all(isfinite(x)) && any(numel(x) == [2 3])
        if numel(x) == 2; v = x(1):x(2); else; v = x(1):x(2):x(3); end
        if isempty(v); v = []; end
    end
    return;
end
x = str2double(s);
if isfinite(x); v = x; end
end

function t = settings_text(settings)
% 'key = value, key = value' with keys sorted; '' when there are none.
f = sort(fieldnames(settings));
parts = cell(1, numel(f));
for i = 1:numel(f)
    parts{i} = sprintf('%s = %s', f{i}, value_text(settings.(f{i})));
end
t = strjoin(parts, ', ');
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

function id = canonical_name(name)
% Same mapping as run_experiment: lower case, hyphenated public ids.
id = lower(strtrim(char(name)));
switch id
    case 'atmals_gsk'; id = 'atmals-gsk';
    case 'fdb_agsk';   id = 'fdb-agsk';
    case 'dt_gsk';     id = 'dt-gsk';
end
end

function fail(path, n, msg)
error('read_algorithm_aliases:file', '%s, line %d: %s', path, n, msg);
end
