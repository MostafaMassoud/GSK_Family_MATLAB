function result = dt_gsk_optimize(problem, options)
%DT_GSK_OPTIMIZE DT-GSK: Dimension-Tiered Gaining-Sharing Knowledge-based
%optimization (minimisation).
%
% DT-GSK keeps the GSK junior/senior knowledge-sharing operators and adds:
%   * ACE, an adaptive configuration engine that draws (KF, KR, Kexp) per
%     individual from a small pool and learns the pool probabilities from the
%     fitness changes they produce (ARGP freezes entries that stop working);
%   * nonlinear population size reduction (NLPSR) from 5*D to n_min;
%   * linkage-aware crossover: some rows take whole blocks of dimensions;
%   * BSE, a budget-safe escape (Cauchy kicks and archive-seeded partial
%     restarts) plus a deep-stall full restart;
%   * deterministic refinement: coordinate local search on the elites and,
%     for D >= 50, a final compass polish.
% The mechanisms and their settings are fixed by the dimension tier of the
% published 'pub' profile (dt_gsk_config.m):
%   D < 20        single ACE memory, stagnation-triggered BSE
%   20 <= D < 50  top/bottom ACE memories, DE/rand/1 pool entry, KR floor,
%                 'triple' BSE trigger (stagnation + low acceptance + low diversity)
%   D >= 50       + learned linkage from the success graph (SGSM, dt_gsk_graph.m),
%                 wider senior groups for the bottom half, final polish
%   D >= 100      + TERRA budget policy, SP-NLPSR floor, basin-novelty restarts,
%                 late-acceptance clipping (A1), frozen-streak KR broadening (A2),
%                 learned/random linkage mixing (FC4); no DE entry
%
% Reference software and paper: DT-GSK v2.46,
% https://github.com/MostafaMassoud/DT-GSK; Masoud, Roshdy, Mohamed,
% "DT-GSK: Dimension-Tiered Adaptive Configuration Selection and
% Deterministic Refinement for Gaining-Sharing Knowledge-Based Optimization
% Algorithm", Algorithms (MDPI), 2026. The draw order and the order of the
% floating-point operations (sequential and NumPy pairwise sums, stable
% sorts) follow the reference, so a seed reproduces its runs exactly.
%
% Seeding: every random draw comes from one of the named Threefry substreams
% derived from options.seed (init, core, ace, div, bse, arch, link, de,
% basin), so one subsystem never shifts another's draws. DT-GSK samples its
% own initial population (fair-start exception: a runner X0 is ignored) and
% never touches the global RNG. options.rand_generator must be 'threefry'
% (or empty/'auto'/'default').
%
% Scope: only the pub profile is implemented. Not included: options that no
% pub tier selects (LHS/oversampled initialisation, Nelder-Mead/subspace
% local search, event-triggered local search, state-driven DE policy,
% hysteresis module gate, coverage-weighted ACE, per-half ARGP memories,
% linkage reliability probes), research hooks and telemetry/generation logs.
%
% Interface: result = dt_gsk_optimize(problem, options); see
% docs/reference/matlab_interface.md. The run always uses the full budget;
% the convergence trace is the best-so-far value after each generation.

start_time = tic;

if ~isfield(options, 'seed') || isempty(options.seed)
    error('dt_gsk_optimize:options', 'options.seed is required');
end
if isfield(options, 'rand_generator') && ~isempty(options.rand_generator) && ...
        ~any(strcmpi(char(options.rand_generator), {'threefry', 'auto', 'default'}))
    error('dt_gsk_optimize:options', ...
        'DT-GSK draws from Threefry substreams only; got rand_generator ''%s''.', char(options.rand_generator));
end
if problem.dim <= 0 || problem.max_nfes <= 0
    error('dt_gsk_optimize:problem', 'problem.dim and problem.max_nfes must be positive.');
