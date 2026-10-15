function result = gsk_optimize(problem, options)
%GSK_OPTIMIZE Baseline Gaining-Sharing Knowledge based optimizer (GSK).
%
%   result = gsk_optimize(problem, options)
%
% Faithful MATLAB port of the reference implementation:
%   primary      : historical source: gsk/gsk/GSK_Enhanced.m
%   cross-check  : historical source: atmalsgsk/atmalsgsk/cec2017/GSK.m
%                  (original algorithmic form, plus the
%                  Gained_Shared_Junior_R1R2R3.m /
%                  Gained_Shared_Senior_R1R2R3.m helpers next to it)
%
% problem/options/result contracts: docs/reference/matlab_interface.md.
% Reference behaviors preserved (G_Max derivation, budget-crossing
% semantics, target-error semantics, random draw order) are documented in
% src/optimizers/gsk/README.md.
%
% Reference defaults: NP = 100, KF = 0.5, KR = 0.9, K = 10, P = 0.1.

if ~isfield(options, 'seed') || isempty(options.seed)
    error('gsk_optimize:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % direct-call default 'twister'; selects threefry|twister|seed|state

np = local_option(options, 'np', 100);
kf = local_option(options, 'kf', 0.5);
kr = local_option(options, 'kr', 0.9);
k_rate = local_option(options, 'k', 10);
p_part = local_option(options, 'p', 0.1);

dim = problem.dim;
lb = problem.lb;
ub = problem.ub;
max_nfes = problem.max_nfes;

t_start = tic;

% Reference G_Max derivation (GSK_Enhanced.m / GSK.m):
%   G_Max = fix(max_nfes / pop_size)
% i.e. derived from the full budget including the initialization
% evaluations; the junior-dimension schedule is driven by the generation
% counter g against this G_Max.
g_max = fix(max_nfes / np);

% ----- population initialization (one rand(NP, D) draw, or runner X0) -----
% Reference/reproduction runs do not pass X0, so this remains the original
% one-draw initialization. Unified fair-comparison runs pass the runner-drawn
% X0 plus the post-X0 RNG state; accepting both here lets every optimizer start
% from the same population and same next random number for the same CEC cell.
popold = gsk_initial_population_from_options(options, np, lb, ub);
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop);
fitness = fitness(:);

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = zeros(1, dim);

% Initial best-so-far scan. The reference counts at most max_nfes
% evaluations (sequential scan with strict-< update, first minimum wins);
% GSK_Enhanced clips the counter with min(pop_size, max_nfes - nfes).
% best_x tracking here is an output-only extension (the reference only
% records bsf_solution inside the generation loop; see README).
n_init = min(np, max_nfes - nfes);
if n_init > 0
    [init_min, init_idx] = min(fitness(1:n_init));
    if init_min < bsf_fit_var
        bsf_fit_var = init_min;
        bsf_solution = pop(init_idx, :);
    end
    nfes = nfes + n_init;
end

% Reference parameter settings: K = 10*ones(pop_size, 1).
k_vec = k_rate * ones(np, 1);

% Convergence recording: one row after initialization (generation 0) and
% one row per generation (interface coarsening of the reference
% per-evaluation run_funcvals; see README).
max_rows = ceil(max_nfes / np) + 2;
conv_nfes = zeros(max_rows, 1);
conv_best = zeros(max_rows, 1);
n_conv = 1;
conv_nfes(n_conv) = nfes;
conv_best(n_conv) = bsf_fit_var;

g = 0;

