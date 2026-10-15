function seed = unified_run_seed(base_seed, dim, func, run)
%UNIFIED_RUN_SEED Backward-compatible wrapper for get_cec_seed.
%
% New code should call get_cec_seed directly. This wrapper keeps older tests,
% scripts, and documentation snippets from breaking while using the same
% optimizer-independent uint64 formula.

seed = get_cec_seed(base_seed, dim, func, run);
end
