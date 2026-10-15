function result = egsk_optimize(problem, options)
%EGSK_OPTIMIZE Faithful MATLAB port of eGSK (Enhanced Gaining-Sharing
%Knowledge-based algorithm; Jawad, Roshdy & Mohamed,
%https://doi.org/10.1016/j.rico.2025.100542).
%
% Historical source notes (transcribed line by line):
%   historical source: egsk/egsk/finaleGSK2023/eGSK.m
%   historical source: egsk/egsk/finaleGSK2023/IP.m
%       (ported as egsk_ip_refine.m)
%   historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Junior_R1R2R3.m
%       (behaviorally identical to the shared src/common copy -- the only
%        textual difference is a cosmetic comma after "if i > 1000"; the
%        shared Gained_Shared_Junior_R1R2R3 is therefore called directly)
%   historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Senior_R1R2R3.m
%       (takes only indBest and uses fixed round(0.1/0.9) partition
%        boundaries, which DIFFER from the shared Senior(indBest, P) helper;
%        kept as the local copy egsk_gained_shared_senior.m)
%   historical source: egsk/egsk/finaleGSK2023/boundConstraint.m
%       (transcribed as the boundConstraint local function below)
%
% Transcribed behaviors (preserved exactly, do NOT "fix"):
%   * KF1 = KF2 = 0.5*ones(NP,1) separate junior/senior knowledge factors;
%     KR = 1; K = 10 (scalar knowledge rate, so D_Gained_Shared_Junior is a
%     scalar broadcast over the population).
%   * Late-stage trigger: every generation with g >= 0.75*G_Max (where
%     G_Max = fix(max_nfes/NP)) recomputes KF1 per individual from a
%     triangular membership over (fitness(Rg1), fitness(Rg3), fitness(Rg2))
%     and KF2 from scalar anchors fitness(min(R1)), fitness(min(R2)),
%     fitness(min(R3)) -- min over the INDEX vectors, as written -- followed
%     by forcing out-of-range memberships to zero: KF(KF>=1)=0; KF(KF<=0)=0.
%   * Population-level selection twist: if sum(fitness) < sum(children)
%     the parent population is the base and improving children are copied
%     in; otherwise the CHILD population is the base and better parents are
%     restored. Both branches keep the pairwise best, but tie-breaking
%     favors the base population -- transcribed as written, not replaced by
%     plain pairwise selection.
%   * IP local refinement (fmincon SQP, budget ceil(0.002*max_nfes)) runs in
%     the same late stage whenever the best-so-far error is still above the
%     target and std([a2 b2 c2])*1e-2 <= 1; the refined point replaces the
%     incumbent at row NO_i (the row index that produced the current
%     best-so-far), and fitness(NO_i) is overwritten -- exactly as eGSK.m.
%
% Toolbox policy: the reference IP stage requires fmincon. Default runs require
% license('test','Optimization_Toolbox') && exist('fmincon','file'); otherwise
% the run errors before the search starts. options.use_fmincon=false is kept only
% as an explicit non-reference diagnostic opt-out.
%
% Unknown optimum: the reference escape trigger compares
% bsf_fit_var > optimum + val_2_reach (val_2_reach = 1e-8). With
% problem.optimum == NaN the target can never be confirmed reached, so the
% trigger is treated as satisfied; the tolerance is problem.target_error
% when set, otherwise the reference constant 1e-8.
%
% Sanctioned modernization (the only one): the reference wall-clock seeding
% rand('seed', sum(100*clock)) is replaced by gsk_set_rng(options) in
% reference runs. options.rand_generator can select threefry, twister, or the
% deterministic legacy 'seed' (v4) / 'state' (v5) streams.
%
% Interface: see docs/reference/matlab_interface.md. result = egsk_optimize(problem, options)

start_time = tic;

if ~isfield(options, 'seed') || isempty(options.seed)
    error('egsk:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % direct-call default 'twister'; selects threefry|twister|seed|state

problem_size = problem.dim;
max_nfes = problem.max_nfes;
lu = [problem.lb; problem.ub];
has_optimum = ~isnan(problem.optimum);

% Reference constant val_2_reach = 10^(-8); the runner-provided
% problem.target_error plays that role when set.
if ~isnan(problem.target_error)
    val_2_reach = problem.target_error;
else
    val_2_reach = 10^(-8);
end

% fmincon availability. The published eGSK reference always calls fmincon when
% IP triggers, so the default/reference path requires it. The only supported
% no-IP path is an explicit low-level diagnostic opt-out.
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
% Reference/reproduction runs do not pass X0, so this remains the original
% one-draw initialization. Unified fair-comparison runs pass the runner-drawn
% X0 plus the post-X0 RNG state; accepting both here lets every optimizer start
% from the same population and same next random number for the same CEC cell.
popold = gsk_initial_population_from_options(options, pop_size, lu(1, :), lu(2, :));
gsk_restore_rng_after_initialization(options);
pop = popold; % the old population becomes the current population

fitness = problem.evaluate(pop);

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = pop(1, :); % defined-before-use guard; overwritten identically by the loop below
NO_i = 1;

for i = 1:pop_size
    nfes = nfes + 1;
    if nfes > max_nfes; break; end
    if fitness(i) < bsf_fit_var
        bsf_fit_var = fitness(i);
        bsf_solution = pop(i, :);
        NO_i = i;
    end
end

%% Parameter settings (reference values; overrides keep reference defaults)
KF1 = 0.5 * ones(pop_size, 1); % junior Knowledge Factor
KF2 = 0.5 * ones(pop_size, 1); % senior Knowledge Factor
KR = 1;                        % Knowledge Ratio
K = 10;                        % Knowledge Rate (scalar)
if isfield(options, 'kf1') && ~isempty(options.kf1); KF1 = options.kf1 * ones(pop_size, 1); end
if isfield(options, 'kf2') && ~isempty(options.kf2); KF2 = options.kf2 * ones(pop_size, 1); end
if isfield(options, 'kr') && ~isempty(options.kr); KR = options.kr; end
if isfield(options, 'k') && ~isempty(options.k); K = options.k; end

% Per-generation convergence recording (interface requirement)
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
    D_Gained_Shared_Junior = ceil((problem_size) * (1 - g / G_Max).^K); % scalar (K is scalar in eGSK)

    D_Gained_Shared_Senior = problem_size - D_Gained_Shared_Junior; %#ok<NASGU>
    pop = popold; % the old population becomes the current population

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

    %% Selection (1) -- population-level twist, transcribed as written
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
            KF1 = y1; % reference re-assigns the whole vector inside the loop (as written)
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
                % else: explicit non-reference diagnostic mode; IP is skipped.
            end
        end
    end

    n_rec = n_rec + 1;
    conv_nfes(n_rec) = nfes;
    conv_fit(n_rec) = bsf_fit_var;
end % end while loop

%% Result assembly (docs/reference/matlab_interface.md)
% Reference driver: bsf_error_val = bsf_fit_var - optimum; zeroed below
% val_2_reach.
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
%BOUNDCONSTRAINT Midpoint bound repair, transcribed from the reference
% boundConstraint.m next to eGSK.m (byte-identical to the ATMALS-GSK copies).

[NP, ~] = size(pop); % the population size and the problem's dimension

% check the lower bound
xl = repmat(lu(1, :), NP, 1);
pos = vi < xl;
vi(pos) = (pop(pos) + xl(pos)) / 2;

% check the upper bound
xu = repmat(lu(2, :), NP, 1);
pos = vi > xu;
vi(pos) = (pop(pos) + xu(pos)) / 2;
end
