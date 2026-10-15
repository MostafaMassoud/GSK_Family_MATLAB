function pop = gsk_initial_population_from_options(options, np, lb, ub)
%GSK_INITIAL_POPULATION_FROM_OPTIONS Use runner-provided X0 or draw normally.
%
% Unified experiments use a strict fair-start protocol:
%   1. run_experiment computes get_cec_seed(base_seed, dim, func, run).
%   2. The runner seeds rng with the resolved unified generator (threefry when
%      supported, otherwise twister) and draws X0 exactly once.
%   3. The same X0 is passed to every optimizer through options.initial_population.
%   4. Each optimizer starts from X0 instead of drawing its own first population.
%
% This helper is the narrow adapter that lets optimizer code keep the reference
% initialization location while allowing the runner to own X0 in unified mode.
% If options.initial_population is absent, reference/native/derived calls keep
% the original one-rand(NP,D) initialization draw through gsk_init_population.
%
% The first np rows are used so a caller can provide a larger fair-start matrix
% and still run optimizers with a smaller population. A too-small X0 is an
% error because silently padding it would introduce optimizer-specific random
% draws and break the fairness guarantee.

dim = numel(lb);
if isfield(options, 'initial_population') && ~isempty(options.initial_population)
    pop = double(options.initial_population);
    assert(ismatrix(pop), 'gsk:initialPopulation', ...
        'options.initial_population must be a 2-D numeric matrix');
    assert(size(pop, 1) >= np && size(pop, 2) == dim, 'gsk:initialPopulation', ...
        'options.initial_population must have at least %d rows and exactly %d columns', np, dim);
    pop = pop(1:np, :);
else
    pop = gsk_init_population(np, lb, ub);
end
end
