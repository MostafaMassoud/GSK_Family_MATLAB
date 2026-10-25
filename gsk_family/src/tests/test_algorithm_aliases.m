function test_algorithm_aliases()
%TEST_ALGORITHM_ALIASES algorithms.ini aliases through run_experiment.
%
% Uses a temporary aliases file ('aliases_file') and the sphere suite (no
% MEX). Checks that:
%   1. read_algorithm_aliases reads numbers, lists, ranges, true/false and
%      comments, and refuses bad lines, missing base, duplicates and
%      unreadable values with read_algorithm_aliases:file;
%   2. an alias with no settings gives exactly the base's runs (same seeds,
%      same results), labelled with the alias name, and environment.json /
%      run_config.json record the base and the settings;
%   3. np_init and min_pop_size in an alias equal the same values passed to
%      run_experiment (gsk with np_init 50, agsk with min_pop_size 20);
%   4. other settings reach the optimizer (gsk kf/kr change the results and
%      are recorded in run_config.json);
%   5. unknown, protected and misplaced settings, an unknown name, an alias
%      named like an optimizer and a tree written with other alias settings
%      are refused with run_experiment:args;
%   6. compare_algorithms writes the settings table with the base and the
%      changed settings.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
addpath(fullfile(project_root, 'scripts'));
root = fullfile(tempdir, sprintf('gskcec_aliases_%d', feature('getpid')));
if exist(root, 'dir'); rmdir(root, 's'); end
mkdir(root);
cleanup = onCleanup(@() remove_dir(root)); %#ok<NASGU>
ini = fullfile(root, 'algorithms.ini');

% 1. Parser.
write_ini(ini, {'; comment line', '[g-same]', 'base = gsk', '', ...
    '[g-np50]', 'base = gsk', 'np_init = 50   ; inline comment', ...
    '[g-kf]', 'base = gsk', 'kf = 0.7', 'kr = 0.8', ...
    '[a-min20]', 'base = agsk', 'min_pop_size = 20', ...
    '[parse-check]', 'base = atmals-gsk', 'kf_pool = 0.2:0.1:0.8', 'kr_pool = [0.85, 0.9 1]', ...
    '# hash comment', '[e-nols]', 'base = egsk', 'use_fmincon = false'});
al = read_algorithm_aliases(ini);
assert(al.Count == 6, 'expected 6 aliases, got %d', al.Count);
p = al('parse-check');
assert(isequal(p.settings.kf_pool, 0.2:0.1:0.8) && isequal(p.settings.kr_pool, [0.85 0.9 1]), 'list/range parse');
assert(islogical(al('e-nols').settings.use_fmincon) && ~al('e-nols').settings.use_fmincon, 'logical parse');
assert(strcmp(al('g-kf').text, 'kf = 0.7, kr = 0.8') && strcmp(al('g-np50').text, 'np_init = 50'), 'canonical text');
assert(isempty(al('g-same').text) && strcmp(al('g-same').base, 'gsk'), 'alias without settings');
bad = {{'[x1]', 'kf = 0.7'}, ...                          % no base
       {'[x1]', 'base = gsk', '[x1]', 'base = gsk'}, ...   % duplicate alias
       {'[x1]', 'base = gsk', 'kf = abc'}, ...             % unreadable value
       {'kf = 0.7'}, ...                                   % setting before a section
       {'[X 1]', 'base = gsk'}, ...                        % bad name
       {'[x1]', 'base = gsk', 'kf = 1', 'kf = 2'}, ...     % duplicate setting
       {'[x1]', 'base = gsk', 'just text'}};               % not key = value
for b = 1:numel(bad)
    bad_ini = fullfile(root, sprintf('bad%d.ini', b));
    write_ini(bad_ini, bad{b});
    expect_error(@() read_algorithm_aliases(bad_ini), 'read_algorithm_aliases:file', sprintf('bad file %d', b));
end
assert(read_algorithm_aliases(fullfile(root, 'missing.ini')).Count == 0, 'missing file -> empty map');

common = {'suite', 'sphere', 'functions', 1, 'dimensions', 10, 'runs', 3, 'base_seed', 4242, ...
          'max_nfes', 4000, 'project_root', project_root, 'aliases_file', ini, 'verbose', false};
% Results go to <root>/<name>/sphere, the layout compare_algorithms reads.
go = @(name, out, varargin) run_experiment('optimizer', name, common{:}, ...
          'output_dir', fullfile(root, out, 'sphere'), varargin{:});

