function test_common_helpers()
%TEST_COMMON_HELPERS Unit checks for the shared GSK helpers (src/common).
%
% Covers: midpoint bound repair (below/above/inside), fair-start X0 and
% post-X0 RNG restore (including its guard), junior donor index
% constraints, senior donor block partition, reduction survivor selection
% (ties, and equivalence with the reference sequential removal loop).
% Raises error() on any failure, returns nothing on success.

% ---------- gsk_bound_repair: midpoint rule ----------
lb = [-5 -5];
ub = [5 5];
pop = [0 0; 4 -4];
vi = [-7 3; 12 -20];   % below lower / inside / above upper / below lower
out = gsk_bound_repair(vi, pop, lb, ub);
expected = [(0 + -5) / 2, 3; (4 + 5) / 2, (-4 + -5) / 2];
local_assert(isequal(out, expected), 'bound repair: midpoint values wrong');

% exactly-on-bound values must be untouched (reference uses strict </>)
vi2 = [-5 5; 5 -5];
out2 = gsk_bound_repair(vi2, pop, lb, ub);
local_assert(isequal(out2, vi2), 'bound repair: on-bound values must not change');

% ---------- gsk_init_population: bounds and shape ----------
rng(11, 'twister');
lb4 = -3 * ones(1, 4);
ub4 = 7 * ones(1, 4);
p0 = gsk_init_population(50, lb4, ub4);
local_assert(isequal(size(p0), [50 4]), 'init population: wrong size');
local_assert(all(p0(:) >= -3) && all(p0(:) <= 7), 'init population: out of bounds');
local_assert(max(p0(:)) > min(p0(:)), 'init population: degenerate values');

% ---------- fair-start initial population helper ----------
x0 = reshape(1:20, 5, 4);
opts = struct('initial_population', x0);
p1 = gsk_initial_population_from_options(opts, 3, lb4, ub4);
local_assert(isequal(p1, x0(1:3, :)), 'init population option: did not use X0 prefix');
% post-X0 RNG restore: the stream is advanced (and switched to another
% generator) between capture and restore, so a no-op restore cannot pass
rng(101, 'twister');
before = rng;
opts.rng_state_after_initialization = before;   % opts already carries initial_population = x0
expected_next = rand(1, 5);                     % reference draw from the captured point
rng(303, 'combRecursive');                      % move away: other seed AND other generator
rand(7, 3);
gsk_restore_rng_after_initialization(opts);
after = rng;
local_assert(strcmp(after.Type, before.Type) && isequal(before.State, after.State), ...
    'post-initialization RNG restore failed (generator or state not restored)');
local_assert(isequal(rand(1, 5), expected_next), ...
    'post-initialization RNG restore: next draw mismatch');

% guard: without initial_population (absent or empty) the helper must leave
% the stream untouched instead of jumping to the captured state
guard_opts = {struct('rng_state_after_initialization', before), ...
    struct('initial_population', [], 'rng_state_after_initialization', before)};
for gi = 1:numel(guard_opts)
    rng(202, 'twister');
    rand(5, 2);
    mid = rng;
    gsk_restore_rng_after_initialization(guard_opts{gi});
    after2 = rng;
    local_assert(isequal(mid.State, after2.State) && ~isequal(before.State, after2.State), ...
        sprintf('RNG restore must be skipped when initial_population is absent/empty (case %d)', gi));
end
% guard: X0 without a captured state keeps the current stream as well
rng(202, 'twister');
mid = rng;
gsk_restore_rng_after_initialization(struct('initial_population', x0));
after3 = rng;
local_assert(isequal(mid.State, after3.State), ...
    'RNG restore must be skipped when rng_state_after_initialization is absent');

