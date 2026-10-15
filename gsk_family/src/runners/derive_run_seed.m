function seed = derive_run_seed(base_seed, optimizer, suite, dim, func, run)
%DERIVE_RUN_SEED Deterministic per-run seed for native/derived diagnostics.
%
% Usage: seed = derive_run_seed(base_seed, optimizer, suite, dim, func, run)
% run_experiment uses this hashed seed for seed_policy = 'native' or
% 'derived'. It mixes in optimizer and suite. The fair cross-family seed
% comes from get_cec_seed.m, which ignores them so all algorithms share one
% seed per (dimension, function, run) cell. The C++ tools document their own
% policy in gskcec/core/random.hpp.
%
% Properties:
%   * Large, mostly prime strides: changing any one of
%     (optimizer, suite, dim, func, run) by 1 moves the seed far.
%   * mod(.,2^31-2)+1 keeps the seed in [1, 2^31-2], valid for every RNG
%     family gsk_set_rng supports (twister and the legacy seed/state v4/v5
%     generators, which reject 0 and anything above 2^31-2).
%   * Every term stays far below 2^53 (largest is 10000019*dim, ~1e10 at
%     dim=1000), so the double arithmetic is exact on every machine.
%   * optimizer and suite are hashed by ASCII sum, which keeps the small
%     fixed name set distinct.
%
% Wall-clock seeding is forbidden project-wide. Every run seed is recorded
% in seed_schedule.csv, per_run.csv and environment.json.
%
% The gsk_run/config default is seed_policy = 'reference'. Use this helper
% only for deliberate diagnostic studies; docs/reference/seed_policy.md
% describes the reference and unified schedules.

opt_code = sum(double(optimizer));
suite_code = sum(double(suite));
seed = mod(base_seed + 1000003 * opt_code + 1000033 * suite_code + ...
           10000019 * dim + 10000169 * func + 10000379 * run, ...
           2^31 - 2) + 1;
end
