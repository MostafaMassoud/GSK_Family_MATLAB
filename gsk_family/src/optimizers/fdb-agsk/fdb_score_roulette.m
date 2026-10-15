function index = fdb_score_roulette(population, fitness)
%FDB_SCORE_ROULETTE Index drawn by roulette wheel over the FDB scores.
%
%   index = fdb_score_roulette(population, fitness)
%
% Faithful port of the FDB-AGSK reference RFDB_Func1.m (historical source).
% population: NP x D; fitness: NP values (lower is better).
% Same FDB score as fdb_score_best (FDB_Func1), but index is drawn with
% probability proportional to the score (one rand draw), not the argmax.
% index = randi(NP) instead when all fitness values are equal, when
% sum(fitness) is +Inf, or when sum(best) is +Inf or NaN, as in the
% reference.

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

    % Vectorized distance and normalization. sum(...,2) adds the dimensions
    % in the same order as the original loop, so scores match bit for bit.
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
