function result = atmals_gsk_optimize(problem, options)
%ATMALS_GSK_OPTIMIZE Faithful MATLAB port of the ATMALS-GSK optimizer.
%
%   result = atmals_gsk_optimize(problem, options)
%   Adaptive GSK with memory-based parameter selection and a local search
%   around the best solution. Interface: docs/reference/matlab_interface.md.
%   options.seed is required (error 'atmals_gsk:options'). Optional: np
%   (default 100) and kf_pool, kr_pool, k_pool, p_pool, pls_pool; each pool
%   must contain its initial value (else error 'atmals_gsk:options').
%
% Sources, transcribed line by line:
%   historical source: atmalsgsk/atmalsgsk/cec2017/ATMALS_GSK.m
%   historical source: atmalsgsk/atmalsgsk/cec2011/ATMALS_GSK.m
%   historical source: atmalsgsk/atmalsgsk/cec2017/ProbUpdate.m
%       -> atmals_prob_update.m (atmals_gaussmf.m replaces the Fuzzy Logic
%          Toolbox gaussmf)
%   historical source: atmalsgsk/atmalsgsk/cec2017/RouletteWheelSelection.m
%       -> atmals_roulette_select.m
%   historical source: atmalsgsk/atmalsgsk/cec2017/boundConstraint.m
%       -> local function boundConstraint below
%   The cec2011 copies of the last three files are byte-identical.
%
% options.protocol picks which reference driver to reproduce
% (other values raise 'atmals_gsk:protocol'):
%   'cec2017' (default): G_Max = fix(max_nfes/np); Mean_Fit = mean of the
%       best half of abs(fitness - optimum); out-of-bound local-search
%       coordinates are clipped exactly to the bound; senior donors come
%       from atmals_senior_r1r2r3_cec2017 below (middle block
%       PartSize+1 .. NP-PartSize, unlike the shared src/common helper).
%   'cec2011': G_Max = max_nfes/np (no fix); Mean_Fit = mean of the best
%       half of the raw fitness (CEC2011 optima are unknown); out-of-bound
%       local-search coordinates go to bound+eps / bound-eps; senior donors
%       come from atmals_senior_r1r2r3_cec2011 below; problem_size == 1 has
%       its own senior-only branch.
%   If problem.optimum is NaN under 'cec2017', Mean_Fit falls back to the
%   cec2011 raw-fitness signal (the reference never ran that case).
%
% Reference quirks, kept on purpose (do NOT "fix"):
%   * The RP update uses the local-search range constants:
%     RP = RP_Min + (RangeLS_Max - RangeLS_Min)*(g/G_Max), so RP only grows
%     from 3 to about 3.2. RP_Max = 5 is defined but never used.
%   * The local search draws randperm(pop_size) into iii_mat, then changes
%     rows 1..NLS of ui, not the rows in iii_mat. The unused draw is kept
%     because it consumes RNG state.
%   * The senior phase always uses the fixed P = 0.1 (P_GSK). The adaptive P
%     is picked by roulette every generation, but the senior phase never
%     uses it (both protocols).
%   * atmals_prob_update centers gaussmf on the pool INDEX and gives the
%     OLDEST reward row the LARGEST weight (see atmals_prob_update.m).
%
% RNG: gsk_set_rng(options) seeds it. The reference driver seeded from the
% clock (rand('seed', sum(100 * clock))); the runner passes a deterministic
% seed instead (legacy 'seed' generator in reference runs). Wall-clock
% seeding is never used.
% result.error: abs(best - optimum) for suite cec2017 under protocol
% 'cec2017', else best - optimum; set to 0 below problem.target_error
% (standard CEC value 1e-8); NaN when the optimum is unknown.

start_time = tic;

if ~isfield(options, 'seed') || isempty(options.seed)
    error('atmals_gsk:options', 'options.seed is required');
end
actual_seed = gsk_set_rng(options);   % options.rand_generator: threefry|twister|seed|state (default twister)

protocol = 'cec2017';
if isfield(options, 'protocol') && ~isempty(options.protocol)
    protocol = options.protocol;
end
if ~any(strcmp(protocol, {'cec2017', 'cec2011'}))
    error('atmals_gsk:protocol', ...
        'options.protocol must be ''cec2017'' or ''cec2011'' (got ''%s'')', protocol);
