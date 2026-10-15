function gsk_restore_rng_after_initialization(options)
%GSK_RESTORE_RNG_AFTER_INITIALIZATION Restore runner-captured post-X0 RNG state.
%
%   gsk_restore_rng_after_initialization(options)
%
% Sets rng to options.rng_state_after_initialization when both that field
% and options.initial_population (X0) are present and non-empty; otherwise
% does nothing.
%
% Why: the same X0 alone is not enough for a fair start. An optimizer that
% accepts X0 draws no random numbers at initialization, while one that draws
% rand(NP, D) itself moves the stream, so later random choices would start
% from different stream positions even with the same seed. In unified mode
% run_experiment draws X0 once and captures rng right after that draw. Each
% optimizer restores this state right after it accepts X0, so every later
% rand/randi/randperm call starts from the same point.
%
% The X0 guard is deliberate: a diagnostic caller that passes only the RNG
% state keeps the normal reference behavior instead of jumping streams
% without the matching X0.

if isfield(options, 'initial_population') && ~isempty(options.initial_population) && ...
        isfield(options, 'rng_state_after_initialization') && ...
        ~isempty(options.rng_state_after_initialization)
    rng(options.rng_state_after_initialization);
end
end
