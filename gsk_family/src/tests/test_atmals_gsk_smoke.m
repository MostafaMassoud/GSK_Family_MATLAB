function test_atmals_gsk_smoke()
%TEST_ATMALS_GSK_SMOKE Smoke test for atmals-gsk under both protocols.
%
% Runs on a plain MATLAB sphere problem (no MEX) with the cec2017 (default)
% and cec2011 protocols, and checks:
%   - the result contract in docs/reference/matlab_interface.md,
%   - optimization progress and seed determinism,
%   - budget accounting when a generation crosses max_nfes (budget not a
%     multiple of NP, or below NP) under both protocols; the reported nfes
%     is clipped at max_nfes,
%   - fair-start X0 reuse with the post-X0 RNG restore,
%   - the cec2011 D == 1 senior-only branch,
%   - pool-override validation and convergence-array sanity.
% Raises error() on any failure.

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

% Budget is a multiple of NP = 100, so the run uses exactly max_nfes.
local_assert(r1.nfes == problem.max_nfes, ...
    sprintf('cec2017 nfes must equal max_nfes (got %d)', r1.nfes));
local_assert(strcmp(r1.termination, 'max_evaluations'), ...
    'termination must be max_evaluations (reference never stops early)');

% Progress: the best must be far below the median fitness of the optimizer's
% own initial population (its first RNG draw, repeated here).
np = r1.params.np;
rng(opts.seed, 'twister');
pop0 = repmat(problem.lb, np, 1) + rand(np, d) .* repmat(problem.ub - problem.lb, np, 1);
med0 = median(problem.evaluate(pop0));
local_assert(isfinite(r1.best_fitness) && r1.best_fitness < 1e-2 * med0, ...
    sprintf('insufficient progress: best=%g vs initial median=%g', r1.best_fitness, med0));

% The same seed reproduces the whole result.
r1b = atmals_gsk_optimize(problem, opts);
local_assert(r1b.best_fitness == r1.best_fitness, 'same seed: best_fitness differs');
local_assert(isequal(r1b.best_x, r1.best_x), 'same seed: best_x differs');
local_assert(r1b.nfes == r1.nfes, 'same seed: nfes differs');
local_assert(isequal(r1b.convergence.nfes, r1.convergence.nfes) && ...
    isequal(r1b.convergence.best_fitness, r1.convergence.best_fitness), ...
    'same seed: convergence differs');

% A different seed changes the trajectory.
r1c = atmals_gsk_optimize(problem, struct('seed', 20172));
local_assert(r1c.best_fitness ~= r1.best_fitness || ...
    ~isequal(r1c.convergence.best_fitness, r1.convergence.best_fitness), ...
    'different seed: trajectory should differ');

% For CEC2017 the reference code reports abs(best - optimum), not the signed
% error.
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

