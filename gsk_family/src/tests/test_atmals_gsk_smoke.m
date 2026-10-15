function test_atmals_gsk_smoke()
%TEST_ATMALS_GSK_SMOKE Smoke test for atmals-gsk on a pure-MATLAB
%sphere problem, exercising both reference protocols.
%
% Checks the docs/reference/matlab_interface.md result contract, optimization
% progress, reference budget-crossing accounting, convergence-array sanity,
% and seed determinism. Raises error() on any failure.

here = fileparts(mfilename('fullpath'));
src_root = fileparts(here);
addpath(fullfile(src_root, 'common'));
addpath(fullfile(src_root, 'optimizers', 'atmals-gsk'));

d = 10;

%% protocol 'cec2017' (default), known optimum
problem = local_sphere_problem(d, 10000, 0, 1e-8);
opts = struct('seed', 20171);

r1 = atmals_gsk_optimize(problem, opts);
local_check_contract(r1, problem, 'atmals-gsk', opts.seed);
local_assert(strcmp(r1.params.protocol, 'cec2017'), 'default protocol must be cec2017');
local_assert(strcmp(r1.notes, ''), 'atmals-gsk notes must be empty');

% reference counter semantics: budget divisible by np=100 -> exactly consumed
local_assert(r1.nfes == problem.max_nfes, ...
    sprintf('cec2017 nfes must equal max_nfes (got %d)', r1.nfes));
local_assert(strcmp(r1.termination, 'max_evaluations'), ...
    'termination must be max_evaluations (reference never stops early)');

% optimization progress: well below the median fitness of the optimizer's
% own initial population (its first RNG draw, replicated here)
np = r1.params.np;
rng(opts.seed, 'twister');
pop0 = repmat(problem.lb, np, 1) + rand(np, d) .* repmat(problem.ub - problem.lb, np, 1);
med0 = median(problem.evaluate(pop0));
local_assert(isfinite(r1.best_fitness) && r1.best_fitness < 1e-2 * med0, ...
    sprintf('insufficient progress: best=%g vs initial median=%g', r1.best_fitness, med0));

% determinism: same seed reproduces everything
r1b = atmals_gsk_optimize(problem, opts);
local_assert(r1b.best_fitness == r1.best_fitness, 'same seed: best_fitness differs');
local_assert(isequal(r1b.best_x, r1.best_x), 'same seed: best_x differs');
local_assert(r1b.nfes == r1.nfes, 'same seed: nfes differs');
local_assert(isequal(r1b.convergence.nfes, r1.convergence.nfes) && ...
    isequal(r1b.convergence.best_fitness, r1.convergence.best_fitness), ...
    'same seed: convergence differs');

% different seed changes the trajectory
r1c = atmals_gsk_optimize(problem, struct('seed', 20172));
local_assert(r1c.best_fitness ~= r1.best_fitness || ...
    ~isequal(r1c.convergence.best_fitness, r1.convergence.best_fitness), ...
    'different seed: trajectory should differ');

% CEC2017 reference reporting uses abs(best - optimum), not signed error.
problem17 = local_sphere_problem(2, 200, 100, 1e-8);
problem17.suite = 'cec2017';
problem17.evaluate = @(pop) zeros(size(pop, 1), 1);
r17 = atmals_gsk_optimize(problem17, struct('seed', 20174));
local_check_contract(r17, problem17, 'atmals-gsk', 20174);
local_assert(r17.error == 100, ...
    sprintf('cec2017 error must be abs(best - optimum), got %.16g', r17.error));

%% protocol 'cec2011', unknown optimum (the cec2011 reference case)
problem11 = local_sphere_problem(d, 5000, NaN, NaN);
opts11 = struct('seed', 20113, 'protocol', 'cec2011');

