function test_agsk_smoke()
%TEST_AGSK_SMOKE Smoke test for agsk_optimize on a pure-MATLAB sphere problem.
%
% Checks the docs/reference/matlab_interface.md result contract, that optimization
% actually happened, budget accounting, convergence consistency,
% seed-determinism, the target-error semantics of both exits (target stop
% zeroes, budget exit reports raw), and the min_pop_size >= 11 floor.
% Raises error() on any failure.

d = 10;
% np_init default = 100 (< 0.1*max_nfes so the initial KW phase exists,
% as in the reference protocols)
problem = local_sphere_problem(d, 8000);

r1 = agsk_optimize(problem, struct('seed', 42));
local_check_contract(r1, problem, 'agsk');

rng(99, 'twister');
rand_pop = repmat(problem.lb, 200, 1) + ...
    rand(200, d) .* repmat(problem.ub - problem.lb, 200, 1);
med = median(problem.evaluate(rand_pop));
local_assert(isfinite(r1.best_fitness) && r1.best_fitness < med, ...
    'agsk: best_fitness must beat a random population median');

% budget semantics: either the full clipped budget was consumed, or the
% run stopped early on the target with the error zeroed
if strcmp(r1.termination, 'max_evaluations')
    local_assert(r1.nfes == problem.max_nfes, ...
        'agsk: budget exit must consume the full clipped budget');
else
    local_assert(r1.error == 0, 'agsk: target exit must zero the error');
end

% determinism: same seed must reproduce everything bit-for-bit
r2 = agsk_optimize(problem, struct('seed', 42));
local_assert(r2.best_fitness == r1.best_fitness, 'agsk: same seed, best_fitness differs');
local_assert(r2.nfes == r1.nfes, 'agsk: same seed, nfes differs');
local_assert(isequal(r2.best_x, r1.best_x), 'agsk: same seed, best_x differs');
local_assert(isequal(r2.convergence.nfes, r1.convergence.nfes) && ...
    isequal(r2.convergence.best_fitness, r1.convergence.best_fitness), ...
    'agsk: same seed, convergence differs');

% different seed must (almost surely) change the trajectory
r3 = agsk_optimize(problem, struct('seed', 43));
local_assert(r3.best_fitness ~= r1.best_fitness, ...
    'agsk: different seed should change best_fitness');

% reference dimension rule can be requested explicitly (40*D for D > 5)
r4 = agsk_optimize(problem, struct('seed', 42, 'np_init', 40 * d));
local_check_contract(r4, problem, 'agsk');
local_assert(r4.params.np_init == 40 * d, 'agsk: np_init option not honored');

% both target branches, independent of how close the default fixture gets:
% an easy target stops early with the error zeroed ...
problem_t = problem;
problem_t.target_error = 1e3;
rt = agsk_optimize(problem_t, struct('seed', 42));
local_check_contract(rt, problem_t, 'agsk');
local_assert(strcmp(rt.termination, 'target_error_reached') && rt.error == 0 && ...
    rt.nfes < problem_t.max_nfes, 'agsk: easy target must stop early with the error zeroed');
% ... and a budget too small to reach 1e-8 exits on the budget with the raw error
problem_b = local_sphere_problem(d, 2000);
rb = agsk_optimize(problem_b, struct('seed', 42));
local_check_contract(rb, problem_b, 'agsk');
local_assert(strcmp(rb.termination, 'max_evaluations') && rb.nfes == problem_b.max_nfes && ...
    rb.error == rb.best_fitness - problem_b.optimum && rb.error ~= 0, ...
    'agsk: budget exit must consume the budget and report the raw (unzeroed) error');

% population floor: the P = 0.05 senior partition needs NP >= 11, so the
% smallest valid min_pop_size runs and anything below is rejected up front
r11 = agsk_optimize(local_sphere_problem(d, 3000), struct('seed', 7, 'min_pop_size', 11));
local_check_contract(r11, local_sphere_problem(d, 3000), 'agsk');
bad = {struct('seed', 7, 'min_pop_size', 10), struct('seed', 7, 'min_pop_size', 4), ...
    struct('seed', 7, 'np_init', 10, 'min_pop_size', 10), struct('seed', 7, 'np_init', 11)};
for i = 1:numel(bad)
    threw = false;
    try
        agsk_optimize(local_sphere_problem(d, 3000), bad{i});
    catch err
        threw = strcmp(err.identifier, 'agsk_optimize:options');
    end
    local_assert(threw, sprintf('agsk: invalid population sizes %s must raise agsk_optimize:options', ...
        jsonencode(bad{i})));
end

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

% error semantics (reference): zeroed only by the per-generation target
% stop; a budget exit reports the raw error (no end-of-run zeroing)
if isnan(problem.optimum)
    local_assert(isnan(r.error), sprintf('%s: error must be NaN for unknown optimum', name));
else
    raw = r.best_fitness - problem.optimum;
    if strcmp(r.termination, 'target_error_reached')
        local_assert(~isnan(problem.target_error) && raw < problem.target_error, ...
            sprintf('%s: target stop requires the raw error strictly below target', name));
        local_assert(r.error == 0, sprintf('%s: target exit must zero the error', name));
    else
        local_assert(r.error == raw, ...
            sprintf('%s: budget exit must report the raw error (no end-of-run zeroing)', name));
        if ~isnan(problem.target_error) && numel(c.nfes) >= 2
            local_assert(raw >= problem.target_error, ...
                sprintf('%s: raw error below target on a budget exit (target stop did not fire)', name));
        end
    end
end
end


function local_assert(cond, message)
if ~cond
    error('test_agsk_smoke:failed', '%s', message);
end
end
