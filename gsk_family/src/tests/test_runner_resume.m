function test_runner_resume()
%TEST_RUNNER_RESUME Resume/add mode reuses only rows of the active configuration.
%
% A summary/per_run.csv row is reused on resume only when its seed, its cell
% budget (max_nfes column) and its effective generator (rand_generator column)
% all match the active run. Otherwise the run id is executed again and
% appended; the old row stays as history and the summary uses only the active
% rows. Also covered on the pure-MATLAB sphere suite (no MEX):
%   - an identical rerun leaves per_run.csv and the summary byte-identical
%     (per_run values are stored at round-trip precision),
%   - a reused run whose latest seed_schedule.csv row came from another
%     session gets the active seed appended again,
%   - after a resume each cell keeps exactly one median-run curve,
%   - a per_run.csv written before the max_nfes/rand_generator columns existed
%     is upgraded from the tree's run_config.json and stays reusable.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
out_root = fullfile(tempdir, sprintf('gskcec_runner_resume_%d', feature('getpid')));
if exist(out_root, 'dir'); rmdir(out_root, 's'); end
cleanup = onCleanup(@() remove_dir(out_root)); %#ok<NASGU>
gen = choose_cec_rng_generator();
D = 5;

% ---- stale budget / seed / generator ------------------------------------
out = fullfile(out_root, 'stale');
per_run = fullfile(out, 'summary', 'per_run.csv');
summary = fullfile(out, 'summary', sprintf('gsk_sphere_D%d.csv', D));
schedule = fullfile(out, 'summary', 'seed_schedule.csv');
go = @(seed, nfes, rgen) run_experiment('optimizer', 'gsk', 'suite', 'sphere', ...
    'functions', 1, 'dimensions', D, 'runs', 2, 'base_seed', seed, 'max_nfes', nfes, ...
    'rand_generator', rgen, 'project_root', project_root, 'output_dir', out, 'verbose', false);

go(4242, 2000, 'threefry');
rows = data_rows(per_run);
assert(numel(rows) == 2, 'expected 2 per-run rows');
assert(all(field(rows, 12) == "2000") && all(field(rows, 13) == gen), ...
       'per_run.csv must record the cell budget and the effective generator');

% Identical rerun: every run is reused, nothing is appended, and the summary
% rebuilt from per_run.csv is byte-identical to the one from the fresh values.
per_run_0 = fileread(per_run);
summary_0 = fileread(summary);
go(4242, 2000, 'threefry');
assert(strcmp(fileread(per_run), per_run_0), 'identical rerun must not append per-run rows');
assert(strcmp(fileread(summary), summary_0), ...
       'identical rerun must leave the summary unchanged (round-trip per_run values)');

% Budget change, same seeds: the 2000-NFE rows must not count as 3000-NFE runs.
go(4242, 3000, 'threefry');
rows = data_rows(per_run);
assert(numel(rows) == 4, 'a budget change must re-run the existing run ids');
assert(startsWith(fileread(per_run), per_run_0), 'stale rows must stay in per_run.csv as history');
assert(all(field(rows(3:4), 12) == "3000") && isequal(field(rows(3:4), 5), ["1"; "2"]), ...
       'appended rows must be runs 1:2 at the new budget');
assert_summary_from(summary, rows(3:4));
summary_3000 = fileread(summary);