%% reference budget crossing: max_nfes not divisible by np = 100
% As in the reference code, the generation that crosses the budget is fully
% evaluated, but only the first max_nfes evaluations are counted and may
% update the best-so-far. The internal counter ends at max_nfes+1; the
% reported nfes (result.nfes, convergence.nfes) is clipped at max_nfes.
% Every evaluation is logged, so the expected best is exact and does not
% depend on the RNG.
for proto = {'cec2017', 'cec2011'}
    pX = local_sphere_problem(d, 1050, 0, 1e-8);
    pX.evaluate = @(pop) local_logged_sphere(pop);
    local_logged_sphere([], 'reset');
    rX = atmals_gsk_optimize(pX, struct('seed', 20197, 'protocol', proto{1}));
    logged = local_logged_sphere([], 'get');
    local_check_contract(rX, pX, 'atmals-gsk', 20197);
    local_assert(rX.nfes == pX.max_nfes, ...
        sprintf('%s crossing: reported nfes must be clipped at max_nfes (got %d)', proto{1}, rX.nfes));
    local_assert(isequal(rX.convergence.nfes, [100:100:1000, 1050]'), ...
        sprintf('%s crossing: expected 10 full records plus one clipped crossing record', proto{1}));
    local_assert(numel(logged) == 1100, ...
        sprintf('%s crossing: the crossing generation must be evaluated in full', proto{1}));
    local_assert(rX.best_fitness == min(logged(1:pX.max_nfes)), ...
        sprintf('%s crossing: best-so-far must only count the first max_nfes evaluations', proto{1}));
    local_assert(min(logged(1:pX.max_nfes)) ~= min(logged), ...
        sprintf('%s crossing: fixture must have its overall best among the uncounted children', proto{1}));
end

% Budget below NP: only the initial population is evaluated, and only its
% first max_nfes individuals are counted and may update the best-so-far.
pS = local_sphere_problem(d, 50, 0, 1e-8);
pS.evaluate = @(pop) local_logged_sphere(pop);
local_logged_sphere([], 'reset');
rS = atmals_gsk_optimize(pS, struct('seed', 20175));
logged = local_logged_sphere([], 'get');
local_assert(rS.nfes == 50 && isequal(rS.convergence.nfes, 50), ...
    sprintf('below-NP budget: reported nfes must be clipped at max_nfes (got %d)', rS.nfes));
local_assert(numel(logged) == np && rS.best_fitness == min(logged(1:50)) && ...
    min(logged(1:50)) ~= min(logged), ...
    'below-NP budget: best-so-far must only count the first max_nfes initial evaluations');

%% fair-start X0 reuse (unified protocol): runner-drawn X0 + post-X0 RNG state
pF = local_sphere_problem(d, 2000, 0, 1e-8);
rng(20176, 'twister');
X0 = gsk_init_population(np, pF.lb, pF.ub);
st = rng;
oF = struct('seed', 1, 'initial_population', X0, 'rng_state_after_initialization', st);
rF = atmals_gsk_optimize(pF, oF);
local_check_contract(rF, pF, 'atmals-gsk', 1);
local_assert(rF.convergence.best_fitness(1) == min(pF.evaluate(X0)), ...
    'fair start: the initial record must come from the supplied X0');
% X0 plus the restored state exactly replaces the optimizer's own seeded
% draw: the run must equal a plain seeded run whose first draw is that X0.
rSeed = atmals_gsk_optimize(pF, struct('seed', 20176));
local_assert(isequal(rF.best_x, rSeed.best_x) && ...
    isequal(rF.convergence.best_fitness, rSeed.convergence.best_fitness), ...
    'fair start: X0 + post-X0 RNG state must reproduce the seeded run that drew X0');
% Once the state is restored, the optimizer seed no longer matters.
oF2 = oF;
oF2.seed = 2;
rF2 = atmals_gsk_optimize(pF, oF2);
local_assert(isequal(rF2.best_x, rF.best_x) && ...
    isequal(rF2.convergence.best_fitness, rF.convergence.best_fitness), ...
    'fair start: the restored post-X0 state must override the optimizer seed stream');
% Guard: X0 without a captured RNG state keeps the optimizer's own stream.
rG = atmals_gsk_optimize(pF, struct('seed', 1, 'initial_population', X0));
local_assert(rG.convergence.best_fitness(1) == rF.convergence.best_fitness(1) && ...
    ~isequal(rG.convergence.best_fitness, rF.convergence.best_fitness), ...
    'fair start: X0 without an RNG state must use X0 but not jump streams');

%% protocol 'cec2011', D == 1: dedicated senior-only branch
p1 = local_sphere_problem(1, 3000, NaN, NaN);
o1 = struct('seed', 20177, 'protocol', 'cec2011');
r1d = atmals_gsk_optimize(p1, o1);
local_check_contract(r1d, p1, 'atmals-gsk', o1.seed);
local_assert(r1d.nfes == p1.max_nfes && numel(r1d.convergence.nfes) == p1.max_nfes / np, ...
    sprintf('cec2011 D==1: nfes/records off (nfes=%d, records=%d)', r1d.nfes, numel(r1d.convergence.nfes)));
rng(o1.seed, 'twister');
pop0 = repmat(p1.lb, np, 1) + rand(np, 1) .* repmat(p1.ub - p1.lb, np, 1);
local_assert(r1d.best_fitness < 1e-2 * median(p1.evaluate(pop0)), ...
    sprintf('cec2011 D==1: insufficient progress (best=%g)', r1d.best_fitness));
r1e = atmals_gsk_optimize(p1, o1);
local_assert(r1e.best_fitness == r1d.best_fitness && isequal(r1e.best_x, r1d.best_x) && ...
    isequal(r1e.convergence.best_fitness, r1d.convergence.best_fitness), ...
    'cec2011 D==1 same seed: result differs');
% This branch hard-codes KF = 0.5 and KR = 0.9 and has no junior phase, so
% the adaptive KF/KR/K picks (one roulette draw each, whatever the pool) do
% not affect it: overriding those pools must not change the trajectory ...
pools_kfk = {'kf_pool', [0.3 0.5 0.7], 'kr_pool', [0.9 0.95], 'k_pool', [10 20]};
o1p = o1;
o17 = struct('seed', o1.seed);
o17p = o17;
for i = 1:2:numel(pools_kfk)
    o1p.(pools_kfk{i}) = pools_kfk{i + 1};
    o17p.(pools_kfk{i}) = pools_kfk{i + 1};
end
r1p = atmals_gsk_optimize(p1, o1p);
local_assert(isequal(r1p.best_x, r1d.best_x) && ...
    isequal(r1p.convergence.best_fitness, r1d.convergence.best_fitness), ...
    'cec2011 D==1: the senior-only branch must ignore the adaptive KF/KR/K');
% ... while the general GSK branch (cec2017 protocol, same D == 1) uses them
r17a = atmals_gsk_optimize(p1, o17);
r17b = atmals_gsk_optimize(p1, o17p);
local_assert(~isequal(r17a.convergence.best_fitness, r17b.convergence.best_fitness), ...
    'control: the general branch must react to the KF/KR/K pools');

%% overridden pools must contain the hard-coded initial picks
bad_pools = {'kf_pool', [0.3 0.4 0.6 0.7]; 'kr_pool', [0.85 0.95 1]; 'k_pool', 1:5; ...
    'p_pool', [0.05 0.15]; 'pls_pool', [1.5 2]};
for i = 1:size(bad_pools, 1)
    threw = false;
    try
        atmals_gsk_optimize(pF, struct('seed', 3, bad_pools{i, 1}, bad_pools{i, 2}));
    catch err
        threw = strcmp(err.identifier, 'atmals_gsk:options') && contains(err.message, bad_pools{i, 1});
    end
    local_assert(threw, sprintf('%s lacking its initial pick must raise atmals_gsk:options', bad_pools{i, 1}));
end
% an override that contains the initial pick still runs
rP = atmals_gsk_optimize(pF, struct('seed', 3, 'kf_pool', [0.3 0.5 0.7]));
local_check_contract(rP, pF, 'atmals-gsk', 3);
local_assert(isequal(rP.params.kf_pool, [0.3 0.5 0.7]), 'kf_pool override not honored');

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
%LOCAL_SPHERE_PROBLEM Sphere problem struct in the standard problem format.
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


function f = local_logged_sphere(pop, cmd)
%LOCAL_LOGGED_SPHERE Sphere objective that logs every fitness it computes.
% The log keeps call order. local_logged_sphere([], 'reset') clears it and
% local_logged_sphere([], 'get') returns it.
persistent log_f
if nargin > 1
    if strcmp(cmd, 'reset')
        log_f = zeros(0, 1);
    end
    f = log_f;
    return;
end
f = sum(pop .^ 2, 2);
log_f = [log_f; f];
end


function local_check_contract(r, problem, name, expected_seed)
%LOCAL_CHECK_CONTRACT Check r against docs/reference/matlab_interface.md.
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

% Convergence records (one per generation)
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

% best_x must reproduce best_fitness (the problem is deterministic)
bf = problem.evaluate(r.best_x);
local_assert(abs(bf - r.best_fitness) <= 1e-12 * max(1, abs(bf)), ...
    sprintf('%s: best_x does not reproduce best_fitness', name));

% Error field: NaN for an unknown optimum, 0 below target_error, otherwise
% best - optimum (abs(best - optimum) for atmals-gsk on cec2017).
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
%LOCAL_ASSERT Raise an error when cond is false.
if ~cond
    error('test_atmals_gsk_smoke:failed', '%s', message);
end
end