% 2. No settings: identical to the base, labelled with the alias.
go('gsk', 'gsk');
go('g-same', 'g-same');
A = per_run(root, 'gsk'); B = per_run(root, 'g-same');
assert(isequal(A.best_fitness, B.best_fitness) && isequal(A.seed, B.seed), 'alias without settings must equal its base');
assert(all(strcmp(B.optimizer, 'g-same')), 'per_run rows must carry the alias name');
assert(isfile(fullfile(root, 'g-same', 'sphere', 'summary', 'g-same_sphere_D10.csv')), 'summary file named after the alias');
env = jsondecode(fileread(fullfile(root, 'g-same', 'sphere', 'summary', 'environment.json')));
assert(strcmp(env.optimizer, 'g-same') && strcmp(env.base_optimizer, 'gsk') && isempty(env.alias_settings), 'environment.json');

% 3. Population settings equal the same run_experiment arguments.
go('gsk', 'gsk-np50-arg', 'np_init', 50);
go('g-np50', 'g-np50');
assert(isequal(per_run(root, 'gsk-np50-arg').best_fitness, per_run(root, 'g-np50').best_fitness), 'alias np_init');
go('agsk', 'agsk-min20-arg', 'min_pop_size', 20);
go('a-min20', 'a-min20');
assert(isequal(per_run(root, 'agsk-min20-arg').best_fitness, per_run(root, 'a-min20').best_fitness), 'alias min_pop_size');
% The alias value wins over the call's (launcher-wide) value.
go('g-np50', 'g-np50-wins', 'np_init', 80);
assert(isequal(per_run(root, 'g-np50').best_fitness, per_run(root, 'g-np50-wins').best_fitness), 'alias np_init wins');

% 4. Other settings reach the optimizer and are recorded.
go('g-kf', 'g-kf');
assert(~isequal(A.best_fitness, per_run(root, 'g-kf').best_fitness), 'kf/kr must change the GSK runs');
cfg = jsondecode(fileread(fullfile(root, 'g-kf', 'sphere', 'summary', 'run_config.json')));
assert(cfg.KF == 0.7 && cfg.KR == 0.8 && strcmp(cfg.base_optimizer, 'gsk') && ...
       strcmp(cfg.alias_settings, 'kf = 0.7, kr = 0.8'), 'run_config.json records the alias settings');

% 5. Refusals.
write_ini(ini, {'[g-typo]', 'base = gsk', 'kff = 0.7', ...
    '[g-seed]', 'base = gsk', 'seed = 5', ...
    '[g-min]', 'base = gsk', 'min_pop_size = 20', ...
    '[gsk]', 'base = agsk', ...
    '[g-kf]', 'base = gsk', 'kf = 0.6', 'kr = 0.8'});
expect_error(@() go('g-typo', 'x1'), 'run_experiment:args', 'unknown setting');
expect_error(@() go('g-seed', 'x2'), 'run_experiment:args', 'protected setting');
expect_error(@() go('g-min', 'x3'), 'run_experiment:args', 'min_pop_size for a fixed population');
expect_error(@() go('no-such-alias', 'x4'), 'run_experiment:args', 'unknown name');
expect_error(@() go('gsk', 'x5'), 'run_experiment:args', 'alias named like an optimizer');
expect_error(@() go('g-kf', 'g-kf'), 'run_experiment:args', 'tree written with other alias settings');
try
    go('g-typo', 'x6');
catch err
    assert(contains(err.message, 'Accepted: np_init, kf, kr, k, p'), 'the message lists the accepted settings');
end

% 6. Settings table.
rep = compare_algorithms('suite', 'sphere', 'optimizers', {'g-kf', 'gsk', 'g-np50'}, ...
          'results_root', root, 'output_dir', fullfile(root, 'cmp'));
S = rep.settings;
assert(strcmp(S(1).base, 'gsk') && strcmp(S(1).other, 'kf = 0.7, kr = 0.8') && ...
       strcmp(S(2).other, 'original') && strcmp(S(2).np_init, '100 (original)') && ...
       strcmp(S(3).np_init, '50') && strcmp(S(3).min_pop_size, 'fixed'), 'settings table rows');
assert(isfile(fullfile(root, 'cmp', 'settings_sphere.tex')), 'settings_<suite>.tex');

fprintf('test_algorithm_aliases: PASS\n');
end

function T = per_run(root, name)
T = readtable(fullfile(root, name, 'sphere', 'summary', 'per_run.csv'), 'TextType', 'char', ...
              'VariableNamingRule', 'preserve');
T = sortrows(T, 'run');
end

function write_ini(path, lines)
fid = fopen(path, 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function expect_error(fn, id, what)
try
    fn();
catch err
    assert(strcmp(err.identifier, id), '%s: expected %s, got %s (%s)', what, id, err.identifier, err.message);
    return;
end
error('test_algorithm_aliases:noError', '%s: expected error %s', what, id);
end

function remove_dir(d)
%REMOVE_DIR Delete folder d and its contents, if it exists.
if exist(d, 'dir'); rmdir(d, 's'); end
end
