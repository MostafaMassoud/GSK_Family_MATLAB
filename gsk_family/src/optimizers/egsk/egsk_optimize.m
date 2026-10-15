function result = egsk_optimize(problem, options)
%EGSK_OPTIMIZE Enhanced Gaining-Sharing Knowledge based optimizer (eGSK).
%
%   result = egsk_optimize(problem, options)
%
% MATLAB port of eGSK (Jawad, Roshdy & Mohamed,
% https://doi.org/10.1016/j.rico.2025.100542), transcribed line by line from:
%   historical source: egsk/egsk/finaleGSK2023/eGSK.m
%   historical source: egsk/egsk/finaleGSK2023/IP.m
%       -> egsk_ip_refine.m
%   historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Junior_R1R2R3.m
%       Same behavior as the shared src/common copy (only a cosmetic comma
%       after "if i > 1000" differs), so the shared helper is called.
%   historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Senior_R1R2R3.m
%       Takes only indBest and hard-codes round(0.1/0.9) partition
%       boundaries, unlike the shared Senior(indBest, P) helper; kept as
%       the local copy egsk_gained_shared_senior.m.
%   historical source: egsk/egsk/finaleGSK2023/boundConstraint.m
%       -> local function boundConstraint below.
%
% Fields of problem, options and result: docs/reference/matlab_interface.md.
% options.seed is required (error 'egsk:options'). Optional: np (100),
% kf1 (0.5), kf2 (0.5), kr (1), k (10), use_fmincon (true). The run never
% stops early; termination is always 'max_evaluations'.
%
% Reference behaviors kept exactly as written (do NOT "fix"):
%   * Separate junior/senior knowledge factors KF1 = KF2 = 0.5*ones(NP,1);
%     KR = 1; K = 10. K is a scalar, so D_Gained_Shared_Junior is one value
%     for the whole population.
%   * Late stage: every generation with g >= 0.75*G_Max
%     (G_Max = fix(max_nfes/NP)) recomputes KF1 per individual from a
%     triangular membership over (fitness(Rg1), fitness(Rg3), fitness(Rg2)),
%     and KF2 from the scalar anchors fitness(min(R1)), fitness(min(R2)),
%     fitness(min(R3)) - min over the INDEX vectors, as written. Memberships
%     >= 1 or <= 0 are then set to zero: KF(KF>=1)=0; KF(KF<=0)=0.
%   * Selection: if sum(fitness) < sum(children), the parents are the base
%     and better children are copied in; otherwise the CHILDREN are the
%     base and better parents are restored. Both keep the pairwise best,
%     but ties go to the base population, so do not replace this with
%     plain pairwise selection.
%   * IP local refinement (fmincon SQP, budget ceil(0.002*max_nfes)) runs in
%     the late stage whenever the best-so-far error is above the target and
%     std([a2 b2 c2])*1e-2 <= 1. The refined point replaces row NO_i (the
%     row that produced the current best-so-far), and fitness(NO_i) is
%     overwritten, exactly as in eGSK.m.
%
% Toolbox: the reference IP stage needs fmincon. By default the run requires
% license('test','Optimization_Toolbox') && exist('fmincon','file') and
% otherwise raises 'egsk:fminconUnavailable' before the search starts.
% options.use_fmincon = false is only an explicit, non-reference diagnostic
% opt-out.
%
% Unknown optimum: the reference escape trigger tests
% bsf_fit_var > optimum + val_2_reach (val_2_reach = 1e-8). With
% problem.optimum = NaN the target can never be confirmed, so the trigger
% counts as satisfied. The tolerance is problem.target_error when set,
% else the reference constant 1e-8.
%
% The only deliberate change in reference runs: the wall-clock seeding
% rand('seed', sum(100*clock)) is replaced by gsk_set_rng(options).
% options.rand_generator selects threefry, twister, or the deterministic
% legacy 'seed' (v4) / 'state' (v5) streams.

start_time = tic;

if ~isfield(options, 'seed') || isempty(options.seed)
    error('egsk:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % options.rand_generator, default twister

problem_size = problem.dim;
max_nfes = problem.max_nfes;
lu = [problem.lb; problem.ub];
has_optimum = ~isnan(problem.optimum);

% Target tolerance: problem.target_error when set, else the reference
% constant val_2_reach = 10^(-8).
if ~isnan(problem.target_error)
    val_2_reach = problem.target_error;
else
    val_2_reach = 10^(-8);
end

% The published eGSK always calls fmincon when IP triggers, so the default
% path requires it. The only way to skip IP is the explicit diagnostic
% opt-out options.use_fmincon = false.
fmincon_available = license('test', 'Optimization_Toolbox') && exist('fmincon', 'file') > 0;
notes = '';
if isfield(options, 'use_fmincon') && ~isempty(options.use_fmincon)
    use_fmincon = logical(options.use_fmincon);
    if use_fmincon && ~fmincon_available
        error('egsk:fminconUnavailable', ...
            ['eGSK reference mode requires Optimization Toolbox/fmincon for the IP ' ...
             'stage. Install/enable fmincon, or pass options.use_fmincon=false ' ...
             'only for an explicit non-reference diagnostic run.']);
    elseif ~use_fmincon
        notes = 'IP refinement disabled via options.use_fmincon (non-reference diagnostic mode)';
    end
else
    use_fmincon = true;
    if ~fmincon_available
        error('egsk:fminconUnavailable', ...
            ['eGSK reference mode requires Optimization Toolbox/fmincon for the IP ' ...
             'stage. Install/enable fmincon, or pass options.use_fmincon=false ' ...
             'only for an explicit non-reference diagnostic run.']);
    end
end

pop_size = 100;
if isfield(options, 'np') && ~isempty(options.np); pop_size = options.np; end

G_Max = fix(max_nfes / pop_size);

%% Initialize the main population (reference one-liner, or runner X0)
% Reference runs pass no X0 and keep the original single draw. Unified
% fair-comparison runs pass the runner's X0 and the RNG state right after
% drawing it, so every optimizer starts from the same population and the
% same next random number for a given CEC cell.
popold = gsk_initial_population_from_options(options, pop_size, lu(1, :), lu(2, :));
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop);

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = pop(1, :); % defined before use; the loop's first pass sets the same row
NO_i = 1;

% Initial best-so-far scan, as in the reference: count each evaluation and
% stop once nfes exceeds max_nfes. NO_i is the row of the best-so-far.
for i = 1:pop_size
    nfes = nfes + 1;
    if nfes > max_nfes; break; end
    if fitness(i) < bsf_fit_var
        bsf_fit_var = fitness(i);
        bsf_solution = pop(i, :);
        NO_i = i;
    end
end

%% Parameter settings (reference defaults; options can override them)
KF1 = 0.5 * ones(pop_size, 1); % junior Knowledge Factor
KF2 = 0.5 * ones(pop_size, 1); % senior Knowledge Factor
KR = 1;                        % Knowledge Ratio
K = 10;                        % Knowledge Rate (scalar)
if isfield(options, 'kf1') && ~isempty(options.kf1); KF1 = options.kf1 * ones(pop_size, 1); end
if isfield(options, 'kf2') && ~isempty(options.kf2); KF2 = options.kf2 * ones(pop_size, 1); end
if isfield(options, 'kr') && ~isempty(options.kr); KR = options.kr; end
if isfield(options, 'k') && ~isempty(options.k); K = options.k; end

% Convergence log: one row after initialization, then one per generation.
max_records = ceil(max_nfes / pop_size) + 2;
conv_nfes = zeros(max_records, 1);
conv_fit = zeros(max_records, 1);
n_rec = 1;
conv_nfes(n_rec) = nfes;
conv_fit(n_rec) = bsf_fit_var;

g = 0;
%% main loop
while nfes < max_nfes
    g = g + 1;
    D_Gained_Shared_Junior = ceil((problem_size) * (1 - g / G_Max).^K); % scalar, since K is a scalar

    D_Gained_Shared_Senior = problem_size - D_Gained_Shared_Junior; %#ok<NASGU>
    pop = popold;

    [~, indBest] = sort(fitness, 'ascend');
    [Rg1, Rg2, Rg3] = Gained_Shared_Junior_R1R2R3(indBest);

    [R1, R2, R3] = egsk_gained_shared_senior(indBest); % eGSK-local senior partition (no P argument)
    R01 = 1:pop_size;
    Gained_Shared_Junior = zeros(pop_size, problem_size);
    ind1 = fitness(R01) > fitness(Rg3);

    if (sum(ind1) > 0)
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF1(ind1) .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(Rg3(ind1), :) - pop(ind1, :));
    end
    ind1 = ~ind1;
    if (sum(ind1) > 0)
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF1(ind1) .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(ind1, :) - pop(Rg3(ind1), :));
    end
    R0 = 1:pop_size;
    Gained_Shared_Senior = zeros(pop_size, problem_size);
    ind = fitness(R0) > fitness(R2);
    if (sum(ind) > 0)
        Gained_Shared_Senior(ind, :) = pop(ind, :) + KF2(ind) .* (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
    end
    ind = ~ind;
    if (sum(ind) > 0)
        Gained_Shared_Senior(ind, :) = pop(ind, :) + KF2(ind) .* (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
    end
    Gained_Shared_Junior = boundConstraint(Gained_Shared_Junior, pop, lu);
    Gained_Shared_Senior = boundConstraint(Gained_Shared_Senior, pop, lu);

    D_Gained_Shared_Junior_mask = rand(pop_size, problem_size) <= (D_Gained_Shared_Junior ./ problem_size);
    D_Gained_Shared_Senior_mask = ~D_Gained_Shared_Junior_mask;

    D_Gained_Shared_Junior_rand_mask = rand(pop_size, problem_size) <= KR;
    D_Gained_Shared_Junior_mask = and(D_Gained_Shared_Junior_mask, D_Gained_Shared_Junior_rand_mask);

    D_Gained_Shared_Senior_rand_mask = rand(pop_size, problem_size) <= KR;
    D_Gained_Shared_Senior_mask = and(D_Gained_Shared_Senior_mask, D_Gained_Shared_Senior_rand_mask);
    ui = pop;

    ui(D_Gained_Shared_Junior_mask) = Gained_Shared_Junior(D_Gained_Shared_Junior_mask);
    ui(D_Gained_Shared_Senior_mask) = Gained_Shared_Senior(D_Gained_Shared_Senior_mask);
    children_fitness = problem.evaluate(ui);

    for i = 1:pop_size
        nfes = nfes + 1;
        if nfes > max_nfes; break; end
        if children_fitness(i) < bsf_fit_var
            bsf_fit_var = children_fitness(i);
            bsf_solution = ui(i, :);
            NO_i = i;
        end
    end

    %% Selection (1): population-level rule, as written (see header)
    if sum(fitness) < sum(children_fitness)
        [fitness, Child_is_better_index] = min([fitness, children_fitness], [], 2);
        popold = pop;
        popold(Child_is_better_index == 2, :) = ui(Child_is_better_index == 2, :);
    else
        [children_fitness, Child_is_better_index] = min([children_fitness, fitness], [], 2);
        popold = ui;
        popold(Child_is_better_index == 2, :) = pop(Child_is_better_index == 2, :);
        fitness = children_fitness;
    end

    %% Parameters setup KF1, KF2 (late stage: g >= 0.75*G_Max)
    if g >= 0.75 * G_Max
        a1 = fitness((Rg1));
        c1 = fitness((Rg2));
        b1 = fitness((Rg3));
        x1 = fitness;
        y1 = zeros(pop_size, 1);
        for k = 1:pop_size
            if and(a1(k) <= x1(k), x1(k) <= b1(k))
                y1(k) = (x1(k) - a1(k)) ./ (b1(k) - a1(k));
            elseif and(b1(k) <= x1(k), x1(k) <= c1(k))
                y1(k) = (c1(k) - x1(k)) ./ (c1(k) - b1(k));
            else
                y1(k) = 0;
            end
            KF1 = y1; % the reference reassigns the whole vector inside the loop
        end
        KF1(KF1 >= 1) = 0;
        KF1(KF1 <= 0) = 0;
        a2 = fitness(min(R1)); % min over the INDEX vector (reference quirk)
        b2 = fitness(min(R2));
        c2 = fitness(min(R3));
        x2 = fitness;
        y2 = zeros(pop_size, 1);
        for k = 1:pop_size
            if and(a2 <= x2(k), x2(k) <= b2)
                y2(k) = (x2(k) - a2) ./ (b2 - a2);
            elseif and(b2 <= x2(k), x2(k) <= c2)
                y2(k) = (c2 - x2(k)) ./ (c2 - b2);
            else
                y2(k) = 0;
            end
            KF2 = y2;
        end
        KF2(KF2 >= 1) = 0;
        KF2(KF2 <= 0) = 0;

        %% Escaping from local minimum solutions
        if ~has_optimum || bsf_fit_var > problem.optimum + val_2_reach
            T = [];
            T(1, 1) = a2;
            T(1, 2) = b2;
            T(1, 3) = c2;
            zz = std(T);
            q = 0;
            zz = zz * 1e-2;
            q(zz <= 1) = 1;
            if q == 1
                if use_fmincon
                    [bsf_solution, bsf_fit_var, nfes] = egsk_ip_refine(bsf_solution, bsf_fit_var, nfes, problem, max_nfes);
                    popold(NO_i, :) = bsf_solution;
                    fitness(NO_i, :) = bsf_fit_var;
                end
                % else: diagnostic mode (use_fmincon = false); IP is skipped.
            end
        end
    end

    n_rec = n_rec + 1;
    conv_nfes(n_rec) = nfes;
    conv_fit(n_rec) = bsf_fit_var;
end

%% Result assembly (docs/reference/matlab_interface.md)
% Reference driver: bsf_error_val = bsf_fit_var - optimum, set to 0 when
% below the target (here problem.target_error, if set).
if has_optimum
    err = bsf_fit_var - problem.optimum;
    if ~isnan(problem.target_error) && err < problem.target_error
        err = 0;
    end
else
    err = NaN;
end

params = struct();
params.np = pop_size;
params.kf1_init = 0.5;
params.kf2_init = 0.5;
if isfield(options, 'kf1') && ~isempty(options.kf1); params.kf1_init = options.kf1; end
if isfield(options, 'kf2') && ~isempty(options.kf2); params.kf2_init = options.kf2; end
params.kr = KR;
params.k = K;
params.use_fmincon = use_fmincon;
params.late_stage_trigger = 0.75;
params.ip_fe = ceil(2.0000e-003 * max_nfes);

result = struct();
result.optimizer = 'egsk';
result.suite = problem.suite;
result.func_id = problem.func_id;
result.dim = problem.dim;
result.seed = actual_seed;
result.best_x = bsf_solution;
result.best_fitness = bsf_fit_var;
result.error = err;
result.nfes = nfes;
result.termination = 'max_evaluations'; % the reference never stops early
result.convergence = struct('nfes', conv_nfes(1:n_rec), 'best_fitness', conv_fit(1:n_rec));
result.runtime_seconds = toc(start_time);
result.params = params;
result.notes = notes;
end

function vi = boundConstraint(vi, pop, lu)
%BOUNDCONSTRAINT Midpoint bound repair.
% Transcribed from the reference boundConstraint.m next to eGSK.m
% (byte-identical to the ATMALS-GSK copies). vi and pop are NP x D and
% lu = [lb; ub]. An entry of vi outside [lb, ub] moves to the midpoint of
% the parent value in pop and the violated bound.

[NP, ~] = size(pop); % population size

% check the lower bound
xl = repmat(lu(1, :), NP, 1);
pos = vi < xl;
vi(pos) = (pop(pos) + xl(pos)) / 2;

% check the upper bound
xu = repmat(lu(2, :), NP, 1);
pos = vi > xu;
vi(pos) = (pop(pos) + xu(pos)) / 2;
end
