function c = dt_gsk_config(D)
%DT_GSK_CONFIG Parameters of the DT-GSK 'pub' profile for dimension D.
%
%   c = dt_gsk_config(D)
%
% Returns a struct with only the parameters dt_gsk_optimize reads. The values
% shared by all tiers come first; each dimension tier (D < 20, 20 <= D < 50,
% D >= 50, D >= 100) then changes values or switches on its own mechanisms.
% Smaller tiers return early, so a setting made outside an 'if D < ...'
% block also holds for every larger D unless a later tier changes it.
% Budget fractions are fractions of max_nfes.

%% Common to all tiers
% Population and GSK operators
c.np_init_mult = 5;          % initial population NP = 5*D
c.n_min = 12;                % final population size of NLPSR
c.KF = 0.5;                  % base GSK knowledge factor   (reported only; ACE picks KF)
c.KR = 0.9;                  % base GSK knowledge ratio    (reported only; ACE picks KR)
c.Kexp = 10;                 % base GSK knowledge exponent (reported only; ACE picks Kexp)
c.p_senior = 0.05;           % senior best/worst group fraction
c.split_senior = false;      % bottom half uses wider senior groups when acceptance is low
c.p_senior_bottom = 0.10;    % senior group fraction of those wider groups

% ACE (adaptive configuration engine) and ARGP (pool pruning)
c.ace_pool = [0.1 0.2  2     % [KF KR Kexp]: cautious explorer
              1.0 0.1 15     %   dimension-selective bold
              0.5 0.9 10     %   GSK-pure (baseline values)
              1.0 0.9  5     %   aggressive wide
              0.5 0.9  3];   %   extended-exploration GSK
c.ace_init_probs = [0.05 0.05 0.45 0.05 0.40];   % initial probabilities
c.ace_modules = [true true false true true];  % entries whose mass keeps BSE enabled
c.module_gate = 0.30;        % BSE only runs while that mass is >= this
c.ace_lr = 0.10;             % learning rate of the probability update
c.ace_start = 0.05;          % budget fraction before probabilities adapt
c.ace_min_prob = 0.05;       % probability floor per entry
c.ace_top_bottom = false;    % separate probabilities for the top and bottom half
c.kr_min_dims = 0;           % KR floor: at least this many dims changed, on average
c.de_entry = false;          % add a DE/rand/1 entry to the pool
c.de_F = 0.5;                % DE scale factor
c.de_CR = 0.9;               % DE crossover rate
c.de_init_prob = 0.20;       % initial probability of the DE entry
c.argp_window = 30;          % ARGP rolling window (generations)
c.argp_threshold = 0.02;     % freeze entries whose acceptance rate falls below this
c.argp_warmup = 0.15;        % no freezing before this budget fraction

% Linkage-aware (blockwise) crossover
c.link_block = 5;            % random linkage block size
c.link_min_dim = 10;         % linkage only for D >= this
c.link_mix = 0.70;           % share of rows that use blockwise masks
c.link_refresh = 20;         % generations between random re-partitions

% BSE (budget-safe escape) and elite archive
c.bse_triple = false;        % BSE also needs low acceptance and low diversity
c.bse_window = 50;           % stagnation window (generations)
c.bse_eps = 1e-8;            % relative improvement that counts as progress
c.signal_window = 10;        % rolling window of the acceptance/diversity signals
c.bse_acc_floor = 0.10;      % low-acceptance threshold
c.bse_div_floor = 0.35;      % low-diversity threshold, relative to the initial radius
c.bse_max_restarts = 2;      % partial restarts per run
c.bse_restart_frac = 0.10;   % share of NP re-seeded by a restart
c.bse_cooldown = 0.05;       % no BSE for this budget fraction after a restart
c.bse_stop = 0.95;           % no escapes after this budget fraction
c.bse_freeze_frac = 0.05;    % elite share protected from kicks and restarts
c.bse_arch_prob = 0.50;      % chance a restart row is seeded from the archive
c.bse_jitter = 0.10;         % archive-seed jitter (fraction of span / sqrt(D))
c.cauchy_frac = 0.10;        % share of NP (worst rows) given a Cauchy kick
c.cauchy_scale = 0.05;       % Cauchy scale (fraction of span / sqrt(D))
c.arch_max = 200;            % archive capacity
c.arch_dist = 0.05;          % minimum normalised distance between archive members

% Coordinate local search (endgame)
c.ls_start = 0.80;           % budget fraction where it may start
c.ls_budget = 0.02;          % total evaluation share
c.ls_elites = 2;             % elites probed per call
c.ls_period = 1;             % generations between calls
c.ls_step = 0.20;            % step = ls_step * std of the coordinate
c.ls_min_step = 0.001;       % std floor (fraction of span)
c.ls_restart_cooldown = 8;   % generations without LS after a restart
c.ls_cooldown = 6;           % generations without LS after an LS call

% Deep-stall full restart
c.dsr_frac = 0.25;           % incumbent frozen for this budget fraction
c.dsr_cooldown = 0.15;       % budget fraction between deep-stall restarts
c.dsr_stop = 0.90;           % none after this budget fraction
c.dsr_min_budget = 20000;    % disabled for smaller budgets

% Mechanisms switched on by higher tiers
c.sgsm = false;              % success-graph structural memory (dt_gsk_graph)
c.final_polish = false;      % one-shot compass search near the end
c.budget_policy = false;     % TERRA: local search only after terra_ls_start of the budget
c.terra_ls_start = 0.70;     %   (judged before the escape step spends evaluations)
c.sp_nlpsr = false;          % sample-protected NLPSR population floor
c.basin_memory = false;      % basin-novelty restart sampling
c.a1 = false;                % late acceptance clipping
c.a2 = false;                % frozen-streak KR broadening
c.fc4 = false;               % learned/random linkage mixing by lift