% ----- main loop -----
while nfes < max_nfes
    g = g + 1;

    % Junior dimensionality schedule (generation ratio, exponent K):
    %   D_Gained_Shared_Junior = ceil(D * (1 - g/G_Max).^K)
    D_Gained_Shared_Junior = ceil(dim * (1 - g / g_max) .^ k_vec);

    pop = popold;

    [~, indBest] = sort(fitness, 'ascend');
    [Rg1, Rg2, Rg3] = Gained_Shared_Junior_R1R2R3(indBest);
    [R1, R2, R3] = Gained_Shared_Senior_R1R2R3(indBest, p_part);

    % ----- junior gaining-sharing (better/worse branching on Rg3) -----
    R01 = 1:np;
    Gained_Shared_Junior = zeros(np, dim);
    ind1 = fitness(R01) > fitness(Rg3);
    if sum(ind1) > 0
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + kf .* ...
            (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(Rg3(ind1), :) - pop(ind1, :));
    end
    ind1 = ~ind1;
    if sum(ind1) > 0
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + kf .* ...
            (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(ind1, :) - pop(Rg3(ind1), :));
    end

    % ----- senior gaining-sharing (better/worse branching on R2) -----
    R0 = 1:np;
    Gained_Shared_Senior = zeros(np, dim);
    ind = fitness(R0) > fitness(R2);
    if sum(ind) > 0
        Gained_Shared_Senior(ind, :) = pop(ind, :) + kf .* ...
            (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
    end
    ind = ~ind;
    if sum(ind) > 0
        Gained_Shared_Senior(ind, :) = pop(ind, :) + kf .* ...
            (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
    end

    % ----- bound constraints (midpoint repair) -----
    Gained_Shared_Junior = gsk_bound_repair(Gained_Shared_Junior, pop, lb, ub);
    Gained_Shared_Senior = gsk_bound_repair(Gained_Shared_Senior, pop, lb, ub);

    % ----- dimension selection masks -----
    % Reference draw order: junior probability mask, junior KR mask,
    % senior KR mask (three rand(NP, D) draws); senior mask is the
    % complement of the junior probability mask before KR filtering.
    D_Gained_Shared_Junior_mask = rand(np, dim) <= ...
        (D_Gained_Shared_Junior ./ dim);
    D_Gained_Shared_Senior_mask = ~D_Gained_Shared_Junior_mask;

    D_Gained_Shared_Junior_rand_mask = rand(np, dim) <= kr;
    D_Gained_Shared_Junior_mask = and(D_Gained_Shared_Junior_mask, ...
        D_Gained_Shared_Junior_rand_mask);

    D_Gained_Shared_Senior_rand_mask = rand(np, dim) <= kr;
    D_Gained_Shared_Senior_mask = and(D_Gained_Shared_Senior_mask, ...
        D_Gained_Shared_Senior_rand_mask);

    % ----- trial vector generation -----
    ui = pop;
    ui(D_Gained_Shared_Junior_mask) = Gained_Shared_Junior(D_Gained_Shared_Junior_mask);
    ui(D_Gained_Shared_Senior_mask) = Gained_Shared_Senior(D_Gained_Shared_Senior_mask);

    % ----- offspring evaluation -----
    % The reference always evaluates the full generation, then counts at
    % most the remaining budget (sequential scan, strict-< update); a
    % crossing generation is therefore fully evaluated but only its first
    % max_nfes - nfes children update nfes and the best-so-far.
    children_fitness = problem.evaluate(ui);
    children_fitness = children_fitness(:);

    n_count = min(np, max_nfes - nfes);
    if n_count > 0
        [gen_min, gen_idx] = min(children_fitness(1:n_count));
        if gen_min < bsf_fit_var
            bsf_fit_var = gen_min;
            bsf_solution = ui(gen_idx, :);
        end
        nfes = nfes + n_count;
    end

    % ----- pairwise greedy selection (parent vs child, ties keep parent) -----
    [fitness, Child_is_better_index] = min([fitness, children_fitness], [], 2);
    popold = pop;
    popold(Child_is_better_index == 2, :) = ui(Child_is_better_index == 2, :);

    n_conv = n_conv + 1;
    conv_nfes(n_conv) = nfes;
    conv_best(n_conv) = bsf_fit_var;
end

% ----- final error, reference target semantics -----
% The reference never stops early on the target; it only zeroes the final
% error (GSK_Enhanced.m / GSK.m):
%   bsf_error_val = bsf_fit_var - optimum;
%   if bsf_error_val < val_2_reach, bsf_error_val = 0; end
% NaN guards per docs/reference/matlab_interface.md.
if isnan(problem.optimum)
    error_val = NaN;
else
    error_val = bsf_fit_var - problem.optimum;
    if ~isnan(problem.target_error) && error_val < problem.target_error
        error_val = 0;
    end
end

result = struct();
result.optimizer = 'gsk';
result.suite = problem.suite;
result.func_id = problem.func_id;
result.dim = dim;
result.seed = actual_seed;
result.best_x = bsf_solution;
result.best_fitness = bsf_fit_var;
result.error = error_val;
result.nfes = nfes;
result.termination = 'max_evaluations';
result.convergence = struct('nfes', conv_nfes(1:n_conv), ...
    'best_fitness', conv_best(1:n_conv));
result.runtime_seconds = toc(t_start);
result.params = struct('np', np, 'kf', kf, 'kr', kr, 'k', k_rate, 'p', p_part);
result.notes = '';

end


function v = local_option(options, name, default)
%LOCAL_OPTION Read an optional field with a reference default.
if isfield(options, name) && ~isempty(options.(name))
    v = options.(name);
else
    v = default;
end
end
