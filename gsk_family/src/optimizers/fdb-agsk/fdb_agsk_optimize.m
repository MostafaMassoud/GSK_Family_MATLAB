function result = fdb_agsk_optimize(problem, options)
%FDB_AGSK_OPTIMIZE Faithful MATLAB port of FDB-AGSK (AGSK with
%Fitness-Distance Balance guide selection), all five reference cases.
%
% Historical source notes (the Case files are self-contained and were
% transcribed directly, including their local
% Gained_Shared_* and boundConstraint subfunctions):
%   historical source: FDB-AGSK reference FDB_AGSK_Case1.m
%   historical source: FDB-AGSK reference FDB_AGSK_Case2.m
%   historical source: FDB-AGSK reference FDB_AGSK_Case3.m
%   historical source: FDB-AGSK reference FDB_AGSK_Case4.m
%   historical source: FDB-AGSK reference FDB_AGSK_Case5.m
%   historical source: FDB-AGSK reference FDB_Func1.m   -> fdb_score_best.m
%   historical source: FDB-AGSK reference FDB_Func2.m   -> fdb_score_ranking.m
%   historical source: FDB-AGSK reference RFDB_Func1.m  -> fdb_score_roulette.m
%   historical source: FDB-AGSK reference problem.m, problem_terminate.m
%       (reference driver harness: sphere objective, D = 100,
%        maxFEs = 1000*D, pop_size = 40*D)
%
% options.fdb_case selects the injection variant (default 1 -- the
% first/canonical case of the reference set; all five are available):
%   Case 1: FDB_Func1 best-scored index -> senior R2 (same guide for every
%           row); junior standard.
%   Case 2: FDB_Func2 descending FDB ranking -> senior R3 sampled from the
%           ranking tail (positions round(NP*0.95)+1..NP); senior R2 is the
%           standard middle partition; junior standard.
%   Case 3: junior R2 = RFDB_Func1 roulette index, junior R3 = FDB_Func1
%           best index (both overwriting the ring-computed values before the
%           collision-regeneration loop); senior standard (0.05/0.95).
%   Case 4: junior R1 = RFDB_Func1 roulette index, junior R3 = FDB_Func1
%           best index; senior standard.
%   Case 5: junior R3 = FDB_Func1 best index; senior standard.
% In cases 3-5 the junior collision loop (R3 == R1/R2/R0) re-randomizes the
% injected constant index at collision positions, exactly as the reference.
%
% Transcribed AGSK machinery (as it appears in the Case files):
%   * Reference problem_terminate harness uses pop_size = 40*problem.dim;
%     this interface defaults to pop_size = 100 and keeps 40*D opt-in via
%     options.np_init. min_pop_size = 12, nonlinear population reduction
%     plan = round((min-max)*((nfes/max_nfes)^(1-nfes/max_nfes)) + max)
%     removing the current worst one by one (K rows deleted alongside).
%   * KF_pool = [0.1 1.0 0.5 1.0], KR_pool = [0.2 0.1 0.9 0.9]; setting
%     probabilities start at [0.85 0.05 0.05 0.05] while nfes < 0.1*max_nfes
%     and afterwards follow KW_ind = 0.95*KW_ind + 0.05*All_Imp
%     (normalized), with the 0.05 floor / largest-gets-remainder rule.
%   * Per-individual knowledge rate K: uniform(0,1) with prob 0.5, integer
%     ceil(20*rand) with prob 0.5; D_junior = ceil(D*(1-nfes/max_nfes).^K).
%
% Preserved quirks / notes:
%   * The reference Case files never record the best-so-far SOLUTION during
%     the initial population scan (only its fitness); this port records it
%     there so result.best_x is always defined. Pure bookkeeping: no RNG
%     draw or search-trajectory change (the reference would crash at its
%     final disp(bsf_solution) if no child ever improved on the initial
%     best).
%   * The reference adaptive branch assumes np_init < 0.1*max_nfes (true for
%     the reference configuration 40*D vs 1000*D); otherwise KW_ind would be
%     its empty initial value when first updated and the reference code path
%     errors. An `isempty(KW_ind)` guard on the phase condition makes this
%     robust under reduced budgets; it is inert on the reference budget (the
%     nfes condition fires first), so it is behavior-preserving.
%   * dif_val is computed and never used, as written.
%   * The reference runs on a simple sphere harness (problem.m); running
%     FDB-AGSK on CEC suites through the generic problem interface is a
%     framework-level extension (see README.md).
%
% Sanctioned modernization (the only one): deterministic seeding via
% gsk_set_rng(options) (the reference relies on MATLAB session RNG state).
%
% Interface: see docs/reference/matlab_interface.md. result = fdb_agsk_optimize(problem, options)