end
use_cec2011 = strcmp(protocol, 'cec2011');

problem_size = problem.dim;
max_nfes = problem.max_nfes;
lu = [problem.lb; problem.ub];
has_optimum = ~isnan(problem.optimum);

%% Parameter settings (same in both reference ATMALS_GSK.m files)
pop_size = 100;
if isfield(options, 'np') && ~isempty(options.np); pop_size = options.np; end

KF_GSK = 0.5;  % Knowledge Factor (initial)
KR_GSK = 0.9;  % Knowledge Ratio (initial)
K_GSK = 10;    % Knowledge Rate (initial)
P_GSK = 0.1;

KF_VAL = 0.2:0.1:0.8;
KR_VAL = 0.85:0.01:1;
K_VAL = 8:1:30;
P_VAL = 0.05:0.01:0.15;
PLS_VAL = 1:0.1:2;
if isfield(options, 'kf_pool') && ~isempty(options.kf_pool); KF_VAL = options.kf_pool; end
if isfield(options, 'kr_pool') && ~isempty(options.kr_pool); KR_VAL = options.kr_pool; end
if isfield(options, 'k_pool') && ~isempty(options.k_pool); K_VAL = options.k_pool; end
if isfield(options, 'p_pool') && ~isempty(options.p_pool); P_VAL = options.p_pool; end
if isfield(options, 'pls_pool') && ~isempty(options.pls_pool); PLS_VAL = options.pls_pool; end

alpha = 0.98;
PLS = 1;

% A custom pool must contain its hard-coded initial value: the first
% atmals_prob_update call finds it with abs(VALs - val) < eps and would
% crash in atmals_gaussmf without a match. Same test here; no RNG draws, and
% default runs are unaffected.
pool_checks = {'kf_pool', KF_VAL, KF_GSK; 'kr_pool', KR_VAL, KR_GSK; ...
    'k_pool', K_VAL, K_GSK; 'p_pool', P_VAL, P_GSK; 'pls_pool', PLS_VAL, PLS};
for c = 1:size(pool_checks, 1)
    if ~any(abs(pool_checks{c, 2} - pool_checks{c, 3}) < eps)
        error('atmals_gsk:options', ...
            ['options.%s must contain the hard-coded initial value %g ' ...
             '(the first-generation probability update looks it up in the pool)'], ...
            pool_checks{c, 1}, pool_checks{c, 3});
    end
end

NLS = round(0.05 * pop_size);

RP_Min = 3;
RP_Max = 5; %#ok<NASGU> % defined by the reference but never used (quirk kept)

RangeLS_Max = 0.2;
RangeLS_Min = 1e-10;

if use_cec2011
    G_Max = max_nfes / pop_size;       % cec2011 file: no fix()
else
    G_Max = fix(max_nfes / pop_size);  % cec2017 file
end

KF = KF_GSK;
KR = KR_GSK;
K = K_GSK;
P = P_GSK; %#ok<NASGU> % the senior phase never uses the adaptive P (reference quirk)

Prob_KF_OLDMAT = ones(1, length(KF_VAL));
Prob_KR_OLDMAT = ones(1, length(KR_VAL));
Prob_K_OLDMAT = ones(1, length(K_VAL));
Prob_P_OLDMAT = ones(1, length(P_VAL));
Prob_PLS_OLDMAT = ones(1, length(PLS_VAL));

%% Initialize the main population (reference one-liner, or runner X0)
% Reference runs pass no X0 and keep the original single-draw start.
% Unified (fair-comparison) runs pass the runner's X0 and the RNG state
% right after it, so every optimizer starts from the same population and
% the same next random number for the same problem and run.
popold = gsk_initial_population_from_options(options, pop_size, lu(1, :), lu(2, :));
gsk_restore_rng_after_initialization(options);
pop = popold;

fitness = problem.evaluate(pop);

% Mean_Fit: mean of the best half of the protocol's signal
if use_cec2011 || ~has_optimum
    aa = fitness;                          % cec2011 file (raw fitness, unknown optima)
else
    aa = abs(fitness - problem.optimum);   % cec2017 file
end
bb = sort(aa);
cc = bb(1:floor(pop_size/2));   % floor() handles an odd custom np; no effect for the default np = 100
Mean_Fit = mean(cc);

