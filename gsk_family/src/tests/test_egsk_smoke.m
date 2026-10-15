function test_egsk_smoke()
%TEST_EGSK_SMOKE Smoke test for egsk_optimize on a pure-MATLAB sphere problem.
%
% Reference-mode eGSK needs fmincon (Optimization Toolbox) for its IP stage.
% Without fmincon the default call must fail with egsk:fminconUnavailable;
% the non-reference path without IP runs only with options.use_fmincon=false.
% Raises an error when a check fails.

here = fileparts(mfilename('fullpath'));
src_root = fileparts(here);
addpath(fullfile(src_root, 'common'));
addpath(fullfile(src_root, 'optimizers', 'egsk'));

d = 10;
problem = local_sphere_problem(d, 10000, 0, 1e-8);
opts = struct('seed', 777);

has_fmincon = license('test', 'Optimization_Toolbox') && exist('fmincon', 'file') > 0;

if ~has_fmincon
    try
        egsk_optimize(problem, opts);
        error('test_egsk_smoke:failed', ...
            'egsk: reference-mode run must require fmincon when unavailable');
    catch err
        local_assert(strcmp(err.identifier, 'egsk:fminconUnavailable'), ...
            sprintf('egsk: wrong missing-fmincon error "%s"', err.identifier));
    end

    r2 = egsk_optimize(problem, struct('seed', 777, 'use_fmincon', false));
    local_check_contract(r2, problem, 'egsk', 777);
    local_assert(contains(r2.notes, 'non-reference diagnostic'), ...
        sprintf('egsk: opt-out notes must mark non-reference mode (got "%s")', r2.notes));
    local_assert(~r2.params.use_fmincon, 'egsk: opt-out params.use_fmincon must be false');
    local_assert(r2.nfes == problem.max_nfes, ...
        sprintf('egsk: opt-out nfes must equal max_nfes (got %d)', r2.nfes));

    fprintf('test_egsk_smoke: PASS\n');
    return;
end

r1 = egsk_optimize(problem, opts);
local_check_contract(r1, problem, 'egsk', opts.seed);

local_assert(isempty(r1.notes), ...
    sprintf('egsk: notes must be empty in reference mode (got "%s")', r1.notes));
local_assert(r1.params.use_fmincon, 'egsk: params.use_fmincon must be true');

% Budget, as in the reference: the per-individual counter caps at
% max_nfes (+1), and the IP refinement adds fmincon's funcCount on top (IP.m).
local_assert(r1.nfes >= problem.max_nfes, 'egsk: budget must be fully consumed');
local_assert(r1.nfes <= problem.max_nfes + 500, ...
    sprintf('egsk: nfes overshoot too large (%d)', r1.nfes));
local_assert(strcmp(r1.termination, 'max_evaluations'), ...
    'egsk: termination must be max_evaluations (reference never stops early)');

% Progress: best_fitness must be far below the median fitness of the
% optimizer's own initial population (its first RNG draw, rebuilt here).
np = r1.params.np;
rng(opts.seed, 'twister');
pop0 = repmat(problem.lb, np, 1) + rand(np, d) .* repmat(problem.ub - problem.lb, np, 1);
med0 = median(problem.evaluate(pop0));
local_assert(isfinite(r1.best_fitness) && r1.best_fitness < 1e-2 * med0, ...
    sprintf('egsk: insufficient progress: best=%g vs initial median=%g', r1.best_fitness, med0));

% Determinism: the same seed reproduces the run (fmincon SQP is deterministic).
r1b = egsk_optimize(problem, opts);
local_assert(r1b.best_fitness == r1.best_fitness, 'egsk same seed: best_fitness differs');
local_assert(isequal(r1b.best_x, r1.best_x), 'egsk same seed: best_x differs');
local_assert(r1b.nfes == r1.nfes, 'egsk same seed: nfes differs');
local_assert(isequal(r1b.convergence.nfes, r1.convergence.nfes) && ...
    isequal(r1b.convergence.best_fitness, r1.convergence.best_fitness), ...
    'egsk same seed: convergence differs');

% A different seed changes the trajectory.
r1c = egsk_optimize(problem, struct('seed', 778));
local_assert(~isequal(r1c.convergence.best_fitness, r1.convergence.best_fitness), ...
    'egsk different seed: trajectory should differ');

% The use_fmincon=false opt-out runs, but is marked as non-reference.
r2 = egsk_optimize(problem, struct('seed', 777, 'use_fmincon', false));
local_check_contract(r2, problem, 'egsk', 777);
local_assert(contains(r2.notes, 'non-reference diagnostic'), ...
    sprintf('egsk: opt-out notes must mark non-reference mode (got "%s")', r2.notes));
