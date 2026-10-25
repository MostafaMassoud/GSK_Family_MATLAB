function path = new_gsk_variant(name, varargin)
%NEW_GSK_VARIANT Create a new optimizer as a renamed copy of a GSK-family member.
%
%   new_gsk_variant('my-gsk')                       copy of GSK
%   new_gsk_variant('my-agsk', 'base','agsk')       copy of AGSK
%   path = new_gsk_variant('my-gsk', 'base','gsk', ...
%                          'description','GSK with an opposition-based step')
%
% Creates src/optimizers/<name>/<stem>_optimize.m (stem = name with hyphens
% replaced by underscores, e.g. my-gsk -> my_gsk_optimize) from the base
% optimizer's main file, and returns its path. The copy is identical to the
% base except:
%   - every <base_stem>_optimize becomes <stem>_optimize (function name, help
%     text, error ids), in lower and upper case;
%   - result.optimizer is set to the new name;
%   - the first help line names the new optimizer and its base.
% Untouched, the copy gives exactly the base's results under the unified seed
% policy, which is a good first check. Then edit it. The runner finds it with
% no registration: run_experiment('optimizer','<name>', ...).
%
% Options:
%   base          one of gsk (default), agsk, apgsk, fdb-agsk, atmals-gsk,
%                 egsk, dt-gsk.
%   description   text for the first help line. Default 'New GSK-family optimizer'.
%   project_root  the gsk_family folder. Default: the parent of this script's
%                 folder.
%
% Names: lower-case letters, digits and hyphens, starting with a letter, and
% not one of the seven built-in names. An existing folder is never
% overwritten.
%
% Helper files of the base (for example atmals_roulette_select.m or
% dt_gsk_config.m) are not copied: the copy keeps calling the base's helpers,
% which stay on the path. To change a helper, copy it into the new folder
% under a new name and call that name from the copy.

p = inputParser;
p.addRequired('name', @(x) ischar(x) || isstring(x));
p.addParameter('base', 'gsk', @(x) ischar(x) || isstring(x));
p.addParameter('description', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', fileparts(fileparts(mfilename('fullpath'))), @(x) ischar(x) || isstring(x));
p.parse(name, varargin{:});
a = p.Results;

family = {'gsk', 'agsk', 'apgsk', 'fdb-agsk', 'atmals-gsk', 'egsk', 'dt-gsk'};
name = lower(strtrim(char(a.name)));
base = lower(strrep(strtrim(char(a.base)), '_', '-'));
assert(~isempty(regexp(name, '^[a-z][a-z0-9-]*$', 'once')) && name(end) ~= '-', ...
       'new_gsk_variant:name', ['name ''%s'' must use lower-case letters, digits and hyphens, ' ...
       'start with a letter and not end with a hyphen (e.g. my-gsk)'], name);
assert(~any(strcmp(name, family)), 'new_gsk_variant:name', ...
       '''%s'' is a built-in optimizer; choose a new name (e.g. my-%s)', name, name);
assert(any(strcmp(base, family)), 'new_gsk_variant:base', ...
       'base must be one of: %s', strjoin(family, ', '));

root = char(a.project_root);
stem = strrep(name, '-', '_');
base_stem = strrep(base, '-', '_');
src = fullfile(root, 'src', 'optimizers', base, [base_stem '_optimize.m']);
dst_dir = fullfile(root, 'src', 'optimizers', name);
dst = fullfile(dst_dir, [stem '_optimize.m']);
assert(isfile(src), 'new_gsk_variant:base', 'base file not found: %s', src);
assert(~exist(dst_dir, 'dir'), 'new_gsk_variant:exists', ...
       'folder already exists (nothing changed): %s', dst_dir);

text = fileread(src);
text = regexprep(text, ['\<' base_stem '_optimize\>'], [stem '_optimize']);
text = regexprep(text, ['\<' upper(base_stem) '_OPTIMIZE\>'], [upper(stem) '_OPTIMIZE']);
opt_line = ['result\.optimizer\s*=\s*''' regexptranslate('escape', base) ''';'];
assert(numel(regexp(text, opt_line)) == 1, 'new_gsk_variant:base', ...
       'could not find result.optimizer = ''%s''; in %s', base, src);
text = regexprep(text, opt_line, ['result.optimizer = ''' name ''';']);
desc = char(a.description);
if isempty(desc); desc = 'New GSK-family optimizer'; end
% First help line: %<STEM>_OPTIMIZE <description> (based on <BASE>).
text = regexprep(text, ['^%' upper(stem) '_OPTIMIZE[^\r\n]*'], ...
                 sprintf('%%%s_OPTIMIZE %s (based on %s).', upper(stem), desc, display_name(base)), ...
                 'once', 'lineanchors');

mkdir(dst_dir);
fid = fopen(dst, 'w');
assert(fid > 0, 'new_gsk_variant:io', 'cannot write %s', dst);
fwrite(fid, text, 'char');
fclose(fid);
path = dst;

fprintf('new_gsk_variant: created %s\n', dst);
fprintf('  base:  %s (%s)\n', display_name(base), src);
fprintf('  next:  1. edit the file;\n');
fprintf(['         2. quick check: addpath(''%s''); run_experiment(''optimizer'',''%s'',''suite'',''cec2017'', ' ...
         '''functions'',1,''dimensions'',10,''runs'',2,''max_nfes'',3000,''project_root'',''%s'', ' ...
         '''output_dir'',fullfile(tempdir,''%s_check''),''use_parallel'',false)\n'], ...
        strrep(fullfile(root, 'src', 'runners'), '\', '/'), name, strrep(root, '\', '/'), stem);
fprintf('         3. add ''%s'' to optimizers in a run_all_cec*.m launcher.\n', name);
end

function s = display_name(id)
switch id
    case 'egsk'; s = 'eGSK';
    otherwise;   s = upper(id);
end
end
