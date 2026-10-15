function [indFDB] = fdb_score_ranking(population, fitness)
%FDB_SCORE_RANKING Population indices sorted by descending FDB score (Case 2).
%
%   indFDB = fdb_score_ranking(population, fitness)
%
% Faithful port of the FDB-AGSK reference FDB_Func2.m (historical source).
% population: NP x D; fitness: NP values (lower is better).
% Same FDB score as fdb_score_best (FDB_Func1), but returns the full
% ranking: a 1 x NP row of indices, highest score first. Kept as its own
% file because the output differs (a ranking, not a single argmax).
%
% Reference quirk, kept: if all fitness values are equal, randi is drawn
% into a local variable, not the output, so indFDB is empty. The Case 2
% caller then fails on indexing, as the reference would.

indFDB = [];

[~, bestIndex] = min(fitness);
best = population(bestIndex, :);
[populationSize, dimension] = size(population);

distances = zeros(1, populationSize);
normFitness = zeros(1, populationSize);
normDistances = zeros(1, populationSize);
divDistances = zeros(1, populationSize);

if min(fitness) == max(fitness)

    index = randi(populationSize); %#ok<NASGU> % one RNG draw; not returned

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

    [~, index] = max(divDistances); %#ok<NASGU> % unused, as in the reference

    % Rank by FDB score, highest first.
    [~, indFDB] = sort(divDistances, 'descend');

end

end
