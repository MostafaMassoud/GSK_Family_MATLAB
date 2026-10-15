function result = fdb_agsk_optimize(problem, options)
%FDB_AGSK_OPTIMIZE AGSK with Fitness-Distance Balance (FDB) guide selection.
%
%   result = fdb_agsk_optimize(problem, options)
%
% MATLAB port of all five FDB-AGSK reference cases. Historical sources
% (FDB-AGSK reference code):
%   FDB_AGSK_Case1.m .. FDB_AGSK_Case5.m  (self-contained; their local
%       Gained_Shared_* and boundConstraint helpers are transcribed here)
%   FDB_Func1.m  -> fdb_score_best.m
%   FDB_Func2.m  -> fdb_score_ranking.m
%   RFDB_Func1.m -> fdb_score_roulette.m
%   problem.m, problem_terminate.m  (reference driver: sphere objective,
%       D = 100, max_nfes = 1000*D, NP = 40*D)
%
% problem, options and result: docs/reference/matlab_interface.md.
% options.seed is required. Optional fields:
%   fdb_case      FDB variant, integer 1..5 (default 1, the canonical case)
%   np_init       initial NP (default 100; the reference driver uses 40*D)
%   min_pop_size  final NP (default 12; must be >= 11)
% Errors: fdb_agsk:options (no seed), fdb_agsk:invalid_case,
% fdb_agsk_optimize:options (bad np_init or min_pop_size).
% result.nfes and result.convergence.nfes are capped at max_nfes.
%
% FDB cases (which donor index the FDB guide replaces):
%   1  senior R2 = FDB best index (same guide for every row).
%   2  senior R3 drawn from the tail of the descending FDB ranking
%      (positions round(NP*0.95)+1..NP).
%   3  junior R2 = RFDB roulette index, junior R3 = FDB best index.
%   4  junior R1 = RFDB roulette index, junior R3 = FDB best index.
%   5  junior R3 = FDB best index.
% All other donors are standard AGSK: junior R1/R2 = rank neighbours, R3
% random; senior R1/R2/R3 from the top 5% / middle / bottom 5%.
% In cases 3-5 the injected indices replace the standard junior ones before
% the junior collision loop. That loop then re-draws R3 wherever it equals
% R0, R1 or R2, so the injected R3 is randomized there, as in the reference.
%
% AGSK steps (as in the Case files):
%   * Population reduction from np_init to min_pop_size:
%     plan = round((min-max)*((nfes/max_nfes)^(1-nfes/max_nfes)) + max);
%     the current worst is removed one at a time, with its row of K.
%   * KF_pool = [0.1 1.0 0.5 1.0], KR_pool = [0.2 0.1 0.9 0.9]. Setting
%     probabilities are [0.85 0.05 0.05 0.05] while nfes < 0.1*max_nfes,
%     then KW_ind = 0.95*KW_ind + 0.05*All_Imp (normalized); All_Imp has a
%     0.05 floor and its largest entry takes the remainder.
%   * Knowledge rate K per individual: uniform(0,1) with prob 0.5, else the
%     integer ceil(20*rand); D_junior = ceil(D*(1-nfes/max_nfes).^K).
%
% Notes on the port:
%   * Seeding through gsk_set_rng(options) makes runs deterministic; the
%     reference uses the MATLAB session RNG state. This is the only
%     intended modernization.
%   * The reference stores only the best fitness, not the solution, in the
%     initial scan, and would crash at its final disp(bsf_solution) if no
%     child ever beat the initial best. This port also stores the solution,
%     so result.best_x is always set. Bookkeeping only: no RNG draw and no
%     change to the search.
%   * The reference assumes np_init < 0.1*max_nfes (true for 40*D vs
%     1000*D); otherwise its first KW_ind update uses an empty KW_ind and
%     errors. An isempty(KW_ind) test on the phase condition prevents this;
%     on the reference budget the nfes test fires first, so results match.
%   * dif_val is computed and never used, as in the reference.
%   * The reference runs only on its sphere driver; running FDB-AGSK on the
%     CEC suites through the problem interface is a toolkit extension (see
%     README.md).

start_time = tic;