start_time = tic;

if ~isfield(options, 'seed') || isempty(options.seed)
    error('fdb_agsk:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % direct-call default 'twister'; selects threefry|twister|seed|state

fdb_case = 1;
if isfield(options, 'fdb_case') && ~isempty(options.fdb_case)
    fdb_case = options.fdb_case;
end
if ~(isnumeric(fdb_case) && isscalar(fdb_case) && any(fdb_case == 1:5))
    error('fdb_agsk:invalid_case', ...
        'options.fdb_case must be an integer in 1..5 (got %s)', mat2str(fdb_case));
end

problem_size = problem.dim;
max_nfes = problem.max_nfes;
lu = [problem.lb; problem.ub];

pop_size = 100; % CEC2017 competition NP (matches GSK/AGSK; verified to reproduce fdb-agsk_cec2017_D10.csv to <0.2%). The 40*D reference-harness value is opt-in via options.np_init.
if isfield(options, 'np_init') && ~isempty(options.np_init); pop_size = options.np_init; end

KF_pool = [0.1 1.0 0.5 1.0];
KR_pool = [0.2 0.1 0.9 0.9];

%% Parameter settings for population size
max_pop_size = pop_size;
min_pop_size = 12;
if isfield(options, 'min_pop_size') && ~isempty(options.min_pop_size); min_pop_size = options.min_pop_size; end
% The P = 0.05 senior partition needs non-empty best/worst blocks
% (round(0.05*NP) >= 1 and NP - round(0.95*NP) >= 1), i.e. NP >= 11 for
% every population size the reduction can reach. Checked before any RNG draw.
if ~(isscalar(max_pop_size) && isscalar(min_pop_size) && ...
        min_pop_size >= 11 && max_pop_size >= min_pop_size)
    error('fdb_agsk_optimize:options', ...
        ['min_pop_size must be >= 11 (the P = 0.05 senior partition needs ' ...
         'NP >= 11) and np_init >= min_pop_size; got np_init=%s, min_pop_size=%s'], ...
        mat2str(max_pop_size), mat2str(min_pop_size));
end

%% CREATE INITIAL POPULATION
% Reference/reproduction runs do not pass X0, so this remains the original
% one-draw initialization. Unified fair-comparison runs pass the runner-drawn
% X0 plus the post-X0 RNG state; accepting both here lets every optimizer start
% from the same population and same next random number for the same CEC cell.
popold = gsk_initial_population_from_options(options, pop_size, lu(1, :), lu(2, :));
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop); % reference evaluates row by row through problem(); same values

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = pop(1, :); % see header: reference records only the fitness here

for i = 1:pop_size
    nfes = nfes + 1;
    if nfes > max_nfes; break; end
    if fitness(i) < bsf_fit_var
        bsf_fit_var = fitness(i);
        bsf_solution = pop(i, :); % bookkeeping addition (reference omits; see header)
    end
end

%% POSSIBLE VALUES FOR KNOWLEDGE RATE K
K = [];
KF = []; %#ok<NASGU>
KR = []; %#ok<NASGU>
Kind = rand(pop_size, 1);
% K uniform rand (0,1) with prob 0.5 and uniform integer [1,20] with prob 0.5
K(Kind < 0.5, :) = rand(sum(Kind < 0.5), 1);
K(Kind >= 0.5, :) = ceil(20 * rand(sum(Kind >= 0.5), 1));

% Per-generation convergence recording (interface requirement). The
% reference per-child counter reads max_nfes+1 when a generation crosses the
% budget; only the RECORDED copies are clipped at max_nfes (bookkeeping only:
% the loop counter that drives the KW phase, junior schedule and resize plan
% is untouched).
max_records = ceil(max_nfes / max(min_pop_size, 1)) + 2;
conv_nfes = zeros(max_records, 1);
conv_fit = zeros(max_records, 1);
n_rec = 1;
conv_nfes(n_rec) = min(nfes, max_nfes);
conv_fit(n_rec) = bsf_fit_var;

g = 0; %#ok<NASGU>
%% main loop

KW_ind = [];
All_Imp = zeros(1, 4);

