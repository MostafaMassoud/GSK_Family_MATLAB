function result = agsk_optimize(problem, options)
%AGSK_OPTIMIZE Adaptive Gaining-Sharing Knowledge based optimizer (AGSK).
%
%   result = agsk_optimize(problem, options)
%
% MATLAB port of the reference implementation:
%   historical source: agsk/agsk/AGSK-CODE-FINAL/Adaptive_GSK_ALI.m
% Its local helpers (same folder) are replaced by these shared ports:
%   Gained_Shared_Junior_R1R2R3.m  -> src/common
%   Gained_Shared_Senior_R1R2R3.m  -> src/common, with P = 0.05
%   boundConstraint.m              -> src/common/gsk_bound_repair.m
%
% Fields of problem, options and result: docs/reference/matlab_interface.md.
% Reference behaviors kept here (KW phase length, All_Imp update, nfes-ratio
% junior schedule, population reduction, budget crossing, target error):
% src/optimizers/agsk/README.md.
%
% options.seed is required. Optional: np_init (100), min_pop_size (12,
% must be >= 11 and <= np_init). Bad options raise 'agsk_optimize:options'.
% When problem.optimum and problem.target_error are set, the run stops
% early once the error drops below the target: the error is reported as 0
% and termination is 'target_error_reached'.

if ~isfield(options, 'seed') || isempty(options.seed)
    error('agsk_optimize:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % options.rand_generator, default twister

% Interface defaults (docs/reference/matlab_interface.md). The reference
% driver uses pop_size = 40*D for D > 5 and 100 otherwise; pass
% options.np_init to reproduce that (see README).
np_init = local_option(options, 'np_init', 100);
min_pop_size = local_option(options, 'min_pop_size', 12);
% The P = 0.05 senior partition needs non-empty best and worst blocks
% (round(0.05*NP) >= 1 and NP - round(0.95*NP) >= 1), so NP must stay
% >= 11 throughout population reduction. Checked before any RNG draw.
if ~(isscalar(np_init) && isscalar(min_pop_size) && ...
        min_pop_size >= 11 && np_init >= min_pop_size)
    error('agsk_optimize:options', ...
        ['min_pop_size must be >= 11 (the P = 0.05 senior partition needs ' ...
         'NP >= 11) and np_init >= min_pop_size; got np_init=%s, min_pop_size=%s'], ...
        mat2str(np_init), mat2str(min_pop_size));
end

% Reference parameter pools: setting i uses kf_pool(i) and kr_pool(i).
kf_pool = [0.1 1.0 0.5 1.0];
kr_pool = [0.2 0.1 0.9 0.9];
% The reference senior helper hard-codes the 0.05/0.95 rank partition.
senior_p = 0.05;

dim = problem.dim;
lb = problem.lb;
ub = problem.ub;
max_nfes = problem.max_nfes;

t_start = tic;

pop_size = np_init;
max_pop_size = pop_size;

% ----- population initialization (one rand(NP, D) draw, or runner X0) -----
% Reference runs pass no X0 and keep the original single draw. Unified
% fair-comparison runs pass the runner's X0 and the RNG state right after
% drawing it, so every optimizer starts from the same population and the
% same next random number for a given CEC cell.
popold = gsk_initial_population_from_options(options, pop_size, lb, ub);
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop);
fitness = fitness(:);

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = zeros(1, dim);

% Initial best-so-far scan; count at most max_nfes evaluations. Strict <
% update, so the first minimum wins. Tracking best_x here is an
% output-only extension (see README).
n_init = min(pop_size, max_nfes - nfes);
if n_init > 0
    [init_min, init_idx] = min(fitness(1:n_init));
    if init_min < bsf_fit_var
        bsf_fit_var = init_min;
        bsf_solution = pop(init_idx, :);
    end
    nfes = nfes + n_init;
end

% ----- per-individual knowledge rate K (reference draw order) -----
% Reference: Kind = rand(pop_size, 1);
%   K(Kind <  0.5) = rand                (uniform in (0,1))
%   K(Kind >= 0.5) = ceil(20*rand)       (uniform integer 1..20)
Kind = rand(pop_size, 1);
k_vec = zeros(pop_size, 1);
k_vec(Kind < 0.5) = rand(sum(Kind < 0.5), 1);
k_vec(Kind >= 0.5) = ceil(20 * rand(sum(Kind >= 0.5), 1));

KW_ind = [];                %#ok<NASGU> % set in the first generation
All_Imp = zeros(1, 4);

% Convergence log: one row after initialization (generation 0), then one
% row per generation. max_rows assumes each generation uses at least
% min_pop_size evaluations.
max_rows = ceil(max_nfes / max(1, min_pop_size)) + 2;
conv_nfes = zeros(max_rows, 1);
conv_best = zeros(max_rows, 1);
n_conv = 1;
conv_nfes(n_conv) = nfes;
conv_best(n_conv) = bsf_fit_var;
% Opt-in dynamics trace (options.log_trace): one row per generation, with
% the probabilities KW_ind of the four (KF, KR) pool settings.
tr = gsk_trace_start(options, max_rows);
if tr.on; tr = gsk_trace_add(tr, nfes, popold, lb, ub, {'kw1', 'kw2', 'kw3', 'kw4'}, nan(1, 4)); end