if ~isfield(options, 'seed') || isempty(options.seed)
    error('fdb_agsk:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % direct calls default to 'twister'; also threefry|seed|state

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

% Default NP = 100, the CEC2017 competition value used by GSK/AGSK (verified
% to reproduce fdb-agsk_cec2017_D10.csv within 0.2%). Set options.np_init
% to 40*D for the reference driver value.
pop_size = 100;
if isfield(options, 'np_init') && ~isempty(options.np_init); pop_size = options.np_init; end

KF_pool = [0.1 1.0 0.5 1.0];
KR_pool = [0.2 0.1 0.9 0.9];

%% Population size settings
max_pop_size = pop_size;
min_pop_size = 12;
if isfield(options, 'min_pop_size') && ~isempty(options.min_pop_size); min_pop_size = options.min_pop_size; end
% The P = 0.05 senior partition needs non-empty best and worst blocks
% (round(0.05*NP) >= 1 and NP - round(0.95*NP) >= 1), so every NP the
% reduction can reach must be >= 11. Checked before any RNG draw.
if ~(isscalar(max_pop_size) && isscalar(min_pop_size) && ...
        min_pop_size >= 11 && max_pop_size >= min_pop_size)
    error('fdb_agsk_optimize:options', ...
        ['min_pop_size must be >= 11 (the P = 0.05 senior partition needs ' ...
         'NP >= 11) and np_init >= min_pop_size; got np_init=%s, min_pop_size=%s'], ...
        mat2str(max_pop_size), mat2str(min_pop_size));
end

%% Initial population
% Reproduction runs pass no X0 and use the original single rand draw.
% Unified comparison runs pass the runner's X0 and the RNG state after it,
% so every optimizer starts from the same population and the same next
% random number on the same CEC cell.
popold = gsk_initial_population_from_options(options, pop_size, lu(1, :), lu(2, :));
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop); % same values as the reference's per-row loop

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = pop(1, :); % not in the reference (see header)

for i = 1:pop_size
    nfes = nfes + 1;
    if nfes > max_nfes; break; end
    if fitness(i) < bsf_fit_var
        bsf_fit_var = fitness(i);
        bsf_solution = pop(i, :); % bookkeeping only; not in the reference
    end
end

%% Knowledge rate K (one per individual)
K = [];
KF = []; %#ok<NASGU>
KR = []; %#ok<NASGU>
Kind = rand(pop_size, 1);
% K is uniform in (0,1) with prob 0.5, else a uniform integer in 1..20.
K(Kind < 0.5, :) = rand(sum(Kind < 0.5), 1);
K(Kind >= 0.5, :) = ceil(20 * rand(sum(Kind >= 0.5), 1));

% Convergence record, one entry per generation (interface requirement).
% The per-child counter reads max_nfes+1 when a generation crosses the
% budget. Only the recorded copies are clipped at max_nfes; the loop counter
% that drives the KW phase, junior schedule and resize plan is unchanged.
max_records = ceil(max_nfes / max(min_pop_size, 1)) + 2;
conv_nfes = zeros(max_records, 1);
conv_fit = zeros(max_records, 1);
n_rec = 1;
conv_nfes(n_rec) = min(nfes, max_nfes);
conv_fit(n_rec) = bsf_fit_var;

g = 0; %#ok<NASGU>
%% Main loop

KW_ind = [];
All_Imp = zeros(1, 4);