while nfes < max_nfes
    g = g + 1; %#ok<NASGU>

    % isempty guard: if np_init >= 0.1*max_nfes (e.g. a reduced budget),
    % generation 1 would otherwise update an uninitialized KW_ind. On the
    % validated runs the nfes condition fires first, so this is preserving.
    if (isempty(KW_ind) || nfes < 0.1 * max_nfes) % initial probability values
        KW_ind = [0.85 0.05 0.05 0.05];
        K_rand_ind = rand(pop_size, 1);
        K_rand_ind(K_rand_ind > sum(KW_ind(1:3)) & K_rand_ind <= sum(KW_ind(1:4))) = 4;
        K_rand_ind(K_rand_ind > sum(KW_ind(1:2)) & K_rand_ind <= sum(KW_ind(1:3))) = 3;
        K_rand_ind(K_rand_ind > KW_ind(1) & K_rand_ind <= sum(KW_ind(1:2))) = 2;
        K_rand_ind(K_rand_ind > 0 & K_rand_ind <= KW_ind(1)) = 1;
        KF = KF_pool(K_rand_ind)';
        KR = KR_pool(K_rand_ind)';
    else % updating probability values
        KW_ind = 0.95 * KW_ind + 0.05 * All_Imp;
        KW_ind = KW_ind ./ sum(KW_ind);
        K_rand_ind = rand(pop_size, 1);
        K_rand_ind(K_rand_ind > sum(KW_ind(1:3)) & K_rand_ind <= sum(KW_ind(1:4))) = 4;
        K_rand_ind(K_rand_ind > sum(KW_ind(1:2)) & K_rand_ind <= sum(KW_ind(1:3))) = 3;
        K_rand_ind(K_rand_ind > KW_ind(1) & K_rand_ind <= sum(KW_ind(1:2))) = 2;
        K_rand_ind(K_rand_ind > 0 & K_rand_ind <= KW_ind(1)) = 1;
        KF = KF_pool(K_rand_ind)';
        KR = KR_pool(K_rand_ind)';
    end

    %%% Junior and Senior Gaining-Sharing phases %%%
    D_Gained_Shared_Junior = ceil((problem_size) * (1 - nfes / max_nfes).^K);
    D_Gained_Shared_Senior = problem_size - D_Gained_Shared_Junior; %#ok<NASGU>
    pop = popold; % the old population becomes the current population

    %% Apply Fitness-Distance Balance (and Roulette FDB) methods, per case
    RfdbIndex = [];
    switch fdb_case
        case 1
            fdbIndex = fdb_score_best(pop, fitness);      % FDB_Func1
        case 2
            fdbIndex = fdb_score_ranking(pop, fitness);   % FDB_Func2 (descending ranking)
        case {3, 4}
            fdbIndex = fdb_score_best(pop, fitness);      % FDB_Func1
            RfdbIndex = fdb_score_roulette(pop, fitness); % RFDB_Func1
        case 5
            fdbIndex = fdb_score_best(pop, fitness);      % FDB_Func1
    end

    [~, indBest] = sort(fitness, 'ascend');
    [Rg1, Rg2, Rg3] = fdb_junior_r1r2r3(indBest, fdb_case, fdbIndex, RfdbIndex);
    [R1, R2, R3] = fdb_senior_r1r2r3(indBest, fdb_case, fdbIndex);
    R01 = 1:pop_size;
    Gained_Shared_Junior = zeros(pop_size, problem_size);
    ind1 = fitness(R01) > fitness(Rg3);

    if (sum(ind1) > 0)
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF(ind1) .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(Rg3(ind1), :) - pop(ind1, :));
    end
    ind1 = ~ind1;
    if (sum(ind1) > 0)
        Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF(ind1) .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(ind1, :) - pop(Rg3(ind1), :));
    end
    R0 = 1:pop_size;
    Gained_Shared_Senior = zeros(pop_size, problem_size);

    ind = fitness(R0) > fitness(R2);

    if (sum(ind) > 0)
        Gained_Shared_Senior(ind, :) = pop(ind, :) + KF(ind) .* (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
    end
    ind = ~ind;
    if (sum(ind) > 0)
        Gained_Shared_Senior(ind, :) = pop(ind, :) + KF(ind) .* (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
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

    children_fitness = problem.evaluate(ui); % reference loops problem() per row; same values

    %%% Updating solutions %%%
    for i = 1:pop_size
        nfes = nfes + 1;
        if nfes > max_nfes; break; end
        if children_fitness(i) < bsf_fit_var
            bsf_fit_var = children_fitness(i);
            bsf_solution = ui(i, :);
        end
    end

    %%% Calculate the improvement of each settings %%%
    dif = abs(fitness - children_fitness);
    % I == 1: the parent is better; I == 2: the offspring is better
    Child_is_better_index = (fitness > children_fitness);
    dif_val = dif(Child_is_better_index == 1); %#ok<NASGU> % computed but unused (as written)

    All_Imp = zeros(1, 4);

    for i = 1:4
        if (sum(and(Child_is_better_index, K_rand_ind == i)) > 0)
            All_Imp(i) = sum(dif(and(Child_is_better_index, K_rand_ind == i)));
        else
            All_Imp(i) = 0;
        end
    end

    if (sum(All_Imp) ~= 0)
        All_Imp = All_Imp ./ sum(All_Imp);
        [~, Imp_Ind] = sort(All_Imp);
        for imp_i = 1:length(All_Imp) - 1
            All_Imp(Imp_Ind(imp_i)) = max(All_Imp(Imp_Ind(imp_i)), 0.05);
        end
        All_Imp(Imp_Ind(end)) = 1 - sum(All_Imp(Imp_Ind(1:end-1)));
    else
        Imp_Ind = 1:length(All_Imp); %#ok<NASGU>
        All_Imp(:) = 1 / length(All_Imp);
    end
    [fitness, Child_is_better_index] = min([fitness, children_fitness], [], 2);

    popold = pop;
    popold(Child_is_better_index == 2, :) = ui(Child_is_better_index == 2, :);

    %% for resizing the population size %%%
    plan_pop_size = round((min_pop_size - max_pop_size) * ((nfes / max_nfes).^((1 - nfes / max_nfes))) + max_pop_size);

    if pop_size > plan_pop_size
        reduction_ind_num = pop_size - plan_pop_size;
        if pop_size - reduction_ind_num < min_pop_size; reduction_ind_num = pop_size - min_pop_size; end

        pop_size = pop_size - reduction_ind_num;
        for r = 1:reduction_ind_num
            [~, indBest] = sort(fitness, 'ascend');
            worst_ind = indBest(end);
            popold(worst_ind, :) = [];
            pop(worst_ind, :) = [];
            fitness(worst_ind, :) = [];
            K(worst_ind, :) = [];
        end
    end

    n_rec = n_rec + 1;
    conv_nfes(n_rec) = min(nfes, max_nfes); % recorded copy clipped (see above)
    conv_fit(n_rec) = bsf_fit_var;
end

%% Result assembly (docs/reference/matlab_interface.md)
% The reference Case files track no optimum/error; error semantics follow
% the interface contract.
if ~isnan(problem.optimum)
    err = bsf_fit_var - problem.optimum;
    if ~isnan(problem.target_error) && err < problem.target_error
        err = 0;
    end
else
    err = NaN;
end

params = struct();
params.fdb_case = fdb_case;
params.np_init = max_pop_size;
params.min_pop_size = min_pop_size;
params.kf_pool = KF_pool;
params.kr_pool = KR_pool;

result = struct();
result.optimizer = 'fdb-agsk';
result.suite = problem.suite;
result.func_id = problem.func_id;
result.dim = problem.dim;
result.seed = actual_seed;
result.best_x = bsf_solution;
result.best_fitness = bsf_fit_var;
result.error = err;
result.nfes = min(nfes, max_nfes); % counted evaluations; reference counter may read max_nfes+1
result.termination = 'max_evaluations'; % the reference never stops early
result.convergence = struct('nfes', conv_nfes(1:n_rec), 'best_fitness', conv_fit(1:n_rec));
result.runtime_seconds = toc(start_time);
result.params = params;
result.notes = '';
end

function [R1, R2, R3] = fdb_junior_r1r2r3(indBest, fdb_case, fdbIndex, RfdbIndex)
%FDB_JUNIOR_R1R2R3 Junior donor indices, per-case faithful transcription of
% the local Gained_Shared_Junior_R1R2R3 subfunctions in FDB_AGSK_Case1..5.m.
% Cases 1-2: standard ring neighbors + uniform random R3.
% Case 3: R2 overwritten by the RFDB roulette index, R3 by the FDB best
%         index (constants for every row).
% Case 4: R1 overwritten by the RFDB roulette index, R3 by the FDB best index.
% Case 5: R3 overwritten by the FDB best index.
% In every case the collision-regeneration loop then re-randomizes R3 where
% it collides with R0/R1/R2, exactly as the reference.

pop_size = length(indBest);
R0 = 1:pop_size;
R1 = [];
R2 = [];
R3 = []; %#ok<NASGU>

for i = 1:pop_size
    ind = find(indBest == i);
    if (ind == 1) % best
        R1(i) = indBest(2); %#ok<AGROW>
        R2(i) = indBest(3); %#ok<AGROW>
    elseif (ind == pop_size) % worst
        R1(i) = indBest(pop_size - 2); %#ok<AGROW>
        R2(i) = indBest(pop_size - 1); %#ok<AGROW>
    else
        R1(i) = indBest(ind - 1); %#ok<AGROW>
        R2(i) = indBest(ind + 1); %#ok<AGROW>
    end
end

switch fdb_case
    case {1, 2}
        R3 = floor(rand(1, pop_size) * pop_size) + 1;
    case 3
        % FDB and RFDB (Case3)
        R2 = ones(1, pop_size) * RfdbIndex;
        R3 = ones(1, pop_size) * fdbIndex;
    case 4
        % FDB and RFDB (Case4)
        R1 = ones(1, pop_size) * RfdbIndex;
        R3 = ones(1, pop_size) * fdbIndex;
    case 5
        % FDB (Case5)
        R3 = ones(1, pop_size) * fdbIndex;
end

for i = 1:99999999
    pos = ((R3 == R2) | (R3 == R1) | (R3 == R0));
    if sum(pos) == 0
        break;
    else % regenerate r3 if it collides
        R3(pos) = floor(rand(1, sum(pos)) * pop_size) + 1;
    end
    if i > 1000 % this has never happened so far
        error('Can not genrate R3 in 1000 iterations');
    end
end

end

function [R1, R2, R3] = fdb_senior_r1r2r3(indBest, fdb_case, fdbIndex)
%FDB_SENIOR_R1R2R3 Senior donor indices, per-case faithful transcription of
% the local Gained_Shared_Senior_R1R2R3 subfunctions in FDB_AGSK_Case1..5.m.
% Case 1: R2 = FDB best index (constant column); R1/R3 sampled from the
%         best/worst 5% partitions.
% Case 2: standard R1/R2; R3 sampled from the TAIL of the FDB descending
%         ranking (positions round(NP*0.95)+1..NP).
% Cases 3-5: standard AGSK senior partition (0.05 / middle / 0.95).

pop_size = length(indBest);

if fdb_case == 2
    fdbIndex = [fdbIndex]'; %#ok<NBRAK> % reference transposes the ranking to a column
end

R1 = indBest(1:round(pop_size * 0.05));
R1rand = ceil(length(R1) * rand(pop_size, 1));
R1 = R1(R1rand);

switch fdb_case
    case 1
        % FDB (Case1)
        R2 = ones(pop_size, 1) * fdbIndex;

        R3 = indBest(round(pop_size * 0.95) + 1:end); % orjinal
        R3rand = ceil(length(R3) * rand(pop_size, 1));
        R3 = R3(R3rand);
    case 2
        R2 = indBest(round(pop_size * 0.05) + 1:round(pop_size * 0.95)); % orjinal
        R2rand = ceil(length(R2) * rand(pop_size, 1));
        R2 = R2(R2rand);

        % FDB (Case2)
        R3 = fdbIndex(round(pop_size * 0.95) + 1:end); % orjinal
        R3rand = ceil(length(R3) * rand(pop_size, 1));
        R3 = R3(R3rand);
    otherwise % cases 3, 4, 5
        R2 = indBest(round(pop_size * 0.05) + 1:round(pop_size * 0.95)); % orjinal
        R2rand = ceil(length(R2) * rand(pop_size, 1));
        R2 = R2(R2rand);

        R3 = indBest(round(pop_size * 0.95) + 1:end); % orjinal
        R3rand = ceil(length(R3) * rand(pop_size, 1));
        R3 = R3(R3rand);
end

end

function vi = boundConstraint(vi, pop, lu)
%BOUNDCONSTRAINT Midpoint bound repair, transcribed from the local
% boundConstraint subfunction embedded in FDB_AGSK_Case1..5.m.

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