r2 = atmals_gsk_optimize(problem11, opts11);
local_check_contract(r2, problem11, 'atmals-gsk', opts11.seed);
local_assert(strcmp(r2.params.protocol, 'cec2011'), 'protocol option not honored');
local_assert(isnan(r2.error), 'cec2011/NaN-optimum run must report error = NaN');
local_assert(r2.nfes == problem11.max_nfes, ...
    sprintf('cec2011 nfes must equal max_nfes (got %d)', r2.nfes));

rng(opts11.seed, 'twister');
pop0 = repmat(problem11.lb, np, 1) + rand(np, d) .* repmat(problem11.ub - problem11.lb, np, 1);
med0 = median(problem11.evaluate(pop0));
local_assert(r2.best_fitness < 1e-2 * med0, ...
    sprintf('cec2011 insufficient progress: best=%g vs initial median=%g', r2.best_fitness, med0));

r2b = atmals_gsk_optimize(problem11, opts11);
local_assert(r2b.best_fitness == r2.best_fitness && isequal(r2b.best_x, r2.best_x), ...
    'cec2011 same seed: result differs');

%% invalid protocol must raise
threw = false;
try
    atmals_gsk_optimize(problem, struct('seed', 1, 'protocol', 'cec9999'));
catch
    threw = true;
end
local_assert(threw, 'invalid protocol must raise an error');

fprintf('test_atmals_gsk_smoke: PASS\n');
end


function problem = local_sphere_problem(d, max_nfes, optimum, target_error)
%LOCAL_SPHERE_PROBLEM Interface-conformant sphere problem struct.
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
%LOCAL_CHECK_CONTRACT Assert the docs/reference/matlab_interface.md result contract.
expected = {'optimizer'; 'suite'; 'func_id'; 'dim'; 'seed'; 'best_x'; ...
    'best_fitness'; 'error'; 'nfes'; 'termination'; 'convergence'; ...
    'runtime_seconds'; 'params'; 'notes'};
local_assert(isequal(sort(fieldnames(r)), sort(expected)), ...
    sprintf('%s: result fields must match the interface exactly', name));
local_assert(strcmp(r.optimizer, name), sprintf('%s: wrong optimizer tag', name));
local_assert(strcmp(r.suite, problem.suite) && r.func_id == problem.func_id ...
    && r.dim == problem.dim, sprintf('%s: problem fields not copied', name));
local_assert(isequal(size(r.best_x), [1 problem.dim]), sprintf('%s: best_x must be 1xD', name));
local_assert(isscalar(r.best_fitness) && isfinite(r.best_fitness), ...
    sprintf('%s: best_fitness must be finite scalar', name));
local_assert(any(strcmp(r.termination, {'max_evaluations', 'target_error_reached'})), ...
    sprintf('%s: bad termination value', name));
local_assert(ischar(r.notes), sprintf('%s: notes must be char', name));
local_assert(isstruct(r.params), sprintf('%s: params must be struct', name));
local_assert(isscalar(r.runtime_seconds) && r.runtime_seconds >= 0, ...
    sprintf('%s: bad runtime_seconds', name));
local_assert(r.seed == expected_seed, sprintf('%s: seed not recorded correctly', name));

% convergence sanity (per-generation records)
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

% best_x must reproduce best_fitness on this deterministic problem
bf = problem.evaluate(r.best_x);
local_assert(abs(bf - r.best_fitness) <= 1e-12 * max(1, abs(bf)), ...
    sprintf('%s: best_x does not reproduce best_fitness', name));

% error semantics
if isnan(problem.optimum)
    local_assert(isnan(r.error), sprintf('%s: error must be NaN for unknown optimum', name));
elseif strcmp(name, 'atmals-gsk') && strcmp(problem.suite, 'cec2017')
    raw = abs(r.best_fitness - problem.optimum);
    if ~isnan(problem.target_error) && raw < problem.target_error
        local_assert(r.error == 0, sprintf('%s: cec2017 error below target must be zeroed', name));
    else
        local_assert(r.error == raw, sprintf('%s: cec2017 absolute error inconsistent', name));
    end
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
    error('test_atmals_gsk_smoke:failed', '%s', message);
end
end