% ---------- Gained_Shared_Junior_R1R2R3: donor constraints ----------
% Case 1: sorted synthetic fitness (individual i has rank i).
rng(21, 'twister');
np = 30;
fitness_sorted = (1:np)';                 % ascending: indBest = (1:np)'
[~, indBest] = sort(fitness_sorted, 'ascend');
local_assert(isequal(indBest, (1:np)'), 'junior: sorted fixture broken');
[R1, R2, R3] = Gained_Shared_Junior_R1R2R3(indBest);
% best gets the next-two-best, worst gets two-better, middles adjacent
local_assert(R1(1) == 2 && R2(1) == 3, 'junior: best must use 2nd/3rd best');
local_assert(R1(np) == np - 2 && R2(np) == np - 1, 'junior: worst must use two better');
for i = 2:np - 1
    local_assert(R1(i) == i - 1 && R2(i) == i + 1, ...
        sprintf('junior: middle %d must use adjacent ranks', i));
end
local_check_r3(R1, R2, R3, np);

% Case 2: permuted fitness; verify via rank mapping.
rng(22, 'twister');
perm = randperm(np);
fitness_perm = zeros(np, 1);
fitness_perm(perm) = (1:np)';             % individual perm(r) has rank r
[~, indBest] = sort(fitness_perm, 'ascend');
[R1, R2, R3] = Gained_Shared_Junior_R1R2R3(indBest);
rankOf = zeros(1, np);
rankOf(indBest) = 1:np;
for i = 1:np
    r = rankOf(i);
    if r == 1
        local_assert(R1(i) == indBest(2) && R2(i) == indBest(3), ...
            'junior(perm): best neighbors wrong');
    elseif r == np
        local_assert(R1(i) == indBest(np - 2) && R2(i) == indBest(np - 1), ...
            'junior(perm): worst neighbors wrong');
    else
        local_assert(R1(i) == indBest(r - 1) && R2(i) == indBest(r + 1), ...
            'junior(perm): middle neighbors wrong');
    end
end
local_check_r3(R1, R2, R3, np);

% ---------- Gained_Shared_Senior_R1R2R3: block partition ----------
rng(31, 'twister');
np = 100;
perm = randperm(np);
fitness_perm = zeros(np, 1);
fitness_perm(perm) = (1:np)';
[~, indBest] = sort(fitness_perm, 'ascend');

% P = 0.1 (baseline GSK): blocks 1..10 / 11..90 / 91..100 of the ranking
[S1, S2, S3] = Gained_Shared_Senior_R1R2R3(indBest, 0.1);
local_check_senior(S1, S2, S3, indBest, 10, 90, np, 'P=0.1');

% P = 0.05 (AGSK/APGSK): blocks 1..5 / 6..95 / 96..100 of the ranking
[S1, S2, S3] = Gained_Shared_Senior_R1R2R3(indBest, 0.05);
local_check_senior(S1, S2, S3, indBest, 5, 95, np, 'P=0.05');

% ---------- gsk_reduction_survivors: worst removed ----------
fit = [3 1 2 5 4]';
surv = gsk_reduction_survivors(fit, 2);
local_assert(isequal(surv, [1; 2; 3]), 'reduction: must keep the 3 best in row order');

% tie on the worst value: reference sequential removal drops the
% highest-index tied row first (num_remove = 1 discriminates: a
% lowest-index-first rule would keep [1;3;4])
fit_tie = [1 5 5 2]';
surv_tie1 = gsk_reduction_survivors(fit_tie, 1);
local_assert(isequal(surv_tie1, [1; 2; 4]), ...
    'reduction: tie handling mismatch (must drop the highest-index tied worst row first)');
% removing both tied rows keeps the two best in row order
surv_tie = gsk_reduction_survivors(fit_tie, 2);
local_assert(isequal(surv_tie, [1; 4]), 'reduction: tie handling mismatch (num_remove=2)');

% equivalence with the reference one-at-a-time worst-removal loop on
% heavily tied fixtures (integer fitness with many duplicates)
rng(41, 'twister');
for trial = 1:50
    n_fix = randi([2 15]);
    fit_fix = randi(4, n_fix, 1);
    k_fix = randi([0 n_fix - 1]);
    local_assert(isequal(gsk_reduction_survivors(fit_fix, k_fix), ...
        local_reference_reduction(fit_fix, k_fix)), ...
        sprintf('reduction: differs from the reference loop (trial %d, fitness %s, remove %d)', ...
        trial, mat2str(fit_fix'), k_fix));
end

% zero removals keeps everything
surv0 = gsk_reduction_survivors(fit, 0);
local_assert(isequal(surv0, (1:5)'), 'reduction: zero removals must keep all rows');

end


function local_check_r3(R1, R2, R3, np)
%LOCAL_CHECK_R3 R3 must be in range and collision-free vs self, R1, R2.
local_assert(all(R3 >= 1 & R3 <= np), 'junior: R3 out of range');
local_assert(all(R3 == floor(R3)), 'junior: R3 not integer');
self_idx = 1:np;
local_assert(all(R3 ~= self_idx & R3 ~= R1 & R3 ~= R2), ...
    'junior: R3 collides with self, R1 or R2');
end


function survivors = local_reference_reduction(fitness, num_remove)
%LOCAL_REFERENCE_REDUCTION Verbatim reference resize loop (Adaptive_GSK_ALI.m),
% tracking original row ids so the survivors can be compared by index.
rows = (1:numel(fitness))';
for r = 1:num_remove
    [~, indBest] = sort(fitness, 'ascend');
    worst_ind = indBest(end);
    fitness(worst_ind, :) = [];
    rows(worst_ind, :) = [];
end
survivors = rows;
end


function local_check_senior(S1, S2, S3, indBest, top_end, mid_end, np, label)
%LOCAL_CHECK_SENIOR Senior donors must come from their rank blocks.
best_block = indBest(1:top_end);
mid_block = indBest(top_end + 1:mid_end);
worst_block = indBest(mid_end + 1:np);
local_assert(numel(S1) == np && numel(S2) == np && numel(S3) == np, ...
    sprintf('senior %s: wrong donor counts', label));
local_assert(all(ismember(S1, best_block)), ...
    sprintf('senior %s: R1 not from best block', label));
local_assert(all(ismember(S2, mid_block)), ...
    sprintf('senior %s: R2 not from middle block', label));
local_assert(all(ismember(S3, worst_block)), ...
    sprintf('senior %s: R3 not from worst block', label));
end


function local_assert(cond, message)
%LOCAL_ASSERT error() on failed condition.
if ~cond
    error('test_common_helpers:failed', '%s', message);
end
end
