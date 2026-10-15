function [R1, R2, R3] = Gained_Shared_Junior_R1R2R3(indBest)
%GAINED_SHARED_JUNIOR_R1R2R3 Junior-phase donor indices for GSK variants.
%
%   [R1, R2, R3] = Gained_Shared_Junior_R1R2R3(indBest)
%
% Faithful port of the reference helper, which exists as identical copies in:
%   historical source: atmalsgsk/atmalsgsk/cec2017/Gained_Shared_Junior_R1R2R3.m
%   historical source: agsk/agsk/AGSK-CODE-FINAL/Gained_Shared_Junior_R1R2R3.m
%   historical source: apgsk/apgsk/APGSK Code/Gained_Shared_Junior_R1R2R3.m
% cross-checked against the inlined O(N) re-engineering of the same logic in
%   historical source: gsk/gsk/GSK_Enhanced.m
%
% Input:
%   indBest : permutation of 1..NP (column or row), individuals sorted by
%             ascending fitness; indBest(1) is the current best individual.
% Output:
%   R1, R2, R3 : 1xNP donor index rows. For individual i with rank r in
%   the sorted list:
%     r == 1  (best)  : R1 = 2nd best,            R2 = 3rd best
%     r == NP (worst) : R1 = rank NP-2,           R2 = rank NP-1
%     otherwise       : R1 = one-better neighbor, R2 = one-worse neighbor
%   R3 is uniform over 1..NP, redrawn until R3(i) differs from i, R1(i)
%   and R2(i).
%
% The deterministic neighbor selection below is the vectorized inverse
% permutation form from GSK_Enhanced.m; it produces exactly the same
% indices as the original find()-loop and consumes no random numbers.
% The random R3 draws keep the original floor(rand(...)*NP)+1 form shared
% by GSK.m, AGSK and APGSK so the consumed random stream matches those
% references (GSK_Enhanced uses randi(), which is the same distribution
% but a different raw stream).

pop_size = numel(indBest);
idx = 1:pop_size;

% rankOf(i) = position (rank) of individual i in the sorted list indBest.
rankOf = zeros(1, pop_size);
rankOf(indBest(:)') = idx;

R1 = zeros(1, pop_size);
R2 = zeros(1, pop_size);

bestMask = (rankOf == 1);
worstMask = (rankOf == pop_size);
middleMask = ~(bestMask | worstMask);

if any(bestMask)
    R1(bestMask) = indBest(2);
    R2(bestMask) = indBest(3);
end
if any(worstMask)
    R1(worstMask) = indBest(pop_size - 2);
    R2(worstMask) = indBest(pop_size - 1);
end
if any(middleMask)
    rMid = rankOf(middleMask);
    R1(middleMask) = indBest(rMid - 1);
    R2(middleMask) = indBest(rMid + 1);
end

% Reference: R3 = floor(rand(1, pop_size) * pop_size) + 1; then regenerate
% any entry that collides with self (R0 = 1:pop_size), R1 or R2.
R3 = floor(rand(1, pop_size) * pop_size) + 1;

for it = 1:99999999
    pos = ((R3 == R2) | (R3 == R1) | (R3 == idx));
    if sum(pos) == 0
        break;
    else
        R3(pos) = floor(rand(1, sum(pos)) * pop_size) + 1;
    end
    if it > 1000
        % Reference guard, kept verbatim ("this has never happened so far").
        error('gsk_common:juniorR3', 'Can not generate R3 in 1000 iterations');
    end
end

end
