function index = fdb_score_best(population, fitness)
%FDB_SCORE_BEST Index of the individual with the highest FDB score.
%
%   index = fdb_score_best(population, fitness)
%
% Faithful port of the FDB-AGSK reference FDB_Func1.m (historical source).
% population: NP x D; fitness: NP values (lower is better).
% Returns one row index into population.
%
% Fitness-Distance Balance (FDB) score = normalized fitness
% 1-(f-min)/(max-min) + normalized Manhattan distance to the current best
% (d-min)/(max-min). index is the argmax of the score. If all fitness
% values are equal, index = randi(NP) (one RNG draw), as in the reference.

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

    % Vectorized distance and normalization. sum(...,2) adds the dimensions
    % in the same order as the original loop, so scores match bit for bit.
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