nfes = 0;
bsf_fit_var = 1e+300;
bsf_solution = pop(1, :); % always defined; the loop below sets it as the reference does

for i = 1:pop_size
    nfes = nfes + 1;
    if nfes > max_nfes; break; end
    if fitness(i) < bsf_fit_var
        bsf_fit_var = fitness(i);
        bsf_solution = pop(i, :);
    end
end

% Convergence trace, one entry per generation (required by the interface).
% The reference counter reads max_nfes+1 when a generation crosses the
% budget. Only the recorded copies are clipped to max_nfes; the loop counter
% keeps the reference behavior.
max_records = ceil(max_nfes / pop_size) + 2;
conv_nfes = zeros(max_records, 1);
conv_fit = zeros(max_records, 1);
n_rec = 1;
conv_nfes(n_rec) = min(nfes, max_nfes);
conv_fit(n_rec) = bsf_fit_var;
% Opt-in dynamics trace (options.log_trace): one row per generation, with
% the KF, KR, K, P and PLS values the adaptive tuning selected.
tr = gsk_trace_start(options, max_records);
if tr.on; tr = gsk_trace_add(tr, min(nfes, max_nfes), popold, lu(1, :), lu(2, :), {'kf', 'kr', 'k', 'p', 'pls'}, [KF KR K P PLS]); end