while nfes < max_nfes
    g = g + 1; %#ok<NASGU>

    % Pick a KF/KR setting (1..4) per individual with probabilities KW_ind.
    % The isempty test guards np_init >= 0.1*max_nfes, where generation 1
    % would update an empty KW_ind (see header); results are unchanged.
    if (isempty(KW_ind) || nfes < 0.1 * max_nfes) % fixed initial probabilities
        KW_ind = [0.85 0.05 0.05 0.05];
        K_rand_ind = rand(pop_size, 1);
        K_rand_ind(K_rand_ind > sum(KW_ind(1:3)) & K_rand_ind <= sum(KW_ind(1:4))) = 4;
        K_rand_ind(K_rand_ind > sum(KW_ind(1:2)) & K_rand_ind <= sum(KW_ind(1:3))) = 3;
        K_rand_ind(K_rand_ind > KW_ind(1) & K_rand_ind <= sum(KW_ind(1:2))) = 2;
        K_rand_ind(K_rand_ind > 0 & K_rand_ind <= KW_ind(1)) = 1;
        KF = KF_pool(K_rand_ind)';
        KR = KR_pool(K_rand_ind)';
    else % adapt probabilities from last generation's All_Imp
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

    %%% Junior and senior gaining-sharing phases %%%
    % Number of junior dimensions per individual; it shrinks as nfes grows.
    D_Gained_Shared_Junior = ceil((problem_size) * (1 - nfes / max_nfes).^K);
    D_Gained_Shared_Senior = problem_size - D_Gained_Shared_Junior; %#ok<NASGU>
    pop = popold;

    %% FDB (and roulette FDB) guide indices for this case
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
    % Junior trial: move toward Rg3 if it is better, away from it otherwise.
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
    % Senior trial: move toward R2 if it is better, away from it otherwise.
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

    % Each dimension takes the junior trial with prob D_junior/D, else the
    % senior trial; it then changes only with prob KR (else keeps pop).
    D_Gained_Shared_Junior_mask = rand(pop_size, problem_size) <= (D_Gained_Shared_Junior ./ problem_size);
    D_Gained_Shared_Senior_mask = ~D_Gained_Shared_Junior_mask;

    D_Gained_Shared_Junior_rand_mask = rand(pop_size, problem_size) <= KR;
    D_Gained_Shared_Junior_mask = and(D_Gained_Shared_Junior_mask, D_Gained_Shared_Junior_rand_mask);

    D_Gained_Shared_Senior_rand_mask = rand(pop_size, problem_size) <= KR;
    D_Gained_Shared_Senior_mask = and(D_Gained_Shared_Senior_mask, D_Gained_Shared_Senior_rand_mask);
    ui = pop;

    ui(D_Gained_Shared_Junior_mask) = Gained_Shared_Junior(D_Gained_Shared_Junior_mask);
    ui(D_Gained_Shared_Senior_mask) = Gained_Shared_Senior(D_Gained_Shared_Senior_mask);

    children_fitness = problem.evaluate(ui); % same values as the reference's per-row loop

    %%% Count evaluations and update the best so far %%%
    for i = 1:pop_size
        nfes = nfes + 1;
        if nfes > max_nfes; break; end
        if children_fitness(i) < bsf_fit_var
            bsf_fit_var = children_fitness(i);
            bsf_solution = ui(i, :);
        end
    end

    %%% Improvement made by each KF/KR setting %%%
    dif = abs(fitness - children_fitness);
    Child_is_better_index = (fitness > children_fitness);
    dif_val = dif(Child_is_better_index == 1); %#ok<NASGU> % unused, as in the reference

    All_Imp = zeros(1, 4);

    for i = 1:4
        if (sum(and(Child_is_better_index, K_rand_ind == i)) > 0)
            All_Imp(i) = sum(dif(and(Child_is_better_index, K_rand_ind == i)));
        else
            All_Imp(i) = 0;
        end
    end

    % Normalize; each share except the largest gets a 0.05 floor and the
    % largest takes the remainder. No improvement at all: equal shares.
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
    % Keep the better of parent and child. Child_is_better_index is now
    % 1 (parent kept, also on ties) or 2 (child is better).
    [fitness, Child_is_better_index] = min([fitness, children_fitness], [], 2);

    popold = pop;
    popold(Child_is_better_index == 2, :) = ui(Child_is_better_index == 2, :);

    %% Population size reduction
    plan_pop_size = round((min_pop_size - max_pop_size) * ((nfes / max_nfes).^((1 - nfes / max_nfes))) + max_pop_size);

    if pop_size > plan_pop_size
        reduction_ind_num = pop_size - plan_pop_size;
        if pop_size - reduction_ind_num < min_pop_size; reduction_ind_num = pop_size - min_pop_size; end

        pop_size = pop_size - reduction_ind_num;
        % Remove the current worst, one at a time, with its row of K.
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
    conv_nfes(n_rec) = min(nfes, max_nfes); % clipped copy (see above)
    conv_fit(n_rec) = bsf_fit_var;
end

%% Result assembly (docs/reference/matlab_interface.md)
% The reference tracks no error. Per the interface: error = best - optimum,
% 0 when below target_error, NaN when the optimum is unknown.
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
result.nfes = min(nfes, max_nfes); % the loop counter may read max_nfes+1
result.termination = 'max_evaluations'; % the reference never stops early
result.convergence = struct('nfes', conv_nfes(1:n_rec), 'best_fitness', conv_fit(1:n_rec));
result.runtime_seconds = toc(start_time);
result.params = params;
result.notes = '';
end

