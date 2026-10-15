function index = fdb_score_best(population, fitness)
%FDB_SCORE_BEST Faithful port of the FDB-AGSK best-score selector.
%
% Source (transcribed verbatim):
%   historical source: FDB-AGSK reference FDB_Func1.m
%
% Fitness-Distance Balance score: Manhattan distance of each individual to
% the current best, normalized fitness 1-(f-min)/(max-min), normalized
% distance (d-min)/(max-min), score = normFitness + normDistance; returns
% the ARGMAX index. Degenerate flat-fitness population: uniform random
% index via randi (consumes one RNG draw), exactly as the reference.

[~, bestIndex] = min(fitness);
best = population(bestIndex, :);
[populationSize, dimension] = size(population);

distances = zeros(1, populationSize);
normFitness = zeros(1, populationSize);
normDistances = zeros(1, populationSize);
divDistances = zeros(1, populationSize);

if min(fitness) == max(fitness)

    index = randi(populationSize);

else

    % Manhattan distance to best + normalization, vectorized. sum(...,2) sums
    % over dimensions in the same order as the original inner j-loop, so the
    % scores are bit-identical to the loop version.
    distances = sum(abs(best - population), 2).';
    f = fitness(:).';
    minFitness = min(f); maxMinFitness = max(f) - minFitness;
    minDistance = min(distances); maxMinDistance = max(distances) - minDistance;
    normFitness = 1 - ((f - minFitness) / maxMinFitness);
    normDistances = (distances - minDistance) / maxMinDistance;
    divDistances = normFitness + normDistances;

    [~, index] = max(divDistances);

end

end
