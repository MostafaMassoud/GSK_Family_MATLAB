function pop = gsk_initial_population_from_options(options, np, lb, ub)
%GSK_INITIAL_POPULATION_FROM_OPTIONS Use runner-provided X0 or draw normally.
%
%   pop = gsk_initial_population_from_options(options, np, lb, ub)
%
% Returns the NP x D starting population (lb and ub are 1 x D rows).
% If options.initial_population (X0) is present and non-empty, returns its
% first np rows as double. Otherwise (for example in reference, native and
% derived calls) it draws one rand(NP, D) through gsk_init_population, as
% the reference code does.
%
% Unified experiments use a strict fair-start protocol:
%   1. run_experiment computes get_cec_seed(base_seed, dim, func, run).
%   2. The runner seeds rng with the resolved unified generator (threefry
%      when supported, otherwise twister) and draws X0 exactly once.
%   3. Every optimizer gets the same X0 in options.initial_population.
%   4. Each optimizer starts from X0 instead of drawing its own population.
% This adapter keeps each optimizer's initialization at its reference
% location while the runner owns X0 in unified mode.
%
% X0 may have more than np rows, so one fair-start matrix can serve smaller
% populations. An X0 that is not 2-D, has too few rows or has a column count
% other than D raises 'gsk:initialPopulation'. Padding a short X0 would add
% optimizer-specific random draws and break fairness.

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
