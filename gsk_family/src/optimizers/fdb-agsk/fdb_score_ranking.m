function [indFDB] = fdb_score_ranking(population, fitness)
%FDB_SCORE_RANKING Faithful port of the FDB-AGSK ranking selector (Case 2).
%
% Source (transcribed verbatim):
%   historical source: FDB-AGSK reference FDB_Func2.m
%
% Same Fitness-Distance Balance score as fdb_score_best (FDB_Func1), but
% returns the FULL index ranking sorted by DESCENDING score (indFDB).
% Ported separately because it differs materially from FDB_Func1 (vector
% ranking output vs scalar argmax).
%
% Preserved reference quirk: in the degenerate flat-fitness branch the
% function draws randi into a local variable that is NOT the output, so
% indFDB is returned EMPTY (the Case2 caller would then error on indexing,
% exactly as the reference would).

indFDB = [];

[~, bestIndex] = min(fitness);
best = population(bestIndex, :);
[populationSize, dimension] = size(population);

distances = zeros(1, populationSize);
normFitness = zeros(1, populationSize);
normDistances = zeros(1, populationSize);
divDistances = zeros(1, populationSize);

if min(fitness) == max(fitness)

    index = randi(populationSize); %#ok<NASGU> % consumed but not returned (as written)

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

    [~, index] = max(divDistances); %#ok<NASGU> % computed but unused for the ranking output (as written)

    % Sort FDB scores
    [~, indFDB] = sort(divDistances, 'descend');

end

end
