function rng_generator = choose_cec_rng_generator()
%CHOOSE_CEC_RNG_GENERATOR Pick the unified-mode CEC RNG family.
%
% Usage: rng_generator = choose_cec_rng_generator()
% Returns 'threefry' when this MATLAB release supports it, else 'twister'.
%
% Threefry is counter-based and gives reproducible independent streams, so it
% suits serial and parfor benchmark runs. Older releases lack it, hence the
% widely available 'twister' fallback. The probe restores the caller's global
% RNG state, so it has no side effect.
%
% Never switch to shuffle seeding, worker or task IDs, the clock or any other
% time or scheduling source: unified seeds depend only on
% (base_seed, dim, func, run).

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
