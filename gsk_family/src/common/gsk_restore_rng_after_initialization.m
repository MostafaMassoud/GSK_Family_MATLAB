function gsk_restore_rng_after_initialization(options)
%GSK_RESTORE_RNG_AFTER_INITIALIZATION Restore runner-captured post-X0 RNG state.
%
% Passing the same X0 is only half of strict fairness. If optimizer A consumes
% zero random numbers during initialization because X0 was supplied, while
% optimizer B consumes rand(NP,D) internally, their later random decisions would
% start from different stream positions even with the same seed. Unified mode
% avoids that by having run_experiment draw X0 once, then capture rng immediately
% after that draw. Each optimizer restores this captured state right after it
% accepts X0, so every later rand/randi/randperm call starts from the same
% post-initialization point.
%
% The restore is intentionally guarded by initial_population. If a low-level
% diagnostic caller accidentally passes only rng_state_after_initialization, the
% optimizer keeps normal reference behavior instead of jumping streams without
% the matching X0.

if isfield(options, 'initial_population') && ~isempty(options.initial_population) && ...
        isfield(options, 'rng_state_after_initialization') && ...
        ~isempty(options.rng_state_after_initialization)
    rng(options.rng_state_after_initialization);
end
end
