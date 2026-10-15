function actual_seed = gsk_set_rng(options)
%GSK_SET_RNG Seed the global RNG for a GSK-family optimizer, with a selectable
% generator family via options.rand_generator (default 'twister' for direct
% optimizer calls; run_experiment chooses threefry-or-twister for unified CEC).
%
%   'threefry' -> counter-based Threefry generator when supported by MATLAB
%   'twister' -> Mersenne Twister   (mt19937ar)  [default; == rng(seed,'twister')]
%   'seed'    -> legacy v4 generator (mcg16807)   [== the classic rand('seed', s)]
%   'state'   -> legacy v5 generator (swb2712)    [== the classic rand('state', s)]
%
% WHY RandStream for deterministic legacy modes: the legacy rand('seed',s) /
% rand('state',s) calls redirect only rand(). randperm (ATMALS-GSK) and randi
% (FDB-AGSK) would keep drawing from the modern global stream and break
% deterministic replay. RandStream.setGlobalStream selects the IDENTICAL
% generator algorithms (mcg16807 = v4, swb2712 = v5, mt19937ar = Mersenne
% Twister) while controlling every draw -- rand, randi AND randperm.
%
% Wall-clock seeding is intentionally not supported. Historical source releases
% that used rand('seed', sum(100*clock)) are represented by deterministic
% scheduled seeds in run_experiment so serial/parfor results remain replayable.
%
% options.seed is required. options.rand_generator is optional (absent or empty
% -> 'twister'), so callers that pass only a seed keep the previous behavior.

if ~isfield(options, 'seed') || isempty(options.seed)
    error('gsk:setRng', 'options.seed is required');
end
seed = options.seed;
actual_seed = seed;

generator = 'twister';
if isfield(options, 'rand_generator') && ~isempty(options.rand_generator)
    generator = char(options.rand_generator);
end

switch lower(generator)
    case {'threefry'}
        try
            rng(seed, 'threefry');
        catch
            % Direct low-level calls on older MATLAB releases still remain
            % reproducible by falling back to twister. The high-level runner
            % resolves and records the actual generator before calling here.
            rng(seed, 'twister');
        end
    case {'twister', 'mt', 'mt19937ar'}
        rng(seed, 'twister');
    case {'seed', 'v4', 'mcg16807'}
        RandStream.setGlobalStream(RandStream('mcg16807', 'Seed', seed));
    case {'state', 'v5', 'swb2712'}
        RandStream.setGlobalStream(RandStream('swb2712', 'Seed', seed));
    otherwise
        error('gsk:setRng', ...
            'unknown rand_generator ''%s'' (use ''threefry'', ''twister'', ''seed'', or ''state'')', generator);
end
end
