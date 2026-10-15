function rng_generator = choose_cec_rng_generator()
%CHOOSE_CEC_RNG_GENERATOR Pick the unified-mode CEC RNG family.
%
% Unified CEC experiments prefer MATLAB's counter-based 'threefry' generator
% because it is designed for reproducible independent streams and is a good fit
% for serial/parfor-safe benchmark tasks. Older MATLAB releases may not support
% it, so the project falls back to the widely available 'twister' generator.
%
% The helper probes support without leaving a side effect on the caller's
% current global RNG state. Do not replace this with shuffle-based seeding,
% worker identifiers, task IDs, clock time, or any other time/scheduling source;
% unified seeds must depend only on (base_seed, dim, func, run).

preferred = 'threefry';
fallback = 'twister';

old_state = rng;
try
    rng(1, preferred);
    rng_generator = preferred;
catch
    rng_generator = fallback;
end
rng(old_state);
end