local_assert(~r2.params.use_fmincon, 'egsk: opt-out params.use_fmincon must be false');
local_assert(r2.nfes == problem.max_nfes, ...
    sprintf('egsk: opt-out nfes must equal max_nfes (got %d)', r2.nfes));

fprintf('test_egsk_smoke: PASS\n');
end


function problem = local_sphere_problem(d, max_nfes, optimum, target_error)
%LOCAL_SPHERE_PROBLEM Sphere problem struct that follows the interface.
problem = struct();
problem.suite = 'sphere';
problem.func_id = 1;
problem.dim = d;
problem.lb = -100 * ones(1, d);
problem.ub = 100 * ones(1, d);
problem.optimum = optimum;
problem.evaluate = @(pop) sum(pop .^ 2, 2);
problem.max_nfes = max_nfes;
problem.target_error = target_error;
end


function local_check_contract(r, problem, name, expected_seed)
%LOCAL_CHECK_CONTRACT Check a result against docs/reference/matlab_interface.md.
expected = {'optimizer'; 'suite'; 'func_id'; 'dim'; 'seed'; 'best_x'; ...
    'best_fitness'; 'error'; 'nfes'; 'termination'; 'convergence'; ...
    'runtime_seconds'; 'params'; 'notes'};
local_assert(isequal(sort(fieldnames(r)), sort(expected)), ...
    sprintf('%s: result fields must match the interface exactly', name));
local_assert(strcmp(r.optimizer, name), sprintf('%s: wrong optimizer tag', name));
local_assert(strcmp(r.suite, problem.suite) && r.func_id == problem.func_id ...
    && r.dim == problem.dim, sprintf('%s: problem fields not copied', name));
local_assert(r.seed == expected_seed, sprintf('%s: seed not recorded correctly', name));
local_assert(isequal(size(r.best_x), [1 problem.dim]), sprintf('%s: best_x must be 1xD', name));
local_assert(isscalar(r.best_fitness) && isfinite(r.best_fitness), ...
    sprintf('%s: best_fitness must be finite scalar', name));
local_assert(any(strcmp(r.termination, {'max_evaluations', 'target_error_reached'})), ...
    sprintf('%s: bad termination value', name));
local_assert(ischar(r.notes), sprintf('%s: notes must be char', name));
local_assert(isstruct(r.params), sprintf('%s: params must be struct', name));
local_assert(isscalar(r.runtime_seconds) && r.runtime_seconds >= 0, ...
    sprintf('%s: bad runtime_seconds', name));

% Convergence trace (one record per generation).
c = r.convergence;
local_assert(isstruct(c) && isfield(c, 'nfes') && isfield(c, 'best_fitness'), ...
    sprintf('%s: convergence struct malformed', name));
local_assert(iscolumn(c.nfes) && iscolumn(c.best_fitness) && ...
    numel(c.nfes) == numel(c.best_fitness) && numel(c.nfes) >= 2, ...
    sprintf('%s: convergence arrays inconsistent', name));
local_assert(all(diff(c.nfes) > 0), sprintf('%s: convergence nfes must increase', name));
local_assert(all(diff(c.best_fitness) <= 0), ...
    sprintf('%s: convergence best_fitness must be nonincreasing', name));
local_assert(c.nfes(end) == r.nfes, ...
    sprintf('%s: last convergence nfes must equal result nfes', name));
local_assert(c.best_fitness(end) == r.best_fitness, ...
    sprintf('%s: last convergence best must equal best_fitness', name));

% best_x must reproduce best_fitness (the problem is deterministic).
bf = problem.evaluate(r.best_x);
local_assert(abs(bf - r.best_fitness) <= 1e-12 * max(1, abs(bf)), ...
    sprintf('%s: best_x does not reproduce best_fitness', name));

% Error = best_fitness - optimum (NaN if the optimum is unknown), zeroed
% when strictly below the target.
if isnan(problem.optimum)
    local_assert(isnan(r.error), sprintf('%s: error must be NaN for unknown optimum', name));
else
    raw = r.best_fitness - problem.optimum;
    if ~isnan(problem.target_error) && raw < problem.target_error
        local_assert(r.error == 0, sprintf('%s: error below target must be zeroed', name));
    else
        local_assert(r.error == raw, sprintf('%s: error field inconsistent', name));
    end
end
end


function local_assert(cond, message)
if ~cond
    error('test_egsk_smoke:failed', '%s', message);
end
end
