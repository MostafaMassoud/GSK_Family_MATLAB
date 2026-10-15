function verify_unified_seed_schedule(results_root, optimizers, suite)
%VERIFY_UNIFIED_SEED_SCHEDULE Confirm matching seeds across optimizers.
%
% Reads results/_run_all/<optimizer>/<suite>/summary/seed_schedule.csv and
% verifies that every successful optimizer used the same seed for each
% (Dim,Function,Run) key.
%
% This is a post-run safety net for the root run_all_cec*.m launchers. The
% seed formula is already optimizer-independent, but this check proves the
% written artifacts obeyed that contract. It catches accidental future changes
% such as adding an optimizer index, using a per-optimizer base seed, or running
% one optimizer under reference/native mode while the rest run unified.
%
% Result directories are append-only. When a run is repeated after a policy
% change, seed_schedule.csv may contain older historical rows for the same
% (Dim,Function,Run). The reader below keeps the latest row per key, matching
% run_experiment's seed-aware resume behavior: old rows remain auditable, while
% the current schedule is what gets compared.

optimizers = cellstr(optimizers);
if numel(optimizers) < 2
    return;
end

ref_opt = optimizers{1};
ref_rows = read_seed_schedule(fullfile(results_root, ref_opt, suite, 'summary', 'seed_schedule.csv'));
for i = 2:numel(optimizers)
    opt = optimizers{i};
    rows = read_seed_schedule(fullfile(results_root, opt, suite, 'summary', 'seed_schedule.csv'));
    assert(isequal(ref_rows(:, 1:3), rows(:, 1:3)), 'verify_unified_seed_schedule:keyMismatch', ...
        'seed schedule keys differ between %s and %s', ref_opt, opt);
    assert(isequal(ref_rows(:, 4), rows(:, 4)), 'verify_unified_seed_schedule:seedMismatch', ...
        'unified seed mismatch between %s and %s', ref_opt, opt);
end

fprintf('verify_unified_seed_schedule: PASS (%d optimizers, %d scheduled run rows)\n', ...
        numel(optimizers), size(ref_rows, 1));
end

function rows = read_seed_schedule(path)
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
