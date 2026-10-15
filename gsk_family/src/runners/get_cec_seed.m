function seed = get_cec_seed(base_seed, dim, func, run)
%GET_CEC_SEED Unified deterministic CEC experiment seed.
%
% Usage: seed = get_cec_seed(base_seed, dim, func, run)
% Single source of truth for the fair cross-family CEC seed schedule. No
% algorithm-specific value (optimizer name or index, population size, maxFEs,
% suite name, implementation language) may affect it, so GSK, eGSK, AGSK,
% APGSK, FDB-AGSK, ATMALS-GSK and any external comparator get the same seed
% on the same (dimension, function, run) cell.
%
% Formula:
%   MAX_SAFE_SEED = 2147483646 = 2^31 - 2
%   seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run,
%              MAX_SAFE_SEED) + 1
%
% Terms:
%   base_seed     : campaign identifier; a new value gives a new, reproducible
%                   campaign under the same protocol.
%   dim           : separates D10/D30/D50/D100 and native-dimension problems.
%   func          : separates functions within one dimension.
%   run           : separates independent repeated trials.
%   strides       : prime-like, to reduce accidental collisions and avoid
%                   ambiguous products such as dim*func.
%   MAX_SAFE_SEED : top of the valid seed range for MATLAB/RandStream legacy
%                   streams; also safe for rng(...,'threefry'/'twister').
%
% The arithmetic uses uint64 on purpose: doubles are exact for today's small
% CEC grids, but uint64 also covers larger future grids and rules out
% rounding before the modulo. The result is returned as a double because
% rng/RandStream take numeric scalar seeds.

MAX_SAFE_SEED = uint64(2147483646);  % 2^31 - 2

seed = mod(uint64(base_seed) ...
    + uint64(1000003) * uint64(dim) ...
    + uint64(1000033) * uint64(func) ...
    + uint64(1000037) * uint64(run), ...
    MAX_SAFE_SEED) + 1;

seed = double(seed);
end
