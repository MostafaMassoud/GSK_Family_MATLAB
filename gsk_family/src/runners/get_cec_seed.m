function seed = get_cec_seed(base_seed, dim, func, run)
%GET_CEC_SEED Unified deterministic CEC experiment seed.
%
% This is the single source of truth for the fair cross-family CEC seed
% schedule. The formula deliberately excludes every algorithm-specific value:
% optimizer name, optimizer index, population size, maxFEs, suite name, and
% implementation language must not affect this seed. Therefore GSK, eGSK,
% AGSK, APGSK, FDB-AGSK, ATMALS-GSK, and any external comparator receive the
% same seed whenever they are run on the same (dimension, function, run) cell.
%
% Formula:
%   MAX_SAFE_SEED = 2147483646 = 2^31 - 2
%   seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run,
%              MAX_SAFE_SEED) + 1
%
% Why these pieces:
%   base_seed   : experiment-level identifier; changing it creates a new,
%                 reproducible campaign without changing the protocol.
%   dim         : separates D10/D30/D50/D100 and native-dimension problems.
%   func        : separates benchmark functions inside the same dimension.
%   run         : separates independent repeated trials.
%   prime-like strides : reduce accidental coordinate collisions and avoid
%                 ambiguous products such as dim*func.
%   MAX_SAFE_SEED : upper valid seed range used by MATLAB/RandStream legacy
%                 streams and safe for rng(...,'threefry'/'twister').
%
% uint64 arithmetic is intentional. MATLAB doubles can exactly represent the
% small CEC grids used here, but using uint64 makes the contract immune to
% future larger grids and prevents hidden rounding before the modulo. The final
% result is converted to double because MATLAB rng/RandStream APIs accept
% numeric scalar seeds.

MAX_SAFE_SEED = uint64(2147483646);  % 2^31 - 2

seed = mod(uint64(base_seed) ...
    + uint64(1000003) * uint64(dim) ...
    + uint64(1000033) * uint64(func) ...
    + uint64(1000037) * uint64(run), ...
    MAX_SAFE_SEED) + 1;

seed = double(seed);
end
