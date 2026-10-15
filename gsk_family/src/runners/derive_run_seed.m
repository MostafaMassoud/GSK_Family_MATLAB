function seed = derive_run_seed(base_seed, optimizer, suite, dim, func, run)
%DERIVE_RUN_SEED Deterministic per-run seed for native/derived diagnostics.
%
% This hashed diagnostic policy includes optimizer and suite in the seed. It is
% used when run_experiment receives seed_policy = 'native' or 'derived'. The
% fair cross-family policy is implemented separately in get_cec_seed.m and
% intentionally ignores optimizer/suite so all algorithms share the same
% (dimension, function, run) seed.
%
% Documented separately from the C++ tooling policy in
% gskcec/core/random.hpp. Properties:
%   * Large, mostly-prime strides decorrelate every coordinate, so changing
%     any one of (optimizer, suite, dim, func, run) by 1 moves the seed far.
%   * mod(.,2^31-2)+1 keeps the seed in [1, 2^31-2], valid for every RNG
%     family gsk_set_rng supports (twister and the legacy seed/state v4/v5
%     generators, which reject 0 and anything above 2^31-2).
%   * All terms stay far below 2^53 (largest is 10000019*dim, ~1e10 at
%     dim=1000), so the double arithmetic is exact and machine-independent.
%   * optimizer/suite are hashed by ASCII sum, so the small fixed name set
%     maps to distinct contributions.
%
% Wall-clock seeding is forbidden project-wide; every run seed is recorded
% in the per-run results (seed_schedule.csv, per_run.csv, environment.json).
%
% The high-level gsk_run/config default is seed_policy = 'reference'. Use this
% helper only for deliberate non-reference diagnostic studies; see
% docs/reference/seed_policy.md for the reference and unified schedules.

opt_code = sum(double(optimizer));
suite_code = sum(double(suite));
seed = mod(base_seed + 1000003 * opt_code + 1000033 * suite_code + ...
           10000019 * dim + 10000169 * func + 10000379 * run, ...
           2^31 - 2) + 1;
end
