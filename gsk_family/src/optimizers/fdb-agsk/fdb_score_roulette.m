function index = fdb_score_roulette(population, fitness)
%FDB_SCORE_ROULETTE Faithful port of the FDB-AGSK roulette-score selector.
%
% Source (transcribed verbatim):
%   historical source: FDB-AGSK reference RFDB_Func1.m
%
% Same Fitness-Distance Balance score as fdb_score_best (FDB_Func1), but
% the returned index is drawn by roulette wheel over the scores instead of
% argmax. The degenerate guard additionally checks for infinite fitness
% sums and non-finite best vectors, exactly as written in the reference.

[~, bestIndex] = min(fitness);
best = population(bestIndex, :);
[populationSize, dimension] = size(population);

distances = zeros(1, populationSize);
normFitness = zeros(1, populationSize);
normDistances = zeros(1, populationSize);
divDistances = zeros(1, populationSize);

if (min(fitness) == max(fitness)) || (sum(fitness) >= Inf) || ~(sum(best) < inf)
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

    r = rand * sum(divDistances);
    c = cumsum(divDistances);
    index = find(r <= c, 1, 'first');

end

end