function [R1, R2, R3] = fdb_junior_r1r2r3(indBest, fdb_case, fdbIndex, RfdbIndex)
%FDB_JUNIOR_R1R2R3 Junior donor indices R1, R2, R3 for one FDB case.
% Transcribes the local Gained_Shared_Junior_R1R2R3 of FDB_AGSK_Case1..5.m.
% indBest: indices sorted by ascending fitness; fdbIndex: FDB best index
% (used in cases 3-5); RfdbIndex: RFDB roulette index (cases 3-4).
% Outputs are 1 x NP row vectors.
% Standard: R1/R2 are the next better / next worse individual by rank (the
% best uses ranks 2 and 3, the worst ranks NP-2 and NP-1); R3 is random.
% Cases 1-2: standard.
% Case 3: R2 = RFDB roulette index, R3 = FDB best index (same for every row).
% Case 4: R1 = RFDB roulette index, R3 = FDB best index.
% Case 5: R3 = FDB best index.
% In every case R3 is then re-drawn wherever it equals R0, R1 or R2, as in
% the reference.

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
        R2 = ones(1, pop_size) * RfdbIndex;
        R3 = ones(1, pop_size) * fdbIndex;
    case 4
        R1 = ones(1, pop_size) * RfdbIndex;
        R3 = ones(1, pop_size) * fdbIndex;
    case 5
        R3 = ones(1, pop_size) * fdbIndex;
end

for i = 1:99999999
    pos = ((R3 == R2) | (R3 == R1) | (R3 == R0));
    if sum(pos) == 0
        break;
    else % re-draw R3 where it collides
        R3(pos) = floor(rand(1, sum(pos)) * pop_size) + 1;
    end
    if i > 1000 % safety limit; never reached so far
        error('Can not genrate R3 in 1000 iterations');
    end
end

end

function [R1, R2, R3] = fdb_senior_r1r2r3(indBest, fdb_case, fdbIndex)
%FDB_SENIOR_R1R2R3 Senior donor indices R1, R2, R3 for one FDB case.
% Transcribes the local Gained_Shared_Senior_R1R2R3 of FDB_AGSK_Case1..5.m.
% indBest: indices sorted by ascending fitness; fdbIndex: FDB best index
% (cases 1, 3-5) or the descending FDB ranking (case 2). Outputs are NP x 1.
% Standard AGSK: R1, R2, R3 are drawn at random from the top 5%, the middle
% and the bottom 5% of indBest (split at round(0.05*NP), round(0.95*NP)).
% Case 1: R2 = FDB best index for every row; R1, R3 standard.
% Case 2: R1, R2 standard; R3 drawn from the tail of the FDB ranking
%         (positions round(NP*0.95)+1..NP).
% Cases 3-5: all standard.

pop_size = length(indBest);

if fdb_case == 2
    fdbIndex = [fdbIndex]'; %#ok<NBRAK> % as a column, as in the reference
end

R1 = indBest(1:round(pop_size * 0.05));
R1rand = ceil(length(R1) * rand(pop_size, 1));
R1 = R1(R1rand);

switch fdb_case
    case 1
        R2 = ones(pop_size, 1) * fdbIndex; % FDB guide

        R3 = indBest(round(pop_size * 0.95) + 1:end);
        R3rand = ceil(length(R3) * rand(pop_size, 1));
        R3 = R3(R3rand);
    case 2
        R2 = indBest(round(pop_size * 0.05) + 1:round(pop_size * 0.95));
        R2rand = ceil(length(R2) * rand(pop_size, 1));
        R2 = R2(R2rand);

        R3 = fdbIndex(round(pop_size * 0.95) + 1:end); % FDB ranking tail
        R3rand = ceil(length(R3) * rand(pop_size, 1));
        R3 = R3(R3rand);
    otherwise % cases 3, 4, 5
        R2 = indBest(round(pop_size * 0.05) + 1:round(pop_size * 0.95));
        R2rand = ceil(length(R2) * rand(pop_size, 1));
        R2 = R2(R2rand);

        R3 = indBest(round(pop_size * 0.95) + 1:end);
        R3rand = ceil(length(R3) * rand(pop_size, 1));
        R3 = R3(R3rand);
end

end

function vi = boundConstraint(vi, pop, lu)
%BOUNDCONSTRAINT Move out-of-bound values halfway between parent and bound.
% Transcribes the local boundConstraint of FDB_AGSK_Case1..5.m.
% vi, pop: NP x D (trial and parent); lu: 2 x D, [lower; upper].

[NP, ~] = size(pop);

% Below the lower bound: (parent + lower) / 2.
xl = repmat(lu(1, :), NP, 1);
pos = vi < xl;
vi(pos) = (pop(pos) + xl(pos)) / 2;

% Above the upper bound: (parent + upper) / 2.
xu = repmat(lu(2, :), NP, 1);
pos = vi > xu;
vi(pos) = (pop(pos) + xu(pos)) / 2;
end
