function verify_unified_seed_schedule(results_root, optimizers, suite)
%VERIFY_UNIFIED_SEED_SCHEDULE Confirm matching seeds across optimizers.
%
% Usage: verify_unified_seed_schedule(results_root, optimizers, suite)
% Reads <results_root>/<optimizer>/<suite>/summary/seed_schedule.csv (the
% launchers pass results/_run_all) and checks that the optimizers used the
% same seed for every (Dim,Function,Run) key found in two or more schedules.
% With fewer than two optimizers it returns at once. Prints a PASS line.
%
% Post-run safety net for the root run_all_cec*.m launchers. The seed formula
% is already optimizer-independent; this check proves the written files obey
% it. It catches future slips such as adding an optimizer index, using a
% per-optimizer base seed, or running one optimizer in reference/native mode
% while the rest run unified.
%
% Errors: verify_unified_seed_schedule:seedMismatch on a seed mismatch, and
% :missingFile, :io or :badHeader for a missing or unreadable schedule.
% A key missing from some optimizers is only a warning
% (verify_unified_seed_schedule:missingKeys), not policy drift: run_experiment
% records a failed (function, dimension) cell as a SKIP with no schedule row
% (e.g. eGSK without the Optimization Toolbox), and with overwrite=false a
% tree may hold rows from an earlier functions/runs config. Each schedule is
% compared with the union of those read before it, so a cell missing from the
% first optimizer is still compared between the others.
%
% Result directories are append-only, so a run repeated after a policy change
% can leave older rows for the same key. The reader keeps the latest row per
% key, which is the active schedule: run_experiment appends the active seed
% again whenever it reuses a run whose latest row came from another
% configuration. Old rows stay for audit; only the current schedule is
% compared.

optimizers = cellstr(optimizers);
if numel(optimizers) < 2
    return;
end

schedules = cell(1, numel(optimizers));
for i = 1:numel(optimizers)
    schedules{i} = read_seed_schedule(fullfile(results_root, optimizers{i}, suite, 'summary', 'seed_schedule.csv'));
end

all_keys = schedules{1}(:, 1:3);
all_seeds = schedules{1}(:, 4);
owner = repmat(optimizers(1), size(all_keys, 1), 1);
n_compared = 0;
for i = 2:numel(optimizers)
    opt = optimizers{i};
    rows = schedules{i};
    [~, ia, ib] = intersect(all_keys, rows(:, 1:3), 'rows');
    bad = find(all_seeds(ia) ~= rows(ib, 4), 1);
    if ~isempty(bad)
        k = all_keys(ia(bad), :);
        error('verify_unified_seed_schedule:seedMismatch', ...
            'unified seed mismatch between %s and %s at D%d F%d run %d (%s vs %s)', ...
            owner{ia(bad)}, opt, k(1), k(2), k(3), ...
            seed_text(all_seeds(ia(bad))), seed_text(rows(ib(bad), 4)));
    end
    n_compared = n_compared + numel(ia);
    [~, inew] = setdiff(rows(:, 1:3), all_keys, 'rows');
    all_keys = [all_keys; rows(inew, 1:3)]; %#ok<AGROW>
    all_seeds = [all_seeds; rows(inew, 4)]; %#ok<AGROW>
    owner = [owner; repmat({opt}, numel(inew), 1)]; %#ok<AGROW>
end

n_keys = size(all_keys, 1);
for i = 1:numel(optimizers)
    [~, imiss] = setdiff(all_keys, schedules{i}(:, 1:3), 'rows');
    if isempty(imiss); continue; end
    k = all_keys(imiss(1), :);
    warning('verify_unified_seed_schedule:missingKeys', ...
        ['%s has no seed_schedule row for %d of %d (Dim,Function,Run) key(s) ' ...
         '(first: D%d F%d run %d); those keys were not compared for it ' ...
         '(failed/skipped cells or a different functions/runs config)'], ...
        optimizers{i}, numel(imiss), n_keys, k(1), k(2), k(3));
end

fprintf(['verify_unified_seed_schedule: PASS (%d optimizers, %d scheduled key(s), ' ...
         '%d cross-optimizer seed comparison(s))\n'], numel(optimizers), n_keys, n_compared);
end

function rows = read_seed_schedule(path)
%READ_SEED_SCHEDULE Rows [Dim Function Run Seed], latest per key, key-sorted.
assert(isfile(path), 'verify_unified_seed_schedule:missingFile', ...
    'missing seed schedule: %s', path);
fid = fopen(path, 'r');
assert(fid > 0, 'verify_unified_seed_schedule:io', 'cannot open %s', path);
closer = onCleanup(@() fclose(fid));
header = strtrim(fgetl(fid));
assert(strcmp(header, 'Dim,Function,Run,Seed'), 'verify_unified_seed_schedule:badHeader', ...
    'unexpected seed schedule header in %s', path);
data = textscan(fid, '%f%f%f%f', 'Delimiter', ',', 'CollectOutput', true);
rows = data{1};
if isempty(rows)
    rows = zeros(0, 4);
else
    [~, last_idx] = unique(rows(:, 1:3), 'rows', 'last');
    rows = rows(sort(last_idx), :);
    rows = sortrows(rows, [1 2 3]);
end
end

function s = seed_text(seed)
s = sprintf('%.0f', seed);
end