g = 0;
%% main loop
while nfes < max_nfes
    g = g + 1;

    if ~use_cec2011
        %% ---- protocol 'cec2017' generation (cec2017/ATMALS_GSK.m) ----
        D_Gained_Shared_Junior = ceil((problem_size) * (1 - g / G_Max).^(K * ones(pop_size, 1)));
        D_Gained_Shared_Senior = problem_size - D_Gained_Shared_Junior;
        pop = popold;

        [~, indBest] = sort(fitness, 'ascend');
        [Rg1, Rg2, Rg3] = Gained_Shared_Junior_R1R2R3(indBest); % shared src/common helper, same RNG draws

        [R1, R2, R3] = atmals_senior_r1r2r3_cec2017(indBest, P_GSK); % quirk: fixed P_GSK, not the adaptive P
        R01 = 1:pop_size;
        Gained_Shared_Junior = zeros(pop_size, problem_size);
        ind1 = fitness(R01) > fitness(Rg3);

        if (sum(ind1) > 0)
            Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(Rg3(ind1), :) - pop(ind1, :));
        end
        ind1 = ~ind1;
        if (sum(ind1) > 0)
            Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(ind1, :) - pop(Rg3(ind1), :));
        end
        R0 = 1:pop_size;
        Gained_Shared_Senior = zeros(pop_size, problem_size);
        ind = fitness(R0) > fitness(R2);
        if (sum(ind) > 0)
            Gained_Shared_Senior(ind, :) = pop(ind, :) + KF .* (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
        end
        ind = ~ind;
        if (sum(ind) > 0)
            Gained_Shared_Senior(ind, :) = pop(ind, :) + KF .* (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
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

        % Adaptive local search around the best-so-far solution
        RangeLS = RangeLS_Max - (RangeLS_Max - RangeLS_Min) * (g / G_Max);

        iii_mat = randperm(pop_size); % quirk: drawn (consumes RNG) but the loop below uses rows 1..NLS
        iii_mat = iii_mat(1:NLS); %#ok<NASGU>

        for iii = 1:NLS
            ui(iii, :) = bsf_solution;
            for jjj = 1:problem_size
                if rand < (PLS / problem_size)
                    ui(iii, jjj) = ui(iii, jjj) + (2 * rand - 1) * RangeLS * (lu(2, jjj) - lu(1, jjj));
                    if ui(iii, jjj) < lu(1, jjj)
                        ui(iii, jjj) = lu(1, jjj);      % cec2017 file: exact-bound clip
                    end
                    if ui(iii, jjj) > lu(2, jjj)
                        ui(iii, jjj) = lu(2, jjj);
                    end
                end
            end
        end

    else
        %% ---- protocol 'cec2011' generation (cec2011/ATMALS_GSK.m) ----
        pop = popold;

        if (problem_size > 1)
            D_Gained_Shared_Junior = ceil((problem_size) * (1 - g / G_Max).^(K * ones(pop_size, 1)));
            D_Gained_Shared_Senior = problem_size - D_Gained_Shared_Junior; %#ok<NASGU>

            [~, indBest] = sort(fitness, 'ascend');
            [Rg1, Rg2, Rg3] = Gained_Shared_Junior_R1R2R3(indBest);

            [R1, R2, R3] = atmals_senior_r1r2r3_cec2011(indBest); % cec2011-local senior partition (P never passed)
            R01 = 1:pop_size;
            Gained_Shared_Junior = zeros(pop_size, problem_size);
            ind1 = fitness(R01) > fitness(Rg3);

            if (sum(ind1) > 0)
                Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(Rg3(ind1), :) - pop(ind1, :));
            end
            ind1 = ~ind1;
            if (sum(ind1) > 0)
                Gained_Shared_Junior(ind1, :) = pop(ind1, :) + KF .* (pop(Rg1(ind1), :) - pop(Rg2(ind1), :) + pop(ind1, :) - pop(Rg3(ind1), :));
            end
            R0 = 1:pop_size;
            Gained_Shared_Senior = zeros(pop_size, problem_size);
            ind = fitness(R0) > fitness(R2);
            if (sum(ind) > 0)
                Gained_Shared_Senior(ind, :) = pop(ind, :) + KF .* (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
            end
            ind = ~ind;
            if (sum(ind) > 0)
                Gained_Shared_Senior(ind, :) = pop(ind, :) + KF .* (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
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

            RangeLS = RangeLS_Max - (RangeLS_Max - RangeLS_Min) * (g / G_Max);

            iii_mat = randperm(pop_size); % quirk kept (see the cec2017 branch)
            iii_mat = iii_mat(1:NLS); %#ok<NASGU>

            for iii = 1:NLS
                ui(iii, :) = bsf_solution;
                for jjj = 1:problem_size
                    if rand < (PLS / problem_size)
                        ui(iii, jjj) = ui(iii, jjj) + (2 * rand - 1) * RangeLS * (lu(2, jjj) - lu(1, jjj));
                        if ui(iii, jjj) < lu(1, jjj)
                            ui(iii, jjj) = lu(1, jjj) + eps;  % cec2011 file: clip to bound +/- eps
                        end
                        if ui(iii, jjj) > lu(2, jjj)
                            ui(iii, jjj) = lu(2, jjj) - eps;
                        end
                    end
                end
            end

        else
            % cec2011 file: senior-only branch for problem_size == 1, with the
            % hard-coded KF = 0.5 and KR = 0.9 written in the reference
            D_Gained_Shared_Senior = problem_size; %#ok<NASGU>

            [~, indBest] = sort(fitness, 'ascend');
            [R1, R2, R3] = atmals_senior_r1r2r3_cec2011(indBest);
            R0 = 1:pop_size;
            Gained_Shared_Senior = zeros(pop_size, problem_size);
            ind = fitness(R0) > fitness(R2);
            if (sum(ind) > 0)
                Gained_Shared_Senior(ind, :) = pop(ind, :) + 0.5 .* (pop(R1(ind), :) - pop(ind, :) + pop(R2(ind), :) - pop(R3(ind), :));
            end
            ind = ~ind;
            if (sum(ind) > 0)
                Gained_Shared_Senior(ind, :) = pop(ind, :) + 0.5 .* (pop(R1(ind), :) - pop(R2(ind), :) + pop(ind, :) - pop(R3(ind), :));
            end
            Gained_Shared_Senior = boundConstraint(Gained_Shared_Senior, pop, lu);

            D_Gained_Shared_Senior_mask = ones(pop_size, problem_size);

            D_Gained_Shared_Senior_rand_mask = rand(pop_size, problem_size) <= 0.9;
            D_Gained_Shared_Senior_mask = and(D_Gained_Shared_Senior_mask, D_Gained_Shared_Senior_rand_mask);
            ui = pop;

            ui(D_Gained_Shared_Senior_mask) = Gained_Shared_Senior(D_Gained_Shared_Senior_mask);

            RangeLS = RangeLS_Max - (RangeLS_Max - RangeLS_Min) * (g / G_Max);

            iii_mat = randperm(pop_size); % quirk kept (see the cec2017 branch)
            iii_mat = iii_mat(1:NLS); %#ok<NASGU>

            for iii = 1:NLS
                ui(iii, :) = bsf_solution;
                for jjj = 1:problem_size
                    if rand < (PLS / problem_size)
                        ui(iii, jjj) = ui(iii, jjj) + (2 * rand - 1) * RangeLS * (lu(2, jjj) - lu(1, jjj));
                        if ui(iii, jjj) < lu(1, jjj)
                            ui(iii, jjj) = lu(1, jjj) + eps;
                        end
                        if ui(iii, jjj) > lu(2, jjj)
                            ui(iii, jjj) = lu(2, jjj) - eps;
                        end
                    end
                end
            end
        end
    end

    children_fitness = problem.evaluate(ui);

    %% Probability-table update + roulette parameter selection (both protocols)
    RP = RP_Min + (RangeLS_Max - RangeLS_Min) * (g / G_Max); % quirk: LS range constants, RP in [3, ~3.2]

    if use_cec2011 || ~has_optimum
        aa = children_fitness;                          % cec2011 signal
    else
        aa = abs(children_fitness - problem.optimum);   % cec2017 signal
    end
    bb = sort(aa);
    cc = bb(1:floor(pop_size/2));   % floor() handles an odd custom np; no effect for the default np = 100
    Mean_Fit_New = mean(cc);

    [Prob_KF, Prob_KF_OLDMAT] = atmals_prob_update(Prob_KF_OLDMAT, KF_VAL, KF, Mean_Fit, Mean_Fit_New, alpha);
    [Prob_KR, Prob_KR_OLDMAT] = atmals_prob_update(Prob_KR_OLDMAT, KR_VAL, KR, Mean_Fit, Mean_Fit_New, alpha);
    [Prob_K, Prob_K_OLDMAT] = atmals_prob_update(Prob_K_OLDMAT, K_VAL, K, Mean_Fit, Mean_Fit_New, alpha);
    [Prob_P, Prob_P_OLDMAT] = atmals_prob_update(Prob_P_OLDMAT, P_VAL, P, Mean_Fit, Mean_Fit_New, alpha);
    [Prob_PLS, Prob_PLS_OLDMAT] = atmals_prob_update(Prob_PLS_OLDMAT, PLS_VAL, PLS, Mean_Fit, Mean_Fit_New, alpha);

    ii = atmals_roulette_select(Prob_KF.^RP);
    KF = KF_VAL(ii);   % Knowledge Factor

    ii = atmals_roulette_select(Prob_KR.^RP);
    KR = KR_VAL(ii);   % Knowledge Ratio

    ii = atmals_roulette_select(Prob_K.^RP);
    K = K_VAL(ii);     % Knowledge Rate

    ii = atmals_roulette_select(Prob_P.^RP);
    P = P_VAL(ii); %#ok<NASGU> % the senior phase never uses it (reference quirk)

    ii = atmals_roulette_select(Prob_PLS.^RP);
    PLS = PLS_VAL(ii);

    Mean_Fit = Mean_Fit_New;

    %% Budget count and best-so-far update (reference budget-crossing rule)
    for i = 1:pop_size
        nfes = nfes + 1;
        if nfes > max_nfes; break; end
        if children_fitness(i) < bsf_fit_var
            bsf_fit_var = children_fitness(i);
            bsf_solution = ui(i, :);
        end
    end

    [fitness, Child_is_better_index] = min([fitness, children_fitness], [], 2);

    popold = pop;
    popold(Child_is_better_index == 2, :) = ui(Child_is_better_index == 2, :);

    n_rec = n_rec + 1;
    conv_nfes(n_rec) = min(nfes, max_nfes); % recorded copy clipped (see above)
    conv_fit(n_rec) = bsf_fit_var;
    if tr.on; tr = gsk_trace_add(tr, min(nfes, max_nfes), popold, lu(1, :), lu(2, :), {'kf', 'kr', 'k', 'p', 'pls'}, [KF KR K P PLS]); end
end

%% Result assembly (docs/reference/matlab_interface.md)
if has_optimum
    if strcmp(problem.suite, 'cec2017') && ~use_cec2011
        err = abs(bsf_fit_var - problem.optimum);
        if ~isnan(problem.target_error) && err < problem.target_error
            err = 0; % CEC2017 standard target error (1e-8)
        end
    else
        err = bsf_fit_var - problem.optimum;
        if ~isnan(problem.target_error) && err < problem.target_error
            err = 0;
        end
    end
else
    err = NaN;
end

params = struct();
params.protocol = protocol;
params.np = pop_size;
params.kf_init = KF_GSK;
params.kr_init = KR_GSK;
params.k_init = K_GSK;
params.p_gsk = P_GSK;
params.kf_pool = KF_VAL;
params.kr_pool = KR_VAL;
params.k_pool = K_VAL;
params.p_pool = P_VAL;
params.pls_pool = PLS_VAL;
params.alpha = alpha;
params.pls_init = 1;
params.nls = NLS;
params.rp_min = RP_Min;
params.rp_max = 5;
params.range_ls_max = RangeLS_Max;
params.range_ls_min = RangeLS_Min;

result = struct();
result.optimizer = 'atmals-gsk';
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
if tr.on; result.trace = gsk_trace_finish(tr); end   % only with options.log_trace
end

function [R1, R2, R3] = atmals_senior_r1r2r3_cec2017(indBest, P)
%ATMALS_SENIOR_R1R2R3_CEC2017 Faithful port of the cec2017-local senior helper.
% historical source: atmalsgsk/atmalsgsk/cec2017/Gained_Shared_Senior_R1R2R3.m
% Draws R1, R2, R3 (one per individual) from the best, middle and worst
% rank blocks, with PartSize = round(P*NP). Kept local because the middle
% block ends at NP-PartSize, while the shared src/common helper uses
% round(NP*(1-P)); the two differ whenever NP*P is an exact half-integer.

pop_size = length(indBest);

PartSize = round(P * pop_size);

R1 = indBest(1:PartSize);
R1rand = ceil(length(R1) * rand(pop_size, 1));
R1 = R1(R1rand);

R2 = indBest(PartSize + 1:pop_size - PartSize);
R2rand = ceil(length(R2) * rand(pop_size, 1));
R2 = R2(R2rand);

R3 = indBest(pop_size - PartSize + 1:end);
R3rand = ceil(length(R3) * rand(pop_size, 1));
R3 = R3(R3rand);

end

function [R1, R2, R3] = atmals_senior_r1r2r3_cec2011(indBest)
%ATMALS_SENIOR_R1R2R3_CEC2011 Faithful port of the cec2011-local senior helper.
% historical source: atmalsgsk/atmalsgsk/cec2011/Gained_Shared_Senior_R1R2R3.m
% No P argument: the block bounds are fixed at round(NP*0.1) and
% round(NP*0.9). These equal the shared src/common helper with P = 0.1
% (1 - 0.1 == 0.9 in double). The cec2017 helper above ends the middle
% block at NP - round(NP*0.1) instead; the two differ whenever
% round(NP*0.9) ~= NP - round(NP*0.1).

pop_size = length(indBest);

R1 = indBest(1:round(pop_size * 0.1));
R1rand = ceil(length(R1) * rand(pop_size, 1));
R1 = R1(R1rand);

R2 = indBest(round(pop_size * 0.1) + 1:round(pop_size * 0.9));
R2rand = ceil(length(R2) * rand(pop_size, 1));
R2 = R2(R2rand);

R3 = indBest(round(pop_size * 0.9) + 1:end);
R3rand = ceil(length(R3) * rand(pop_size, 1));
R3 = R3(R3rand);

end

function vi = boundConstraint(vi, pop, lu)
%BOUNDCONSTRAINT Midpoint bound repair, from the reference boundConstraint.m.
% A coordinate of vi below lb (above ub) is set to the midpoint between the
% parent value in pop and that bound. vi and pop are NP x D; lu is 2 x D
% ([lb; ub]). The file is byte-identical in the cec2017 and cec2011
% reference folders.

[NP, ~] = size(pop); % NP = population size

% check the lower bound
xl = repmat(lu(1, :), NP, 1);
pos = vi < xl;
vi(pos) = (pop(pos) + xl(pos)) / 2;

% check the upper bound
xu = repmat(lu(2, :), NP, 1);
pos = vi > xu;
vi(pos) = (pop(pos) + xu(pos)) / 2;
end
