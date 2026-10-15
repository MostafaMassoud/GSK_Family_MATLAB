function test_fdb_agsk_smoke()
%TEST_FDB_AGSK_SMOKE Smoke test for fdb-agsk on a pure-MATLAB
%sphere problem (matching the reference's own sphere harness).
%
% Runs the default configuration (case 1, np_init = 100 in this interface),
% then all five FDB cases briefly, and checks that an invalid case raises.
% Raises error() on any failure.
%
% Note: the brief case runs keep np_init = 100 so they exercise all cases
% quickly while staying close to the current interface default.

here = fileparts(mfilename('fullpath'));
src_root = fileparts(here);
addpath(fullfile(src_root, 'common'));
addpath(fullfile(src_root, 'optimizers', 'fdb-agsk'));

d = 10;

%% default configuration: case 1, current interface np_init = 100
problem = local_sphere_problem(d, 10000, 0, 1e-8);
opts = struct('seed', 555);

r1 = fdb_agsk_optimize(problem, opts);
local_check_contract(r1, problem, 'fdb-agsk', opts.seed);
local_assert(r1.params.fdb_case == 1, 'default fdb_case must be 1');
local_assert(r1.params.np_init == 100, 'default np_init must be 100');

% reference counter semantics: the per-child counter reads max_nfes+1 when
% a generation crosses the budget mid-population (population reduction
% makes the per-generation increments uneven); the reported copies
% (result.nfes, convergence.nfes) are clipped at max_nfes
local_assert(r1.nfes == problem.max_nfes, ...
    sprintf('fdb-agsk: reported nfes must be clipped at max_nfes (got %d)', r1.nfes));
local_assert(strcmp(r1.termination, 'max_evaluations'), ...
    'termination must be max_evaluations (reference never stops early)');

% optimization progress: well below the median fitness of the optimizer's
% own initial population (its first RNG draw, replicated here)
np = r1.params.np_init;
rng(opts.seed, 'twister');
pop0 = repmat(problem.lb, np, 1) + rand(np, d) .* repmat(problem.ub - problem.lb, np, 1);
med0 = median(problem.evaluate(pop0));
local_assert(isfinite(r1.best_fitness) && r1.best_fitness < 1e-2 * med0, ...
    sprintf('insufficient progress: best=%g vs initial median=%g', r1.best_fitness, med0));

% determinism: same seed reproduces everything
r1b = fdb_agsk_optimize(problem, opts);
local_assert(r1b.best_fitness == r1.best_fitness, 'same seed: best_fitness differs');
local_assert(isequal(r1b.best_x, r1.best_x), 'same seed: best_x differs');
local_assert(r1b.nfes == r1.nfes, 'same seed: nfes differs');
local_assert(isequal(r1b.convergence.nfes, r1.convergence.nfes) && ...
    isequal(r1b.convergence.best_fitness, r1.convergence.best_fitness), ...
    'same seed: convergence differs');

% different seed changes the trajectory
r1c = fdb_agsk_optimize(problem, struct('seed', 556));
local_assert(~isequal(r1c.convergence.best_fitness, r1.convergence.best_fitness), ...
    'different seed: trajectory should differ');

%% all five cases, brief budgets, distinct seeds
problem_brief = local_sphere_problem(d, 3000, 0, 1e-8);
for c = 1:5
    oc = struct('seed', 9000 + c, 'fdb_case', c, 'np_init', 100);
    rc = fdb_agsk_optimize(problem_brief, oc);
    local_check_contract(rc, problem_brief, 'fdb-agsk', oc.seed);
    local_assert(rc.params.fdb_case == c, sprintf('case %d: params.fdb_case wrong', c));
    local_assert(rc.nfes == problem_brief.max_nfes, ...
        sprintf('case %d: reported nfes must be clipped at max_nfes (got %d)', c, rc.nfes));
    rng(oc.seed, 'twister');
    pop0 = repmat(problem_brief.lb, 100, 1) + rand(100, d) .* repmat(problem_brief.ub - problem_brief.lb, 100, 1);
    med0 = median(problem_brief.evaluate(pop0));
    local_assert(rc.best_fitness < 1e-2 * med0, ...
        sprintf('case %d: insufficient progress: best=%g vs initial median=%g', ...
        c, rc.best_fitness, med0));
end

%% invalid case must raise
threw = false;
try
    fdb_agsk_optimize(problem_brief, struct('seed', 1, 'fdb_case', 6));
catch err
    threw = true;
    local_assert(strcmp(err.identifier, 'fdb_agsk:invalid_case'), ...
        sprintf('unexpected error identifier: %s', err.identifier));
end
local_assert(threw, 'fdb_case = 6 must raise an error');

%% min_pop_size >= 11 floor (P = 0.05 senior partition needs NP >= 11)
r11 = fdb_agsk_optimize(problem_brief, struct('seed', 3, 'min_pop_size', 11));
local_assert(r11.nfes == problem_brief.max_nfes, 'min_pop_size = 11 must run to budget');
bad = {struct('seed', 3, 'min_pop_size', 10), struct('seed', 3, 'min_pop_size', 4), ...
       struct('seed', 3, 'np_init', 10, 'min_pop_size', 10)};
for k = 1:numel(bad)
    threw = false;
    try
        fdb_agsk_optimize(problem_brief, bad{k});
    catch err
        threw = strcmp(err.identifier, 'fdb_agsk_optimize:options');
    end
    local_assert(threw, sprintf('invalid population sizes (case %d) must be rejected', k));
end

fprintf('test_fdb_agsk_smoke: PASS\n');
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
    error('test_fdb_agsk_smoke:failed', '%s', message);
end
end