% Seed change (base_seed): rows of the old schedule are stale as well.
go(4243, 3000, 'threefry');
rows = data_rows(per_run);
assert(numel(rows) == 6, 'a seed change must re-run the existing run ids');
new_seeds = str2double(field(rows(5:6), 6));
assert(isequal(new_seeds(:)', [get_cec_seed(4243, D, 1, 1), get_cec_seed(4243, D, 1, 2)]), ...
       'appended rows must carry the new seeds');
assert_summary_from(summary, rows(5:6));

% Back to the 4242/3000 configuration: its rows are reused (nothing appended),
% the summary is the 4242/3000 one again, and because the latest schedule rows
% are now the 4243 seeds, the active seeds are recorded again.
go(4242, 3000, 'threefry');
assert(numel(data_rows(per_run)) == 6, 'matching rows must be reused, not re-run');
assert(strcmp(fileread(summary), summary_3000), 'reused rows must reproduce the summary');
latest = latest_schedule(schedule);
assert(isequal(latest(:, 4)', [get_cec_seed(4242, D, 1, 1), get_cec_seed(4242, D, 1, 2)]), ...
       'latest seed_schedule rows must describe the reused (active) runs');
% The stored curve now belongs to a 4243 run, not to the reused median run
% (whose own curve was superseded in the 4243 session): no stale curve stays.
assert(isempty(curve_files(out, 1, D)), 'a curve of a stale run must not be kept as the median curve');

% Generator change (unified threefry -> twister) is stale too.
if strcmp(gen, 'threefry')
    go(4242, 3000, 'twister');
    rows = data_rows(per_run);
    assert(numel(rows) == 8 && all(field(rows(7:8), 13) == "twister"), ...
           'a generator change must re-run the existing run ids');
    assert_summary_from(summary, rows(7:8));
    assert(numel(curve_files(out, 1, D)) == 1, 'one median curve per cell after a re-run');
else
    fprintf('test_runner_resume: generator-change check skipped (threefry unavailable)\n');
end

% ---- one median-run curve per cell after adding runs ----------------------
out_c = fullfile(out_root, 'curves');
for nr = [3 5]
    run_experiment('optimizer', 'gsk', 'suite', 'sphere', 'functions', 1:2, ...
                   'dimensions', [5 10], 'runs', nr, 'base_seed', 4242, 'max_nfes', 2000, ...
                   'project_root', project_root, 'output_dir', out_c, 'verbose', false);
end
rows = data_rows(fullfile(out_c, 'summary', 'per_run.csv'));
median_changed = false;
for f = 1:2
    for d = [5 10]
        cell_rows = rows(field(rows, 3) == string(f) & field(rows, 4) == string(d));
        [~, order] = sort(str2double(field(cell_rows, 5)));
        v = str2double(field(cell_rows(order), 8));
        [~, med] = min(abs(v - median(v)));            % median run over runs 1:5
        [~, med3] = min(abs(v(1:3) - median(v(1:3))));  % median run of the first session
        files = curve_files(out_c, f, d);
        median_changed = median_changed || med ~= med3;
        if med >= 4 || med == med3
            % The median's trace exists (new run, or the first session's median).
            assert(numel(files) == 1 && strcmp(files{1}, sprintf('Figure_F%d_D%d_Run#%d.csv', f, d, med)), ...
                   'F%d D%d: expected only the median curve Run#%d, found %s', f, d, med, strjoin(files, ' '));
        else
            % The median is an earlier non-median run whose trace was never stored.
            assert(isempty(files), 'F%d D%d: no stale curve may stand in for median run %d', f, d, med);
        end
    end
end
assert(~median_changed || isfolder(fullfile(out_c, 'curves', '_archive')), ...
       'superseded curves must be archived, not deleted');

% ---- per_run.csv from before the max_nfes/rand_generator columns -----------
legacy_header = 'optimizer,suite,function,dimension,run,seed,best_fitness,error,nfes,termination,runtime_seconds';
% (a) explicit budget, run_config.json present: rows are upgraded and reused.
out_l = fullfile(out_root, 'legacy');
legacy_go = @(out_dir, dim, nfes) run_experiment('optimizer', 'gsk', 'suite', 'sphere', ...
    'functions', 1, 'dimensions', dim, 'runs', 2, 'base_seed', 4242, 'max_nfes', nfes, ...
    'project_root', project_root, 'output_dir', out_dir, 'verbose', false);
legacy_go(out_l, D, 2000);
make_legacy(fullfile(out_l, 'summary', 'per_run.csv'), legacy_header);
legacy_go(out_l, D, 2000);
rows = data_rows(fullfile(out_l, 'summary', 'per_run.csv'));
assert(numel(rows) == 2, 'legacy rows of the same configuration must be reused');
assert(all(field(rows, 12) == "2000") && all(field(rows, 13) == gen), ...
       'legacy rows must be upgraded with the recorded budget and generator');
lines = readlines(fullfile(out_l, 'summary', 'per_run.csv'));
assert(endsWith(lines(1), ',max_nfes,rand_generator'), 'legacy header must be upgraded');
archived = dir(fullfile(out_l, 'summary', '_archive', '*', 'per_run.csv'));
assert(~isempty(archived) && startsWith(fileread(fullfile(archived(1).folder, archived(1).name)), ...
       [legacy_header newline]), 'the legacy per_run.csv must be archived before the upgrade');
% (b) suite-default budget (max_nfes 0): the legacy budget is resolved per cell.
out_d = fullfile(out_root, 'legacy_default');
legacy_go(out_d, 2, 0);
make_legacy(fullfile(out_d, 'summary', 'per_run.csv'), legacy_header);
legacy_go(out_d, 2, 0);
rows = data_rows(fullfile(out_d, 'summary', 'per_run.csv'));
assert(numel(rows) == 2 && all(field(rows, 12) == "20000"), ...
       'legacy suite-default rows must resolve to the cell default budget and be reused');
% (c) no run_config.json: budget/generator unknown, so the runs are re-run.
out_u = fullfile(out_root, 'legacy_unknown');
legacy_go(out_u, D, 2000);
make_legacy(fullfile(out_u, 'summary', 'per_run.csv'), legacy_header);
delete(fullfile(out_u, 'summary', 'run_config.json'));
legacy_go(out_u, D, 2000);
rows = data_rows(fullfile(out_u, 'summary', 'per_run.csv'));
assert(numel(rows) == 4 && all(field(rows(1:2), 12) == "") && all(field(rows(3:4), 12) == "2000"), ...
       'legacy rows without a recorded configuration must be re-run, not reused');

fprintf('test_runner_resume: PASS\n');
end

% ---- helpers ------------------------------------------------------------------

function rows = data_rows(path)
rows = readlines(path);
rows = rows(2:end);
rows = rows(strlength(strtrim(rows)) > 0);
end

function v = field(rows, k)
% k-th comma-separated field of each row (empty fields kept), as a column.
v = strings(numel(rows), 1);
for i = 1:numel(rows)
    f = split(rows(i), ',');
    v(i) = f(k);
end
end

function assert_summary_from(summary, rows)
% Summary Best/Worst must come from exactly these per-run rows (error column).
s = readlines(summary);
vals = split(s(2), ',');
err = str2double(field(rows, 8));
assert(vals(2) == sprintf('%.10E', min(err)) && vals(5) == sprintf('%.10E', max(err)), ...
       'summary must be computed from the active per-run rows only');
end

function rows = latest_schedule(path)
fid = fopen(path, 'r');
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fgetl(fid);
data = textscan(fid, '%f%f%f%f', 'Delimiter', ',', 'CollectOutput', true);
rows = data{1};
[~, last_idx] = unique(rows(:, 1:3), 'rows', 'last');
rows = sortrows(rows(last_idx, :), [1 2 3]);
end

function names = curve_files(out_dir, f, d)
L = dir(fullfile(out_dir, 'curves', sprintf('Figure_F%d_D%d_Run#*.csv', f, d)));
names = {L.name};
end

function make_legacy(path, legacy_header)
% Rewrite a per_run.csv the way the runner wrote it before the trailing
% max_nfes,rand_generator columns existed.
rows = data_rows(path);
out = legacy_header;
for i = 1:numel(rows)
    f = split(rows(i), ',');
    out = [out newline char(join(f(1:11), ','))]; %#ok<AGROW>
end
fid = fopen(path, 'w');
fprintf(fid, '%s\n', out);
fclose(fid);
end

function remove_dir(d)
if exist(d, 'dir'); rmdir(d, 's'); end
end
