function result = gsk_optimize(problem, options)
%GSK_OPTIMIZE Baseline Gaining-Sharing Knowledge based optimizer (GSK).
%
%   result = gsk_optimize(problem, options)
%
% MATLAB port of the reference implementation:
%   primary    : historical source: gsk/gsk/GSK_Enhanced.m
%   cross-check: historical source: atmalsgsk/atmalsgsk/cec2017/GSK.m
%                (original form, with the Gained_Shared_Junior_R1R2R3.m and
%                Gained_Shared_Senior_R1R2R3.m helpers next to it)
%
% Fields of problem, options and result: docs/reference/matlab_interface.md.
% Reference behaviors kept here (G_Max, budget crossing, target error,
% random draw order): src/optimizers/gsk/README.md.
%
% options.seed is required (error 'gsk_optimize:options'). Optional fields
% and their reference defaults: np = 100, kf = 0.5, kr = 0.9, k = 10, p = 0.1.

if ~isfield(options, 'seed') || isempty(options.seed)
    error('gsk_optimize:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % options.rand_generator, default twister

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

% G_Max = fix(max_nfes / pop_size), as in GSK_Enhanced.m / GSK.m. It uses
% the full budget, including the initial evaluations. The junior-dimension
% schedule compares the generation counter g with this G_Max.
g_max = fix(max_nfes / np);

% ----- population initialization (one rand(NP, D) draw, or runner X0) -----
% Reference runs pass no X0 and keep the original single draw. Unified
% fair-comparison runs pass the runner's X0 and the RNG state right after
% drawing it, so every optimizer starts from the same population and the
% same next random number for a given CEC cell.
popold = gsk_initial_population_from_options(options, np, lb, ub);
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop);
fitness = fitness(:);

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = zeros(1, dim);

% Initial best-so-far scan. Count at most max_nfes evaluations, as
% GSK_Enhanced does with min(pop_size, max_nfes - nfes). Strict < update,
% so the first minimum wins. Tracking best_x here is an output-only
% extension: the reference sets bsf_solution only inside the generation
% loop (see README).
n_init = min(np, max_nfes - nfes);
if n_init > 0
    [init_min, init_idx] = min(fitness(1:n_init));
    if init_min < bsf_fit_var
        bsf_fit_var = init_min;
        bsf_solution = pop(init_idx, :);
    end
    nfes = nfes + n_init;
end

% Knowledge rate K per individual (reference: K = 10*ones(pop_size, 1)).
k_vec = k_rate * ones(np, 1);

% Convergence log: one row after initialization (generation 0), then one
% row per generation. The reference logs every evaluation (run_funcvals);
% the interface keeps one row per generation (see README).
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

    % Junior dimensions per individual, from the generation ratio:
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
    % Three rand(NP, D) draws in reference order: junior probability mask,
    % junior KR mask, senior KR mask. The senior mask starts as the
    % complement of the junior probability mask, before KR filtering.
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
    % As in the reference, the whole generation is evaluated, but only the
    % first max_nfes - nfes children update nfes and the best-so-far
    % (strict < update). So the generation that crosses the budget is only
    % partly counted.
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
% The reference never stops early on the target. It only sets the final
% error to 0 when it is below the target (GSK_Enhanced.m / GSK.m):
%   bsf_error_val = bsf_fit_var - optimum;
%   if bsf_error_val < val_2_reach, bsf_error_val = 0; end
% NaN handling follows docs/reference/matlab_interface.md.
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
%LOCAL_OPTION Return options.(name), or default when missing or empty.
if isfield(options, name) && ~isempty(options.(name))
    v = options.(name);
else
    v = default;
end
end