g = 0;
terminated_on_target = false;

% ----- main loop -----
while nfes < max_nfes
    g = g + 1;

    % KW probabilities of the four pool settings. While
    % nfes < 0.1*max_nfes, reset KW_ind to [0.85 0.05 0.05 0.05] every
    % generation. After that, blend in the improvement credit All_Imp
    % (weights 0.95 / 0.05) and normalize.
    % The isempty guard covers np_init >= 0.1*max_nfes (e.g. a reduced
    % budget), where generation 1 would otherwise update an unset KW_ind.
    % On full-budget runs the nfes test fires first, so the guard does not
    % change their results.
    if isempty(KW_ind) || nfes < 0.1 * max_nfes
        KW_ind = [0.85 0.05 0.05 0.05];
    else
        KW_ind = 0.95 * KW_ind + 0.05 * All_Imp;
        KW_ind = KW_ind ./ sum(KW_ind);
    end

    % Pick a pool setting (1..4) per individual: one rand(NP,1) draw,
    % relabeled by the KW_ind thresholds as in the reference. Same block in
    % both phases.
    K_rand_ind = rand(pop_size, 1);
    K_rand_ind(K_rand_ind > sum(KW_ind(1:3)) & K_rand_ind <= sum(KW_ind(1:4))) = 4;
    K_rand_ind(K_rand_ind > sum(KW_ind(1:2)) & K_rand_ind <= sum(KW_ind(1:3))) = 3;
    K_rand_ind(K_rand_ind > KW_ind(1) & K_rand_ind <= sum(KW_ind(1:2))) = 2;
    K_rand_ind(K_rand_ind > 0 & K_rand_ind <= KW_ind(1)) = 1;
    KF = kf_pool(K_rand_ind)';
    KR = kr_pool(K_rand_ind)';

    % Junior dimensions per individual, from the nfes ratio (not the
    % generation ratio) and the per-individual exponent K:
    %   D_Gained_Shared_Junior = ceil(D * (1 - nfes/max_nfes).^K)
    D_Gained_Shared_Junior = ceil(dim * (1 - nfes / max_nfes) .^ k_vec);

    pop = popold;

    [~, indBest] = sort(fitness, 'ascend');
    [Rg1, Rg2, Rg3] = Gained_Shared_Junior_R1R2R3(indBest);
    [R1, R2, R3] = Gained_Shared_Senior_R1R2R3(indBest, senior_p);

    % ----- junior gaining-sharing (per-individual KF) -----
    R01 = 1:pop_size;
    Gained_Shared_Junior = zeros(pop_size, dim);
    ind1 = fitness(R01) > fitness(Rg3);
    if sum(ind1) > 0
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF(ind1) .* ...
            (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(Rg3(ind1), :) - pop(ind1, :));
    end
    ind1 = ~ind1;
    if sum(ind1) > 0
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF(ind1) .* ...
            (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(ind1, :) - pop(Rg3(ind1), :));
    end

    % ----- senior gaining-sharing (per-individual KF) -----
    R0 = 1:pop_size;
    Gained_Shared_Senior = zeros(pop_size, dim);
    ind = fitness(R0) > fitness(R2);
    if sum(ind) > 0
        Gained_Shared_Senior(ind, :) = pop(ind, :) + KF(ind) .* ...
            (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
    end
    ind = ~ind;
    if sum(ind) > 0
        Gained_Shared_Senior(ind, :) = pop(ind, :) + KF(ind) .* ...
            (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
    end

    % ----- bound constraints (midpoint repair) -----
    Gained_Shared_Junior = gsk_bound_repair(Gained_Shared_Junior, pop, lb, ub);
    Gained_Shared_Senior = gsk_bound_repair(Gained_Shared_Senior, pop, lb, ub);

    % ----- dimension selection masks (reference draw order) -----
    D_Gained_Shared_Junior_mask = rand(pop_size, dim) <= ...
        (D_Gained_Shared_Junior ./ dim);
    D_Gained_Shared_Senior_mask = ~D_Gained_Shared_Junior_mask;

    D_Gained_Shared_Junior_rand_mask = rand(pop_size, dim) <= KR;
    D_Gained_Shared_Junior_mask = and(D_Gained_Shared_Junior_mask, ...
        D_Gained_Shared_Junior_rand_mask);

    D_Gained_Shared_Senior_rand_mask = rand(pop_size, dim) <= KR;
    D_Gained_Shared_Senior_mask = and(D_Gained_Shared_Senior_mask, ...
        D_Gained_Shared_Senior_rand_mask);

    % ----- trial vector generation -----
    ui = pop;
    ui(D_Gained_Shared_Junior_mask) = Gained_Shared_Junior(D_Gained_Shared_Junior_mask);
    ui(D_Gained_Shared_Senior_mask) = Gained_Shared_Senior(D_Gained_Shared_Senior_mask);

    % ----- offspring evaluation -----
    % The whole generation is evaluated; nfes and the best-so-far count
    % only up to the remaining budget (reference crossing semantics).
    children_fitness = problem.evaluate(ui);
    children_fitness = children_fitness(:);

    n_count = min(pop_size, max_nfes - nfes);
    if n_count > 0
        [gen_min, gen_idx] = min(children_fitness(1:n_count));
        if gen_min < bsf_fit_var
            bsf_fit_var = gen_min;
            bsf_solution = ui(gen_idx, :);
        end
        nfes = nfes + n_count;
    end

    % ----- improvement credit of each pool setting (All_Imp) -----
    % As in the reference: the credit of setting i is the sum of
    % abs(parent - child fitness) over the children that used setting i and
    % are strictly better. Normalize, raise every entry but the largest to
    % at least 0.05, and give the largest the remainder. With no improvement
    % at all, use 1/4 each. Uses the whole generation, including children
    % past the budget, as the reference does.
    dif = abs(fitness - children_fitness);
    Child_is_better_index = (fitness > children_fitness);
    All_Imp = zeros(1, 4);
    for i = 1:4
        if sum(and(Child_is_better_index, K_rand_ind == i)) > 0
            All_Imp(i) = sum(dif(and(Child_is_better_index, K_rand_ind == i)));
        else
            All_Imp(i) = 0;
        end
    end
    if sum(All_Imp) ~= 0
        All_Imp = All_Imp ./ sum(All_Imp);
        [~, Imp_Ind] = sort(All_Imp);
        for imp_i = 1:length(All_Imp) - 1
            All_Imp(Imp_Ind(imp_i)) = max(All_Imp(Imp_Ind(imp_i)), 0.05);
        end
        All_Imp(Imp_Ind(end)) = 1 - sum(All_Imp(Imp_Ind(1:end - 1)));
    else
        All_Imp(:) = 1 / length(All_Imp);
    end

    % ----- pairwise greedy selection (parent vs child, ties keep parent) -----
    [fitness, Child_is_better_index] = min([fitness, children_fitness], [], 2);
    popold = pop;
    popold(Child_is_better_index == 2, :) = ui(Child_is_better_index == 2, :);

    % ----- nonlinear population size reduction (worst removal) -----
    plan_pop_size = round((min_pop_size - max_pop_size) * ...
        ((nfes / max_nfes) .^ ((1 - nfes / max_nfes))) + max_pop_size);
    if pop_size > plan_pop_size
        reduction_ind_num = pop_size - plan_pop_size;
        if pop_size - reduction_ind_num < min_pop_size
            reduction_ind_num = pop_size - min_pop_size;
        end
        pop_size = pop_size - reduction_ind_num;
        % The shared helper keeps the same rows as the reference loop that
        % removes the worst individual one at a time. Trim every array the
        % reference trims (popold, pop, fitness, K), keeping row order.
        survivors = gsk_reduction_survivors(fitness, reduction_ind_num);
        popold = popold(survivors, :);
        pop = pop(survivors, :);
        fitness = fitness(survivors);
        k_vec = k_vec(survivors);
    end

    n_conv = n_conv + 1;
    conv_nfes(n_conv) = nfes;
    conv_best(n_conv) = bsf_fit_var;
    if tr.on; tr = gsk_trace_add(tr, nfes, popold, lb, ub, {'kw1', 'kw2', 'kw3', 'kw4'}, KW_ind); end

    % ----- reference target check: every generation, zero and stop -----
    %   bsf_error_val = bsf_fit_var - optimum;
    %   if bsf_error_val < val_2_reach, bsf_error_val = 0; break; end
    % NaN handling follows docs/reference/matlab_interface.md.
    if ~isnan(problem.target_error) && ~isnan(problem.optimum)
        bsf_error_val = bsf_fit_var - problem.optimum;
        if bsf_error_val < problem.target_error
            terminated_on_target = true;
            break;
        end
    end
end

if isnan(problem.optimum)
    error_val = NaN;
else
    error_val = bsf_fit_var - problem.optimum;
    if terminated_on_target
        error_val = 0;
    end
end

if terminated_on_target
    termination = 'target_error_reached';
else
    termination = 'max_evaluations';
end

result = struct();
result.optimizer = 'agsk';
result.suite = problem.suite;
result.func_id = problem.func_id;
result.dim = dim;
result.seed = actual_seed;
result.best_x = bsf_solution;
result.best_fitness = bsf_fit_var;
result.error = error_val;
result.nfes = nfes;
result.termination = termination;
result.convergence = struct('nfes', conv_nfes(1:n_conv), ...
    'best_fitness', conv_best(1:n_conv));
result.runtime_seconds = toc(t_start);
result.params = struct('np_init', np_init, 'min_pop_size', min_pop_size, ...
    'kf_pool', kf_pool, 'kr_pool', kr_pool, 'senior_p', senior_p);
result.notes = '';
if tr.on; result.trace = gsk_trace_finish(tr); end   % only with options.log_trace

end


function v = local_option(options, name, default)
%LOCAL_OPTION Return options.(name), or default when missing or empty.
if isfield(options, name) && ~isempty(options.(name))
    v = options.(name);
else
    v = default;
end
end
