function test_apgsk_smoke()
%TEST_APGSK_SMOKE Smoke test for apgsk_optimize on a pure-MATLAB sphere problem.
%
% Uses D = 5 with the current interface default NP = 100 so the test stays
% fast. Checks the docs/reference/matlab_interface.md result contract, that optimization
% actually happened, budget accounting, convergence consistency, and
% seed-determinism. Raises error() on any failure.

d = 5;
% max_nfes = 10000 keeps NP < 0.1*max_nfes so the initial KW phase exists,
% as in the reference protocols
problem = local_sphere_problem(d, 10000);

r1 = apgsk_optimize(problem, struct('seed', 42));
local_check_contract(r1, problem, 'apgsk');
local_assert(r1.params.np_init == 100, 'apgsk: default np_init must be 100');

rng(99, 'twister');
rand_pop = repmat(problem.lb, 200, 1) + ...
    rand(200, d) .* repmat(problem.ub - problem.lb, 200, 1);
med = median(problem.evaluate(rand_pop));
local_assert(isfinite(r1.best_fitness) && r1.best_fitness < med, ...
    'apgsk: best_fitness must beat a random population median');

% budget semantics: either the full clipped budget was consumed, or the
% run stopped early on the target with the error zeroed
if strcmp(r1.termination, 'max_evaluations')
    local_assert(r1.nfes == problem.max_nfes, ...
        'apgsk: budget exit must consume the full clipped budget');
else
    local_assert(r1.error == 0, 'apgsk: target exit must zero the error');
end

% determinism: same seed must reproduce everything bit-for-bit
r2 = apgsk_optimize(problem, struct('seed', 42));
local_assert(r2.best_fitness == r1.best_fitness, 'apgsk: same seed, best_fitness differs');
local_assert(r2.nfes == r1.nfes, 'apgsk: same seed, nfes differs');
local_assert(isequal(r2.best_x, r1.best_x), 'apgsk: same seed, best_x differs');
local_assert(isequal(r2.convergence.nfes, r1.convergence.nfes) && ...
    isequal(r2.convergence.best_fitness, r1.convergence.best_fitness), ...
    'apgsk: same seed, convergence differs');

% different seed must (almost surely) change the trajectory
r3 = apgsk_optimize(problem, struct('seed', 43));
local_assert(r3.best_fitness ~= r1.best_fitness, ...
    'apgsk: different seed should change best_fitness');

end


function problem = local_sphere_problem(d, max_nfes)
%LOCAL_SPHERE_PROBLEM Interface-conformant sphere problem struct.
problem = struct();
problem.suite = 'sphere';
problem.func_id = 1;
problem.dim = d;
problem.lb = -100 * ones(1, d);
problem.ub = 100 * ones(1, d);
problem.optimum = 0;
problem.evaluate = @(pop) sum(pop .^ 2, 2);
problem.max_nfes = max_nfes;
problem.target_error = 1e-8;
end


function local_check_contract(r, problem, name)
%LOCAL_CHECK_CONTRACT Assert the docs/reference/matlab_interface.md result fields.
fields = {'optimizer', 'suite', 'func_id', 'dim', 'seed', 'best_x', ...
    'best_fitness', 'error', 'nfes', 'termination', 'convergence', ...
    'runtime_seconds', 'params', 'notes'};
for i = 1:numel(fields)
    local_assert(isfield(r, fields{i}), ...
        sprintf('%s: missing result field %s', name, fields{i}));
end
local_assert(strcmp(r.optimizer, name), sprintf('%s: wrong optimizer tag', name));
local_assert(strcmp(r.suite, problem.suite) && r.func_id == problem.func_id ...
    && r.dim == problem.dim, sprintf('%s: problem fields not copied', name));
local_assert(isequal(size(r.best_x), [1 problem.dim]), ...
    sprintf('%s: best_x must be 1xD', name));
local_assert(isfinite(r.best_fitness), sprintf('%s: best_fitness not finite', name));
local_assert(r.nfes <= problem.max_nfes, sprintf('%s: nfes exceeds budget', name));
local_assert(any(strcmp(r.termination, {'max_evaluations', 'target_error_reached'})), ...
    sprintf('%s: bad termination value', name));
local_assert(ischar(r.notes), sprintf('%s: notes must be char', name));
local_assert(isstruct(r.params), sprintf('%s: params must be struct', name));
local_assert(r.runtime_seconds >= 0, sprintf('%s: bad runtime', name));

c = r.convergence;
local_assert(isstruct(c) && isfield(c, 'nfes') && isfield(c, 'best_fitness'), ...
    sprintf('%s: convergence struct malformed', name));
local_assert(numel(c.nfes) == numel(c.best_fitness) && ~isempty(c.nfes), ...
    sprintf('%s: convergence arrays inconsistent', name));
local_assert(all(diff(c.nfes) >= 0), ...
    sprintf('%s: convergence nfes must be nondecreasing', name));
local_assert(all(diff(c.best_fitness) <= 0), ...
    sprintf('%s: convergence best_fitness must be nonincreasing', name));
local_assert(c.nfes(end) == r.nfes, ...
    sprintf('%s: last convergence nfes must equal result nfes', name));
local_assert(c.best_fitness(end) == r.best_fitness, ...
    sprintf('%s: last convergence best must equal best_fitness', name));

bf = problem.evaluate(r.best_x);
local_assert(abs(bf - r.best_fitness) <= 1e-12 * max(1, abs(bf)), ...
    sprintf('%s: best_x does not reproduce best_fitness', name));

if r.error ~= 0
    local_assert(abs(r.error - (r.best_fitness - problem.optimum)) <= 1e-12, ...
        sprintf('%s: error field inconsistent', name));
end
end


function local_assert(cond, message)
if ~cond
    error('test_apgsk_smoke:failed', '%s', message);
end
end
