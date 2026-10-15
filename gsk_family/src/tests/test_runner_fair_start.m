function test_runner_fair_start()
%TEST_RUNNER_FAIR_START Unified fair-start X0 through run_experiment, the six runner-X0 optimizers.
%
% Under seed_policy='unified' the runner seeds get_cec_seed(base_seed,D,func,run)
% with the resolved generator, draws X0 once (gsk_init_population, NP=100),
% captures the post-X0 RNG state and passes both to the optimizer. DT-GSK is
% not listed: it samples its own NP = 5*D population and the runner draws no
% X0 for it (documented fair-start exception; test_dt_gsk_smoke checks that a
% supplied X0 is ignored). Checks, on the pure-MATLAB sphere suite, for every
% listed optimizer and run:
%   1. the first gen_logs checkpoint (before any generation has finished, so
%      it holds the first convergence record = best of the initial population)
%      equals min f(X0) for the runner's X0 - the same value for all six;
%   2. the per_run.csv best_fitness equals a direct optimizer call given that
%      X0 and post-X0 RNG state (the runner wires both through unchanged);
%   3. the final checkpoint E<max_nfes> equals the per-run final error, also
%      for optimizers whose last counter reads max_nfes+1 (FDB-AGSK, eGSK).

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
addpath(fullfile(project_root, 'src', 'common'));
out_root = fullfile(tempdir, sprintf('gskcec_fair_start_%d', feature('getpid')));
if exist(out_root, 'dir'); rmdir(out_root, 's'); end
cleanup = onCleanup(@() remove_dir(out_root)); %#ok<NASGU>

names = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk'};
stems = {'gsk', 'agsk', 'apgsk', 'atmals_gsk', 'egsk', 'fdb_agsk'};
if ~(license('test', 'Optimization_Toolbox') && ~isempty(ver('optim')))
    fprintf('test_runner_fair_start: egsk skipped (reference eGSK needs fmincon / Optimization Toolbox)\n');
    keep = ~strcmp(names, 'egsk');
    names = names(keep);
    stems = stems(keep);
end

D = 10; func_id = 1; runs = 2; mnf = 2000; base_seed = 20240620;
gen = choose_cec_rng_generator();
for k = 1:numel(names)
    run_experiment('optimizer', names{k}, 'suite', 'sphere', 'functions', func_id, ...
                   'dimensions', D, 'runs', runs, 'max_nfes', mnf, 'base_seed', base_seed, ...
                   'project_root', project_root, 'output_dir', fullfile(out_root, names{k}), ...
                   'seed_policy', 'unified', 'rand_generator', 'threefry', 'verbose', false, ...
                   'overwrite', true);
end

problem = gskcec_make_problem('sphere', func_id, D, project_root, mnf);
for r = 1:runs
    seed = get_cec_seed(base_seed, D, func_id, r);
    rng(seed, gen);
    x0 = gsk_init_population(100, problem.lb, problem.ub);
    st = rng;
    f0 = min(problem.evaluate(x0));
    for k = 1:numel(names)
        out = fullfile(out_root, names{k});
        [hdr, chk] = csv_rows(fullfile(out, 'gen_logs', ...
            sprintf('CheckpointErrors_%s_F%d_D%d.csv', names{k}, func_id, D)));
        row = chk(str2double(chk(:, 1)) == r, :);
        assert(size(row, 1) == 1, '%s run %d: expected one checkpoint row', names{k}, r);
        assert(row(2) == string(seed), '%s run %d: checkpoint seed is not the unified seed', names{k}, r);
        % 1. first checkpoint = best of the runner's X0 (identical across optimizers)
        assert(row(3) == sprintf('%.16g', f0), ...
               '%s run %d: initial best %s differs from min f(runner X0) %.16g', names{k}, r, row(3), f0);

        [~, pr] = csv_rows(fullfile(out, 'summary', 'per_run.csv'));
        pr = pr(str2double(pr(:, 5)) == r, :);
        assert(size(pr, 1) == 1, '%s run %d: expected one per_run row', names{k}, r);
        best = str2double(pr(7));
        err = str2double(pr(8));
        % 2. per_run result = direct call with the runner's X0 + post-X0 state
        opts = struct('seed', seed, 'rand_generator', gen, ...
                      'initial_population', x0, 'rng_state_after_initialization', st);
        if strcmp(names{k}, 'egsk'); opts.use_fmincon = true; end   % runner default for eGSK
        direct = feval([stems{k} '_optimize'], problem, opts);
        assert(direct.best_fitness == best, ...
               '%s run %d: run_experiment result %.17g differs from the direct fair-start call %.17g', ...
               names{k}, r, best, direct.best_fitness);
        % 3. final checkpoint = per-run final error
        assert(hdr(end) == sprintf('E%d', mnf), 'last checkpoint column must be E<max_nfes>');
        e_last = str2double(row(end));
        if err == 0
            assert(abs(e_last) < 1e-8, '%s run %d: E%d must be below the zero cut', names{k}, r, mnf);
        else
            assert(row(end) == sprintf('%.16g', err), ...
                   '%s run %d: E%d = %s but the per-run error is %.16g (nfes %s)', ...
                   names{k}, r, mnf, row(end), err, pr(9));
        end
    end
end

fprintf('test_runner_fair_start: PASS (%s)\n', strjoin(names, ', '));
end

function [header, rows] = csv_rows(path)
% Header fields and the data rows of a small numeric CSV, as strings.
lines = readlines(path);
lines = lines(strlength(strtrim(lines)) > 0);
header = split(lines(1), ',')';
rows = strings(numel(lines) - 1, numel(header));
for i = 2:numel(lines)
    rows(i - 1, :) = split(lines(i), ',')';
end
end

function remove_dir(d)
if exist(d, 'dir'); rmdir(d, 's'); end
end