%% Tier D < 20
if D < 20
    c.bse_restart_frac = 0.30;
    c.bse_max_restarts = 4;
    return
end

%% Tier 20 <= D < 50
% The next four settings hold for every D >= 20 (D >= 100 turns de_entry off).
c.ace_top_bottom = true;
c.de_entry = true;
c.bse_triple = true;
c.cauchy_scale = 0.04;
if D < 50
    c.p_senior = 0.15;
    c.kr_min_dims = 20;
    c.de_init_prob = 0.10;
    c.link_mix = 0.40;
    c.bse_restart_frac = 0.30;
    c.ls_budget = 0.01;
    c.ls_elites = 3;
    return
end

%% Tier D >= 50
c.n_min = 25;
c.split_senior = true;
c.kr_min_dims = 40;
c.argp_threshold = 0.01;
c.link_block = 10;
c.link_min_dim = 30;
c.link_refresh = 10;
c.bse_max_restarts = 4;
c.ls_start = 0.70;
c.ls_budget = 0.05;
c.ls_elites = 5;
c.ls_step = 0.10;

% SGSM interaction graph (dt_gsk_graph)
c.sgsm = true;
c.ig_decay = 0.95;           % per-generation decay of the graph
c.ig_lr = 1.0;               % learning rate of graph updates
c.ig_warmup = 0.10;          % budget fraction before the graph learns
c.ig_update_period = 1;      % generations between structural updates
c.ig_max_samples = 0;        % keep only the largest improvements per update (0 = all)
c.ig_refresh = 5;            % generations between block extractions
c.ig_edge_floor = 1e-4;      % edge weight floor of block extraction
c.ig_block_min = 2;          % learned block size limits
c.ig_block_max = 10;
c.ig_link_conf = 0.35;       % static confidence gate for learned linkage
c.ig_conf_pct = 0.50;        % adaptive gate: quantile of recent confidences ...
c.ig_conf_floor = 0.12;      %   ... clipped below at this floor,
c.ig_conf_min_samples = 5;   %   ... used once this many refreshes exist,
c.ig_conf_window = 30;       %   ... over this window
c.ig_min_updates = 10;       % readiness: graph updates,
c.ig_min_refreshes = 2;      %   block refreshes,
c.ig_min_dims = 4;           %   dims inside non-trivial blocks
c.ig_link_mix = 0.50;        % share of blockwise rows that use learned blocks
c.ig_restart_cooldown = 5;   % generations without learned linkage after an escape
c.ig_restart_decay = 0.50;   % graph shrink factor after an escape
c.ig_de_weight = 0.0;        % weight of DE-made moves in graph updates
c.ig_ls_weight = 0.25;       % weight of local-search moves in graph updates

% Final compass polish
c.final_polish = true;
c.fp_start = 0.96;           % budget fraction where it runs (once)
c.fp_budget = 0.02;          % evaluation share
c.fp_step = 0.05;            % initial step (fraction of max span)
c.fp_min_step = 1e-12;       % stop below this step (fraction of max span)

if D < 100
    return
end

%% Tier D >= 100
c.de_entry = false;
c.bse_max_restarts = 2;
c.ls_budget = 0.02;
c.ls_elites = 2;
c.ls_period = 2;
c.ls_cooldown = 3;
c.ig_update_period = 10;
c.ig_max_samples = 24;
c.ig_refresh = 20;

c.budget_policy = true;      % TERRA budget policy
c.sp_nlpsr = true;           % SP-NLPSR: keep NP >= sp_floor ...
c.sp_floor = max(12, ceil(2.5 * sqrt(D) + log2(D + 1)));
c.sp_min_samples = 64;       %   ... until this many learned-linkage generations,
c.sp_release = 0.70;         %   ... or this budget fraction
c.basin_memory = true;       % basin memory for novelty-driven restarts
c.basin_max = 64;            %   capacity
c.basin_dist = 0.05;         %   merge distance (normalised)
c.basin_pool_mult = 4;       %   candidates sampled per restart row

c.a1 = true;                 % A1 late acceptance clip: require a relative gain ...
c.a1_tau = 0.85;             %   after this budget fraction,
c.a1_acc_high = 0.30;        %   while acceptance stays >= this,
c.a1_log_drop = -2.0;        %   and log10(best-f drop) EMA < this
c.a1_streak = 5;             %   for this many generations;
c.a1_eps = 1e-3;             %   relative gain required
c.a1_alpha = 0.30;           %   EMA weight of the log drop
c.a2 = true;                 % A2 frozen-streak broadening ...
c.a2_acc_floor = 0.05;       %   when acceptance < this
c.a2_log_drop = -3.0;        %   and the log-drop EMA < this
c.a2_streak = 10;            %   for this many consecutive generations:
c.a2_window = 20;            %   broaden KR for this many generations,
c.a2_cooldown = 10;          %   then pause this long
c.a2_factor = 1.5;           %   KR multiplier
c.fc4 = true;                % FC4: route rows back to random blocks when learned ones lag
c.fc4_tau = 0.50;            %   after this budget fraction
c.fc4_negative = -0.05;      %   lift EMA <= this: cut the learned share by fc4_strength
c.fc4_severe = -0.20;        %   lift EMA <= this: random blocks only
c.fc4_strength = 0.5;        %   (share of learned rows removed at the negative level)
c.fc4_alpha = 0.20;          %   EMA weight of the lift (learned - random acceptance)
end