end
D = fix(double(problem.dim));            % integer-valued doubles, whatever class was passed
max_nfes = fix(double(problem.max_nfes));
lb = double(problem.lb(:).') .* ones(1, D);
ub = double(problem.ub(:).') .* ones(1, D);
span = ub - lb;
inv_sqrt_d = 1 / sqrt(D);
fobj = problem.evaluate;
cfg = dt_gsk_config(D);

%% Random substreams
% The child seed of a stream is fixed by its position k in the reference
% list init(0) core(1) ace(2) kexp(3) div(4) bse(5) arch(6) link(7) de(8)
% control(9) flow(10) basin(11) trust(12); unused streams are not created.
seed = fix(double(options.seed));
if seed < 0
    error('dt_gsk:valueError', 'Seed must be a non-negative integer, got %g.', seed);
end
substream = @(k) RandStream('threefry', 'Seed', mod(seed + 1000003 * (k + 1), 2147483646) + 1);
rs_init = RandStream('threefry', 'Seed', seed);
rs_core = substream(1);    % GSK sources and crossover masks
rs_ace = substream(2);     % ACE pool sampling
rs_div = substream(4);     % Cauchy kicks
rs_bse = substream(5);     % restarts (partial and deep-stall)
rs_arch = substream(6);    % archive sampling
rs_link = substream(7);    % linkage groups and blockwise masks
rs_de = substream(8);      % DE/rand/1 entry
rs_basin = substream(11);  % basin-novelty restart candidates

%% Initial population
NP_init = cfg.np_init_mult * D;
pop = lb + rand(rs_init, NP_init, D) .* span;
[fit, nfes] = evaluate(fobj, pop, 0, max_nfes);
NP = numel(fit);
pop = pop(1:NP, :);
best_i = argmin(fit);
best_f = fit(best_i);
best_x = pop(best_i, :);
glob_f = best_f;           % best ever: a deep-stall restart may discard the incumbent
glob_x = best_x;
dsr_best_nfes = nfes;      % evaluations at the last incumbent improvement
dsr_last = -1;             % evaluations at the last deep-stall restart

%% ACE pool and probabilities
pool = cfg.ace_pool;                     % rows [KF KR Kexp]
probs = cfg.ace_init_probs;
modules = cfg.ace_modules;
de_entry = 0;                            % pool row of the DE/rand/1 entry (0 = none)
if cfg.de_entry
    pool(end + 1, :) = [cfg.de_F, cfg.de_CR, 0];
    probs = [probs * (1 - cfg.de_init_prob), cfg.de_init_prob];
    modules(end + 1) = false;
    de_entry = size(pool, 1);
end
M = size(pool, 1);
Kw = project_probs(probs, cfg.ace_min_prob);   % sampling probabilities; with ace_top_bottom
Kw_top = Kw;                                   % a blend of these top-half ...
Kw_bot = Kw;                                   % ... and bottom-half memories
frozen = false(1, M);                          % ARGP: frozen pool entries
argp_succ = zeros(cfg.argp_window, M);         % ARGP ring of per-entry successes ...
argp_samp = zeros(cfg.argp_window, M);         % ... and samples
argp_slot = 1;

%% Escape state, archive, basin memory
init_rad = pop_radius(pop, span);
div_floor = cfg.bse_div_floor * init_rad;
stag = best_f;                 % best_f over the last bse_window+1 generations
acc_hist = zeros(1, 0);        % acceptance rate over the last signal_window generations
div_hist = init_rad;           % population radius over the same window
restarts = 0;
cooldown_until = 0;
% Span normalisers of the archive (x .* inv_span) and basin (x ./ bspan) distances:
% the two zero-span guards round differently, so both forms are kept.
inv_span = 1 ./ span;
inv_span(span <= 0) = 0;
arch = archive_add(zeros(0, D), best_x, best_f, inv_span, inv_sqrt_d, cfg);
bspan = max(span, 1e-30);
basin = struct('C', zeros(0, D), 'F', zeros(0, 1));   % basin centres and fitness
if cfg.basin_memory
    basin = basin_add(basin, best_x, best_f, bspan, cfg);
end

%% Linkage, SGSM graph, local search, polish
link_on = D >= cfg.link_min_dim;
rand_groups = {};              % random partition of the dimensions
learned_groups = {};           % SGSM blocks plus singletons ({} = none)
if cfg.sgsm
    G = dt_gsk_graph(D);       % interaction graph (only referenced when cfg.sgsm)
end
graph_block_until = 0;         % no learned linkage before this generation
sp_count = 0;                  % generations that used learned linkage (SP-NLPSR)
ls_cap = max(1, floor(cfg.ls_budget * max_nfes));   % local-search evaluation budget
ls_used = 0;
ls_cursor = 0;                 % rotates the probed coordinate
ls_block_until = 0;
ls_restart_block_until = 0;
ls_min_step = cfg.ls_min_step * span;
fp_done = false;

% Late-budget controllers (D >= 100)
logdrop_ema = 0;               % EMA of log10(best-f drop)
logdrop_streak = 0;            % A1: generations with small drop and high acceptance
frozen_streak = 0;             % A2: generations with small drop and low acceptance
a2_window = 0;                 % A2: generations of KR broadening left
a2_cool = 0;                   % A2: cooldown generations left
lift_ema = 0;                  % FC4: EMA of learned minus random linkage acceptance
prev_best = best_f;

max_gen = ceil(max_nfes / min(cfg.n_min, NP_init)) + 1;
conv_nfes = zeros(max_gen, 1);
conv_fit = zeros(max_gen, 1);
gen = 0;

%% Main loop
while nfes < max_nfes
    gen = gen + 1;
    frac = nfes / max_nfes;    % budget fraction used at the start of the generation

    %% Population size reduction (NLPSR): NP = NP_init + (n_min - NP_init) * frac^(1-frac)
    n_min = cfg.n_min;
    if cfg.sp_nlpsr && frac < cfg.sp_release && sp_count < cfg.sp_min_samples
        n_min = max(n_min, cfg.sp_floor);   % SP-NLPSR: keep NP up until learned linkage has samples
    end
    n_min = min(n_min, NP_init);
    NP_new = floor(NP_init + (n_min - NP_init) * frac ^ (1 - frac) + 0.5);
    NP_new = max(n_min, min(NP_new, NP));
    [~, order] = sort(fit);
    if NP_new < NP             % keep the best NP_new individuals (the population is now sorted)
        pop = pop(order(1:NP_new), :);
        fit = fit(order(1:NP_new));
        NP = NP_new;
        order = (1:NP)';
    end
    div_rad = pop_radius(pop, span);

    %% Ranking and GSK knowledge sources
    rank = zeros(NP, 1);
    rank(order) = 1:NP;
    n_top = floor((NP + 1) / 2);
    top = rank <= n_top;                  % better half
    top_frac = n_top / NP;
    bot_frac = 1 - top_frac;
    [Rg1, Rg2, Rg3] = junior_sources(order, rs_core);
    % Senior sources: best / middle / worst groups. With split_senior and low
    % recent acceptance, the bottom half draws from wider groups (same draws).
    r1 = rand(rs_core, 1, NP);
    r2 = rand(rs_core, 1, NP);
    r3 = rand(rs_core, 1, NP);
    [R1, R2, R3] = senior_sources(order, r1, r2, r3, cfg.p_senior);
    if cfg.split_senior && numel(acc_hist) >= cfg.signal_window && ...
            mean0(acc_hist) <= cfg.bse_acc_floor
        [W1, W2, W3] = senior_sources(order, r1, r2, r3, cfg.p_senior_bottom);
        R1(~top) = W1(~top);
        R2(~top) = W2(~top);
        R3(~top) = W3(~top);
    end

    %% ACE: draw a pool entry (KF, KR, Kexp) per individual
    if cfg.ace_top_bottom
        s_idx = zeros(NP, 1);
        s_idx(top) = ace_sample(rs_ace, Kw_top, n_top);
        s_idx(~top) = ace_sample(rs_ace, Kw_bot, NP - n_top);
    else
        s_idx = ace_sample(rs_ace, Kw, NP);
    end
    KF = pool(s_idx, 1);
    KR = pool(s_idx, 2);
    kexp = pool(s_idx, 3);
    KR = max(KR, min(1, cfg.kr_min_dims / D));   % KR floor (kr_min_dims = 0: no floor)
    if a2_window > 0           % A2 broadening window is open
        KR = min(max(KR * cfg.a2_factor, 0), 1);
    end
    % Junior share of the dimensions, ceil(D*(1-frac)^Kexp)/D: junior early, senior late
    p_jun = ceil(D * (1 - frac) .^ kexp) / D;

    %% Linkage groups: random blocks, or learned SGSM blocks once the graph is mature
    groups = {};               % primary groups of the blockwise rows ({} = no linkage)
    groups2 = {};              % secondary (random) groups when learned ones are used
    p_primary = 1;             % share of blockwise rows using the primary groups
    if link_on
        if mod(gen - 1, cfg.link_refresh) == 0
            rand_groups = random_groups(D, cfg.link_block, rs_link);
        end
        groups = rand_groups;
        if cfg.sgsm
            thr = adaptive_threshold(G, cfg.ig_link_conf, cfg.ig_conf_pct, cfg.ig_conf_floor, ...
                cfg.ig_conf_min_samples, cfg.ig_conf_window);
            if gen >= graph_block_until && ...
                    ready(G, thr, cfg.ig_min_updates, cfg.ig_min_refreshes, cfg.ig_min_dims) && ...
                    ~isempty(learned_groups)
                groups = learned_groups;
                groups2 = rand_groups;
                sp_count = sp_count + 1;
                p_primary = cfg.ig_link_mix;
                % FC4: learned blocks that accept worse than random ones lose rows
                if cfg.fc4 && frac >= cfg.fc4_tau
                    if lift_ema <= cfg.fc4_severe
                        p_primary = 0;
                    elseif lift_ema <= cfg.fc4_negative
                        p_primary = p_primary * (1 - cfg.fc4_strength);
                    end
                end
            end
        end
    end

    % Module gate: escapes stay enabled while ACE favours module entries
    if cfg.ace_top_bottom
        mass = top_frac * seqsum(Kw_top(modules)) + bot_frac * seqsum(Kw_bot(modules));
    else
        mass = seqsum(Kw(modules));
    end
    modules_active = mass >= cfg.module_gate;

    %% Trial vectors: GSK junior/senior donors, crossover, DE entry
    [vj, vs] = gsk_donors(pop, fit, KF, Rg1, Rg2, Rg3, R1, R2, R3, lb, ub);
    [DJ, DS, rows1, rows2] = crossover_masks(rs_core, rs_link, p_jun, KR, D, ...
        groups, groups2, cfg.link_mix, p_primary);
    ui = pop;
    ui(DJ) = vj(DJ);
    ui(DS) = vs(DS);           % senior wins where both masks are set
    % Every trial changes at least one coordinate (random dim, junior or senior)
    miss = find(~(any(DJ, 2) | any(DS, 2)));
    if ~isempty(miss)
        n = numel(miss);
        cols = draw_int(rs_core, D, [1 n]);
        use_j = rand(rs_core, 1, n) <= p_jun(miss).';
        cell_j = sub2ind([NP D], miss(use_j).', cols(use_j));
        cell_s = sub2ind([NP D], miss(~use_j).', cols(~use_j));
        ui(cell_j) = vj(cell_j);
        ui(cell_s) = vs(cell_s);
    end
    % DE/rand/1/bin replaces the trials of individuals that drew the DE entry
    de_rows = false(NP, 1);
    if de_entry > 0
        de_rows = s_idx == de_entry;
        idx = find(de_rows);
        n = numel(idx);
        if n > 0
            keys = rand(rs_de, n, NP);         % three distinct random donors ~= self
            keys(sub2ind([n NP], (1:n)', idx)) = Inf;
            [~, donors] = sort(keys, 2);
            mutant = pop(donors(:, 1), :) + cfg.de_F * (pop(donors(:, 2), :) - pop(donors(:, 3), :));
            cross = rand(rs_de, n, D) < cfg.de_CR;
            cross(sub2ind([n D], (1:n)', draw_int(rs_de, D, [1 n]).')) = true;
            u = ui(idx, :);
            u(cross) = mutant(cross);
            ui(idx, :) = bound(u, pop(idx, :), lb, ub);
        end
    end

    %% Evaluation and greedy selection
    fit_old = fit;
    [y, nfes] = evaluate(fobj, ui, nfes, max_nfes);
    frac_sel = nfes / max_nfes;   % budget fraction after the offspring, before BSE/LS spend more
    n_child = numel(y);
    child = inf(NP, 1);
    child(1:n_child) = y;
    improved = child <= fit;
    improved(n_child + 1:end) = false;
    % A1: late in the run, while acceptance is high but progress tiny, demand a relative gain
    if cfg.a1 && logdrop_streak >= cfg.a1_streak && frac >= cfg.a1_tau && ...
            mean0(acc_hist) >= cfg.a1_acc_high
        improved = child < fit - cfg.a1_eps * abs(fit);   % false for unevaluated rows (Inf)
    end
    idx_imp = find(improved);
    accepted = numel(idx_imp);
    gain_pos = max(fit_old(idx_imp) - child(idx_imp), 0);   % graph weights (gains <= 0 are ignored)
    moves = zeros(0, D);       % accepted displacements (graph input)
    weights = [];
    if cfg.sgsm && accepted > 0
        moves = ui(idx_imp, :) - pop(idx_imp, :);
        weights = ones(accepted, 1);
        weights(de_rows(idx_imp)) = cfg.ig_de_weight;
    end
    pop(improved, :) = ui(improved, :);
    fit(improved) = child(improved);
    if accepted > 0
        arch = archive_add(arch, pop(idx_imp, :), fit(idx_imp), inv_span, inv_sqrt_d, cfg);
        if cfg.basin_memory
            k = idx_imp(argmin(fit(idx_imp)));
            basin = basin_add(basin, pop(k, :), fit(k), bspan, cfg);
        end
    end

    %% SGSM: learn the interaction graph from accepted moves, refresh learned blocks
    if cfg.sgsm && frac_sel >= cfg.ig_warmup
        if mod(gen, cfg.ig_update_period) == 0
            if cfg.ig_max_samples > 0 && numel(gain_pos) > cfg.ig_max_samples
                [~, o] = sort(-gain_pos);      % keep the largest improvements
                o = o(1:cfg.ig_max_samples);
                moves = moves(o, :);
                gain_pos = gain_pos(o);
                weights = weights(o);
            end
            update(G, moves, gain_pos, cfg.ig_decay, cfg.ig_lr, weights);
        else
            update(G, zeros(0, D), zeros(0, 1), cfg.ig_decay, cfg.ig_lr, []);   % decay only
        end
        if G.updates > 0 && (isempty(G.blocks) || mod(gen, cfg.ig_refresh) == 0)
            learned_groups = refresh_blocks(G, cfg, D);
        end
    end

    best_i = argmin(fit);
    best_f = fit(best_i);

    % Late-budget controller state (A1/A2): EMA of log10(best-f drop) and streaks
    if cfg.a1 || cfg.a2
        log_drop = log10(max(0, prev_best - best_f) + 1e-30);
        logdrop_ema = (1 - cfg.a1_alpha) * logdrop_ema + cfg.a1_alpha * log_drop;
        prev_best = best_f;
        acc_prev = mean0(acc_hist);
        if logdrop_ema < cfg.a1_log_drop && acc_prev >= cfg.a1_acc_high
            logdrop_streak = logdrop_streak + 1;
        else
            logdrop_streak = 0;
        end
        if logdrop_ema < cfg.a2_log_drop && acc_prev < cfg.a2_acc_floor
            frozen_streak = frozen_streak + 1;
        else
            frozen_streak = 0;
        end
        a2_window = max(0, a2_window - 1);
        a2_cool = max(0, a2_cool - 1);
        if cfg.a2 && frozen_streak >= cfg.a2_streak && a2_cool == 0 && a2_window == 0
            a2_window = cfg.a2_window;
            a2_cool = cfg.a2_window + cfg.a2_cooldown;
            frozen_streak = 0;
        end
    end

    %% ACE probability update: entries are rewarded by their summed fitness changes
    if frac_sel >= cfg.ace_start
        delta = child(1:n_child) - fit_old(1:n_child);
        s = s_idx(1:n_child);
        if cfg.ace_top_bottom
            t = top(1:n_child);
            if any(t)
                Kw_top = ace_update(Kw_top, accumarray(s(t), delta(t), [M 1]).', cfg);
            end
            if any(~t)
                Kw_bot = ace_update(Kw_bot, accumarray(s(~t), delta(~t), [M 1]).', cfg);
            end
            Kw = project_probs(top_frac * Kw_top + bot_frac * Kw_bot, cfg.ace_min_prob);
        else
            Kw = ace_update(Kw, accumarray(s, delta, [M 1]).', cfg);
        end
    end

    %% ARGP: freeze pool entries whose rolling acceptance rate is too low
    argp_samp(argp_slot, :) = accumarray(s_idx, 1, [M 1]).';
    argp_succ(argp_slot, :) = accumarray(s_idx(improved), 1, [M 1]).';
    argp_slot = mod(argp_slot, cfg.argp_window) + 1;
    n_s = sum(argp_samp, 1);
    rate = zeros(1, M);
    rate(n_s > 0) = sum(argp_succ(:, n_s > 0), 1) ./ n_s(n_s > 0);
    if frac_sel >= cfg.argp_warmup
        n_free = sum(~frozen);
        for k = 1:M            % freeze in pool order, keeping at least two entries
            if frozen(k)
                continue
            end
            if n_free <= 2
                break
            end
            if rate(k) < cfg.argp_threshold
                frozen(k) = true;
                n_free = n_free - 1;
            end
        end
        frozen(frozen & n_s > 0 & rate >= cfg.argp_threshold) = false;   % recovered entries
        if any(frozen)         % frozen entries keep p_min, the others share the rest
            free = ~frozen;
            Kw(free) = Kw(free) * ((1 - sum(frozen) * cfg.ace_min_prob) / sum(Kw(free)));
            Kw(frozen) = cfg.ace_min_prob;
            Kw_top = Kw;       % both half memories restart from the redistributed probabilities
            Kw_bot = Kw;
        end
    end

    %% Escape signals: stagnation of best_f, low acceptance, low diversity
    acc_hist = push(acc_hist, accepted / n_child, cfg.signal_window);
    div_hist = push(div_hist, div_rad, cfg.signal_window);
    stag = push(stag, best_f, cfg.bse_window + 1);
    escape = numel(stag) > cfg.bse_window && isfinite(stag(1)) && isfinite(best_f) && ...
        max(0, stag(1) - best_f) / max(abs(stag(1)), 1) < cfg.bse_eps;
    if cfg.bse_triple
        escape = escape && numel(acc_hist) >= cfg.signal_window && ...
            mean0(acc_hist) <= cfg.bse_acc_floor && ...
            mean0(div_hist) <= div_floor;
    end

    %% BSE: Cauchy kick on the worst rows, then (if still stuck) a partial restart
    if modules_active && restarts < cfg.bse_max_restarts && frac_sel < cfg.bse_stop && ...
            nfes >= cooldown_until && escape
        best_before = best_f;
        [~, ranked] = sort(fit);
        n_keep = min(max(1, floor(cfg.bse_freeze_frac * NP + 0.5)), NP - 1);
        rpool = ranked(n_keep + 1:end);          % non-elite rows, best to worst
        % Cauchy kick: heavy-tailed moves of the worst rows, kept when not worse
        % (n >= 1: at least one non-elite row and budget left before bse_stop)
        n = min([max(1, floor(cfg.cauchy_frac * NP + 0.5)), numel(rpool), max_nfes - nfes]);
        ic = rpool(end - n + 1:end);
        z = tan(pi * (min(max(rand(rs_div, n, D), 1e-15), 1 - 1e-15) - 0.5));
        Xc = bound(pop(ic, :) + (cfg.cauchy_scale * inv_sqrt_d * span) .* z, pop(ic, :), lb, ub);
        [yc, nfes] = evaluate(fobj, Xc, nfes, max_nfes);
        keep = yc <= fit(ic);
        if any(keep)
            pop(ic(keep), :) = Xc(keep, :);
            fit(ic(keep)) = yc(keep);
            arch = archive_add(arch, pop(ic(keep), :), fit(ic(keep)), inv_span, inv_sqrt_d, cfg);
        end
        best_i = argmin(fit);
        best_f = fit(best_i);
        if best_f < best_before                  % the kick found progress: no restart
            stag = best_f;
            escape = false;
        end
        % Partial restart of the worst rows: archive elites with jitter, or
        % fresh points (the most novel w.r.t. known basins when basin memory is on)
        if escape
            n = min(max(1, floor(cfg.bse_restart_frac * NP + 0.5)), numel(rpool));
            ir = rpool(end - n + 1:end);
            ir = ir(1:min(n, max_nfes - nfes));  % the kick may have used the last evaluations
            n = numel(ir);
            if n > 0
                Xn = zeros(n, D);
                from_arch = false(1, n);
                if ~isempty(arch)
                    from_arch = rand(rs_bse, 1, n) < cfg.bse_arch_prob;
                end
                for k = find(from_arch)
                    j = draw_int(rs_arch, size(arch, 1), [1 1]);
                    jitter = (rand(rs_bse, 1, D) - 0.5) * 2.0;
                    Xn(k, :) = arch(j, :) + (cfg.bse_jitter * inv_sqrt_d * span) .* jitter;
                end
                fresh = find(~from_arch);
                if ~isempty(fresh)
                    if cfg.basin_memory
                        cand = lb + rand(rs_basin, numel(fresh) * cfg.basin_pool_mult, D) .* span;
                        [~, o] = sort(basin_novelty(basin, cand, bspan));
                        Xn(fresh, :) = cand(o(end - numel(fresh) + 1:end), :);
                    else
                        Xn(fresh, :) = lb + rand(rs_bse, numel(fresh), D) .* span;
                    end
                end
                Xn = bound(Xn, pop(ir, :), lb, ub);
                [yn, nfes] = evaluate(fobj, Xn, nfes, max_nfes);
                pop(ir, :) = Xn;
                fit(ir) = yn;
                arch = archive_add(arch, Xn, yn, inv_span, inv_sqrt_d, cfg);
                if cfg.basin_memory
                    k = argmin(yn);
                    basin = basin_add(basin, Xn(k, :), yn(k), bspan, cfg);
                end
                restarts = restarts + 1;
                cooldown_until = nfes + max(0, floor(cfg.bse_cooldown * max_nfes + 0.5));
                ls_restart_block_until = max(ls_restart_block_until, gen + cfg.ls_restart_cooldown);
                best_i = argmin(fit);
                best_f = fit(best_i);
                stag = best_f;
            end
        end
        div_hist(end) = pop_radius(pop, span);   % diversity signal of the post-escape population
        if cfg.sgsm                % weaken the graph and pause learned linkage
            restart_decay(G, cfg.ig_restart_decay);
            graph_block_until = max(graph_block_until, gen + cfg.ig_restart_cooldown);
            if G.updates > 0
                learned_groups = refresh_blocks(G, cfg, D);
            end
        end
    end

    %% Local search: +/- one coordinate step around each elite (endgame, capped budget)
    ls_moves = zeros(0, D);
    ls_gain = zeros(1, 0);
    frac_ls = nfes / max_nfes;
    if frac_ls >= cfg.ls_start && ls_used < ls_cap && nfes < max_nfes && mod(gen, cfg.ls_period) == 0 && ...
            gen >= ls_restart_block_until && gen >= ls_block_until && ...
            (~cfg.budget_policy || frac_sel >= cfg.terra_ls_start)   % TERRA: pre-escape fraction
        n_ls = min(max_nfes - nfes, ls_cap - ls_used);
        n_el = min(cfg.ls_elites, NP);
        [~, o] = sort(fit);
        elites = o(1:n_el);
        scale = max(std(pop, 1, 1), ls_min_step);
        [~, coord] = sort(-scale);               % widest coordinates first
        % step shrinks linearly from 1x to 0.25x between ls_start and the end of the budget
        step_decay = max(0.25, 1 - 0.75 * max(0, min(1, (frac_ls - cfg.ls_start) / max(1e-12, 1 - cfg.ls_start))));
        % Elite e is probed at +step (row 2e-1), then -step (row 2e), along its own
        % rotating coordinate; an elite with step 0 (fixed variable, lb == ub) is skipped.
        X = repelem(pop(elites, :), 2, 1);
        probe = true(2 * n_el, 1);
        for e = 1:n_el
            c = coord(mod(ls_cursor + e - 1, D) + 1);
            step = cfg.ls_step * scale(c) * step_decay;
            probe(2 * e - 1:2 * e) = step > 0 && step < Inf;
            X(2 * e - 1, c) = X(2 * e - 1, c) + step;
            X(2 * e, c) = X(2 * e, c) - step;
        end
        rows = find(probe, n_ls);                % budget cap
        if ~isempty(rows)                        % nothing to probe: no evaluation, cursor move or cooldown
            owner = ceil(rows / 2);              % elite position of each proposal
            X = bound(X(rows, :), pop(elites(owner), :), lb, ub);
            [y, nfes] = evaluate(fobj, X, nfes, max_nfes);   % n_ls fits in the budget
            ls_used = ls_used + numel(y);
            ok = y <= fit(elites(owner));
            moved = zeros(0, 1);
            for e = 1:n_el                       % each elite takes its best non-worse probe
                k = find(owner == e & ok);
                if isempty(k)
                    continue
                end
                [yb, kb] = min(y(k));
                r = elites(e);
                ls_moves(end + 1, :) = X(k(kb), :) - pop(r, :); %#ok<AGROW>
                ls_gain(end + 1) = max(0, fit(r) - yb); %#ok<AGROW>
                pop(r, :) = X(k(kb), :);
                fit(r) = yb;
                moved(end + 1, 1) = r; %#ok<AGROW>
            end
            if ~isempty(moved)
                arch = archive_add(arch, pop(moved, :), fit(moved), inv_span, inv_sqrt_d, cfg);
                best_i = argmin(fit);
                best_f = fit(best_i);
                stag = best_f;
            end
            ls_cursor = mod(ls_cursor + n_el, D);
            ls_block_until = max(ls_block_until, gen + cfg.ls_cooldown);
        end
    end

    %% Final polish: one compass search from the incumbent along the SGSM eigenbasis
    % (runs once; best_i is current here)
    if cfg.final_polish && ~fp_done && nfes / max_nfes >= cfg.fp_start && nfes < max_nfes
        fp_done = true;
        n_fp = min(max_nfes - nfes, floor(cfg.fp_budget * max_nfes));
        [x, fx, nfes] = compass(fobj, pop(best_i, :), best_f, polish_basis(G, D), lb, ub, span, ...
            nfes, max_nfes, n_fp, cfg.fp_step, cfg.fp_min_step);
        if fx < best_f
            pop(best_i, :) = x;
            fit(best_i) = fx;
            best_f = fx;
        end
    end

    % Local-search moves also teach the graph (down-weighted; ls_start > ig_warmup)
    if cfg.sgsm && ~isempty(ls_gain)
        update(G, ls_moves, ls_gain, 1.0, cfg.ig_lr, repmat(cfg.ig_ls_weight, 1, numel(ls_gain)));
        if G.updates > 0
            learned_groups = refresh_blocks(G, cfg, D);
        end
    end
    best_x = pop(best_i, :);

    %% Deep-stall restart: re-sample the whole population when the incumbent
    % has not improved for dsr_frac of the budget (the best ever is kept aside)
    if best_f < glob_f
        glob_f = best_f;
        glob_x = best_x;
        dsr_best_nfes = nfes;
    end
    if max_nfes >= cfg.dsr_min_budget && (nfes - dsr_best_nfes) / max_nfes >= cfg.dsr_frac && ...
            (dsr_last < 0 || nfes - dsr_last >= cfg.dsr_cooldown * max_nfes) && ...
            nfes / max_nfes < cfg.dsr_stop
        n = min(NP, max_nfes - nfes);
        Xd = lb + rand(rs_bse, n, D) .* span;
        [yd, nfes] = evaluate(fobj, Xd, nfes, max_nfes);
        pop(1:n, :) = Xd;
        fit(1:n) = yd;
        best_i = argmin(fit);
        best_f = fit(best_i);
        best_x = pop(best_i, :);
        stag = best_f;
        dsr_best_nfes = nfes;
        dsr_last = nfes;
    end

    % FC4: EMA of the acceptance lift of learned over random blockwise rows
    if cfg.fc4 && ~isempty(groups2) && ~isempty(rows1) && ~isempty(rows2)
        lift = sum(improved(rows1)) / numel(rows1) - sum(improved(rows2)) / numel(rows2);
        lift_ema = (1 - cfg.fc4_alpha) * lift_ema + cfg.fc4_alpha * lift;
    end

    conv_nfes(gen) = nfes;
    conv_fit(gen) = best_f;
end

%% Result
if glob_f < best_f
    best_f = glob_f;
    best_x = glob_x;
end
if gen == 0
    conv_nfes = nfes;
    conv_fit = best_f;
    gen = 1;
end
if isnan(problem.optimum)
    err = NaN;
else
    err = best_f - problem.optimum;
    if ~isnan(problem.target_error) && err < problem.target_error
        err = 0;
    end
end
result = struct();
result.optimizer = 'dt-gsk';
result.suite = problem.suite;
result.func_id = problem.func_id;
result.dim = problem.dim;
result.seed = options.seed;
result.best_x = best_x;
result.best_fitness = best_f;
result.error = err;
result.nfes = nfes;
result.termination = 'max_evaluations';
result.convergence = struct('nfes', conv_nfes(1:gen), 'best_fitness', cummin(conv_fit(1:gen)));
result.runtime_seconds = toc(start_time);
result.params = struct('profile', 'pub', 'np_init_mult', cfg.np_init_mult, 'n_min', cfg.n_min, ...
    'KF', cfg.KF, 'KR', cfg.KR, 'Kexp', cfg.Kexp, 'restarts_done', restarts, 'max_nfes', max_nfes);
result.notes = 'self-init (fair-start exception)';
end

%% ------------------------------------------------------------------------
function [y, nfes] = evaluate(fobj, X, nfes, max_nfes)
% Evaluate the leading rows of X that still fit in the budget (every caller
% leaves at least one evaluation).
n = min(size(X, 1), max_nfes - nfes);
if n < size(X, 1)
    X = X(1:n, :);
end
y = reshape(double(fobj(X)), [], 1);
nfes = nfes + n;
end

function i = argmin(v)
% First minimum; a NaN wins (NumPy argmin).
i = find(isnan(v), 1);
if isempty(i)
    [~, i] = min(v);
end
end

function s = seqsum(v)
% Left-to-right sum (the reference's summation order).
s = 0;
for k = 1:numel(v)
    s = s + v(k);
end
end

function m = mean0(v)
% Mean of a signal window, 0 when empty.
m = 0;
if ~isempty(v)
    m = seqsum(v) / numel(v);
end
end

function v = push(v, x, n)
% Append x to the signal window v, keeping its last n values.
v = [v(max(1, end - n + 2):end), x];
end

function v = draw_int(rs, n, sz)
% Uniform integers 1..n of size sz (one double per value).
v = min(floor(rand(rs, sz) * n) + 1, n);
end

function v = bound(v, parent, lb, ub)
% Midpoint repair (L-SHADE): a violated coordinate goes halfway from its
% parent to the violated bound.
lo = v < lb;
hi = ~lo & v > ub;
if any(lo(:))
    r = (parent + lb) * 0.5;
    v(lo) = r(lo);
end
if any(hi(:))
    r = (parent + ub) * 0.5;
    v(hi) = r(hi);
end
end

function rad = pop_radius(pop, span)
% Mean distance to the centroid divided by ||span|| (sequential sums), in [0, 1].
n = size(pop, 1);
if n <= 1
    rad = 0;
    return
end
s = cumsum(pop, 1);
mu = s(end, :) / n;
d = pop - mu;
d = cumsum(d .* d, 2);
d = cumsum(sqrt(d(:, end)));
s = cumsum(span .* span);
rad = min(max((d(end) / n) / sqrt(s(end)), 0), 1);
end

function [R1, R2, R3] = junior_sources(order, rs)
% Junior sources: the rank neighbours (better R1, worse R2; the best and the
% worst use the two next ones) and a random third individual, the first valid
% entry of a pre-drawn candidate pool (NP x 32 draws).
NP = numel(order);
cand = draw_int(rs, NP, [NP 32]);
pos = zeros(NP, 1);
pos(order) = 1:NP;
lo = pos - 1;
hi = pos + 1;
lo(pos == 1) = 2;
hi(pos == 1) = 3;
lo(pos == NP) = NP - 2;
hi(pos == NP) = NP - 1;
R1 = order(lo);
R2 = order(hi);
valid = cand ~= (1:NP)' & cand ~= R1 & cand ~= R2;
[found, a] = max(valid, [], 2);
R3 = cand(sub2ind([NP 32], (1:NP)', a));
for i = find(~found)'          % (practically never) smallest valid index
    R3(i) = find((1:NP)' ~= i & (1:NP)' ~= R1(i) & (1:NP)' ~= R2(i), 1);
end
end

function [R1, R2, R3] = senior_sources(order, r1, r2, r3, p)
% Senior sources from the best / middle / worst groups (sizes n, NP-2n, n;
% p <= 0.15 and NP >= 5, so the groups never overlap).
NP = numel(order);
n = max(1, floor(p * NP + 0.5));
m = NP - 2 * n;
R1 = order(min(max(ceil(r1(:) * n), 1), n));
R2 = order(n + min(max(ceil(r2(:) * m), 1), m));
R3 = order(NP - n + min(max(ceil(r3(:) * n), 1), n));
end

function [vj, vs] = gsk_donors(pop, fit, KF, Rg1, Rg2, Rg3, R1, R2, R3, lb, ub)
% GSK junior and senior donor vectors with midpoint bound repair:
%   junior: x + KF*(x_R1 - x_R2 + x_R3 - x)  if x is worse than x_R3, else x + KF*(x_R1 - x_R2 + x - x_R3)
%   senior: x + KF*(x_p - x_w + x_m - x)     if x is worse than x_m,  else x + KF*(x_p - x_w + x - x_m)
d = pop(Rg1, :) - pop(Rg2, :);
b = fit > fit(Rg3);
d(b, :) = d(b, :) + pop(Rg3(b), :) - pop(b, :);
d(~b, :) = d(~b, :) + pop(~b, :) - pop(Rg3(~b), :);
vj = bound(pop + KF .* d, pop, lb, ub);
d = pop(R1, :) - pop(R3, :);
b = fit > fit(R2);
d(b, :) = d(b, :) + pop(R2(b), :) - pop(b, :);
d(~b, :) = d(~b, :) + pop(~b, :) - pop(R2(~b), :);
vs = bound(pop + KF .* d, pop, lb, ub);
end

function [DJ, DS, rows1, rows2] = crossover_masks(rs_core, rs_link, p_jun, KR, D, groups, groups2, mix, p_primary)
% Junior (DJ) / senior (DS) crossover masks. Scalar rows decide every
% dimension separately (junior with prob p_jun, kept with prob KR). With
% linkage, a 'mix' share of rows decides per group of dimensions instead;
% when learned groups exist, a p_primary share of those rows uses them
% (rows1) and the rest the random groups (rows2).
NP = numel(p_jun);
rows1 = zeros(0, 1);
rows2 = zeros(0, 1);
if isempty(groups)
    [DJ, DS] = scalar_masks(rs_core, p_jun, KR, D);
    return
end
blockwise = (rand(rs_link, 1, NP) <= mix).';
DJ = false(NP, D);
DS = false(NP, D);
s = find(~blockwise);
if ~isempty(s)
    [DJ(s, :), DS(s, :)] = scalar_masks(rs_core, p_jun(s), KR(s), D);
end
b = find(blockwise);
if isempty(b)
    return
end
rows1 = b;
if ~isempty(groups2) && p_primary < 1
    primary = rand(rs_link, 1, numel(b)) <= p_primary;
    rows1 = b(primary);
    rows2 = b(~primary);
end
[DJ, DS] = block_masks(rs_link, rows1, groups, p_jun, KR, DJ, DS);
[DJ, DS] = block_masks(rs_link, rows2, groups2, p_jun, KR, DJ, DS);
end

function [DJ, DS] = scalar_masks(rs, p_jun, KR, D)
% Per-dimension masks from one fused draw of 3*n*D uniforms.
n = numel(p_jun);
r = rand(rs, 1, 3 * n * D);
jun = reshape(r(1:n * D), n, D) <= p_jun;
DJ = jun & (reshape(r(n * D + 1:2 * n * D), n, D) <= KR);
DS = ~jun & (reshape(r(2 * n * D + 1:end), n, D) <= KR);
end

function [DJ, DS] = block_masks(rs, rows, groups, p_jun, KR, DJ, DS)
% Blockwise masks: per (row, group) one junior/senior draw and one KR gate.
if isempty(rows)
    return
end
jun = rand(rs, numel(rows), numel(groups)) <= p_jun(rows);
gate = rand(rs, numel(rows), numel(groups)) <= KR(rows);
for g = 1:numel(groups)
    DJ(rows(gate(:, g) & jun(:, g)), groups{g}) = true;
    DS(rows(gate(:, g) & ~jun(:, g)), groups{g}) = true;
end
end

function groups = random_groups(D, b, rs)
% Random partition of 1..D into blocks of b (one permutation, D draws).
[~, perm] = sort(rand(rs, 1, D));
groups = cell(1, ceil(D / b));
for g = 1:numel(groups)
    groups{g} = sort(perm((g - 1) * b + 1:min(g * b, D)));
end
end

function groups = refresh_blocks(G, cfg, D)
% Re-extract the SGSM blocks; learned linkage groups = blocks + singletons.
extract_blocks(G, cfg.ig_edge_floor, cfg.ig_block_min, cfg.ig_block_max);
groups = {};
if ~isempty(G.blocks)
    groups = linkage_groups(G, D);
end
end

function s = ace_sample(rs, p, n)
% Roulette-wheel draw of n pool entries (left-closed CDF bins).
c = cumsum(p);
c(end) = 1;
s = 1 + sum(rand(rs, 1, n).' > c(1:end - 1), 2);
end

function Kw = ace_update(Kw, omega, cfg)
% Blend the probabilities towards the share of the total fitness decrease
% each entry produced (only the improving entries when the total rose).
s = seqsum(omega);
if ~isfinite(s) || s == 0
    Kw = project_probs(Kw, cfg.ace_min_prob);
    return
end
if s >= 0
    neg = omega < 0;
    s = seqsum(omega(neg));
    if s == 0 || ~isfinite(s)
        Kw = project_probs(Kw, cfg.ace_min_prob);
        return
    end
    target = zeros(size(omega));
    target(neg) = omega(neg) / s;
else
    target = omega / s;
end
target = project_probs(target, cfg.ace_min_prob);
Kw = project_probs((1 - cfg.ace_lr) * Kw + cfg.ace_lr * target, cfg.ace_min_prob);
end

function out = project_probs(v, p_min)
% Euclidean projection onto {p >= p_min, sum(p) = 1} (Duchi et al.), then
% floor at p_min and renormalise.
n = numel(v);
s = 1 - p_min * n;
a = v - p_min;
u = flip(sort(a));
cssv = cumsum(u);
rho = find(u - (cssv - s) ./ (1:n) > 0, 1, 'last');
x = a - (cssv(rho) - s) / rho;
x(x < 0) = 0;
out = x + p_min;
out = out / seqsum(out);
out(out < p_min) = p_min;
out = out / seqsum(out);
end

function A = archive_add(A, X, F, inv_span, inv_sqrt_d, cfg)
% Elite archive: a candidate joins only if its normalised distance to every
% member is >= arch_dist; when full it replaces the nearest member.
for k = 1:size(X, 1)
    if ~isfinite(F(k))
        continue
    end
    if ~isempty(A)
        d = (A - X(k, :)) .* inv_span;
        d = cumsum(d .* d, 2);
        d = sqrt(d(:, end)) * inv_sqrt_d;
        if any(d < cfg.arch_dist)
            continue
        end
        if size(A, 1) >= cfg.arch_max
            [d_min, j] = min(d);
            if d_min < 1e30
                A(j, :) = X(k, :);
            end
            continue
        end
    end
    A(end + 1, :) = X(k, :); %#ok<AGROW>
end
end

function B = basin_add(B, x, f, bspan, cfg)
% Basin memory: merge x into the nearest basin within basin_dist (keeping
% the better centre), else add a new basin; over capacity keep the best.
if isempty(B.F)
    B.C = x;
    B.F = f;
    return
end
d = basin_dist(B.C, x, bspan);
j = argmin(d);
if d(j) <= cfg.basin_dist
    if f < B.F(j)
        B.C(j, :) = x;
        B.F(j) = f;
    end
    return
end
B.C(end + 1, :) = x;
B.F(end + 1, 1) = f;
if numel(B.F) > cfg.basin_max
    [~, o] = sort(B.F);
    B.C = B.C(o(1:cfg.basin_max), :);
    B.F = B.F(o(1:cfg.basin_max));
end
end

function nov = basin_novelty(B, X, bspan)
% Novelty of each candidate row: distance to its nearest known basin.
nov = zeros(1, size(X, 1));
for i = 1:size(X, 1)
    nov(i) = min(basin_dist(B.C, X(i, :), bspan));
end
end

function d = basin_dist(C, x, bspan)
% Normalised L2 distances (NumPy pairwise row sums) from x to the rows of C.
Z = (C - x) ./ bspan;
d = sqrt(np_rowsum(Z .* Z)) / sqrt(numel(x));
end

function s = np_rowsum(A)
% NumPy pairwise sum of every row: 8 running sums up to 128 columns, halving
% above (n >= 64 here, since basin memory runs only for D >= 100).
n = size(A, 2);
if n <= 128
    m = n - mod(n, 8);
    r = A(:, 1:8);
    for i = 9:8:m
        r = r + A(:, i:i + 7);
    end
    s = ((r(:, 1) + r(:, 2)) + (r(:, 3) + r(:, 4))) + ((r(:, 5) + r(:, 6)) + (r(:, 7) + r(:, 8)));
    for i = m + 1:n
        s = s + A(:, i);
    end
else
    h = floor(n / 2);
    h = h - mod(h, 8);
    s = np_rowsum(A(:, 1:h)) + np_rowsum(A(:, h + 1:n));
end
end

function [x, fx, nfes] = compass(fobj, x, fx, basis, lb, ub, span, nfes, max_nfes, cap, step_frac, min_frac)
% Compass search: probe x +/- step along one basis row at a time; a success
% moves there and grows the step (x1.3), a failure moves to the next
% direction, a full failed sweep halves the step. cap <= remaining budget.
smax = max(span);
step = step_frac * smax;
n_dir = size(basis, 1);
used = 0;
k = 0;
fails = 0;
while used < cap && step >= min_frac * smax
    dirv = basis(mod(k, n_dir) + 1, :);
    cand = min(max([x + step * dirv; x - step * dirv], lb), ub);
    [y, nfes] = evaluate(fobj, cand(1:min(2, cap - used), :), nfes, max_nfes);
    used = used + numel(y);
    j = argmin(y);
    if y(j) < fx
        fx = y(j);
        x = cand(j, :);
        step = min(step * 1.3, 0.5 * smax);
        fails = 0;
    else
        k = k + 1;
        fails = fails + 1;
        if fails >= n_dir
            step = step * 0.5;
            fails = 0;
        end
    end
end
end
