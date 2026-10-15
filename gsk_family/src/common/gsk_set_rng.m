function actual_seed = gsk_set_rng(options)
%GSK_SET_RNG Seed the global RNG for a GSK-family optimizer.
%
%   actual_seed = gsk_set_rng(options)
%
% options.seed is required ('gsk:setRng' if absent or empty) and is returned
% unchanged as actual_seed. options.rand_generator picks the generator
% (case-insensitive); absent or empty means 'twister', the default for
% direct optimizer calls. run_experiment picks threefry or twister for
% unified CEC runs.
%   'threefry' -> counter-based Threefry when MATLAB supports it, else twister
%   'twister'  -> Mersenne Twister (mt19937ar)  [== rng(seed, 'twister')]
%   'seed'     -> legacy v4 generator (mcg16807) [== rand('seed', s)]
%   'state'    -> legacy v5 generator (swb2712)  [== rand('state', s)]
% Aliases: 'mt', 'mt19937ar'; 'v4', 'mcg16807'; 'v5', 'swb2712'. Any other
% name raises 'gsk:setRng'.
%
% Legacy modes use RandStream.setGlobalStream because rand('seed', s) and
% rand('state', s) redirect only rand(): randperm (ATMALS-GSK) and randi
% (FDB-AGSK) would still draw from the modern global stream and break
% replay. RandStream selects the same algorithms and controls every draw:
% rand, randi and randperm.
%
% Wall-clock seeding is not supported. Source releases that used
% rand('seed', sum(100*clock)) get deterministic scheduled seeds from
% run_experiment, so serial and parfor results stay replayable.

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
            % Older MATLAB releases: fall back to twister so direct calls
            % stay reproducible. run_experiment resolves and records the
            % actual generator before calling here.
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
