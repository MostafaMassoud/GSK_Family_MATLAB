function seed = unified_run_seed(base_seed, dim, func, run)
%UNIFIED_RUN_SEED Backward-compatible wrapper for get_cec_seed.
%
% Usage: seed = unified_run_seed(base_seed, dim, func, run)
% Same optimizer-independent uint64 formula as get_cec_seed. Kept so older
% tests, scripts and documentation snippets still work; new code should call
% get_cec_seed directly.

seed = get_cec_seed(base_seed, dim, func, run);
end
