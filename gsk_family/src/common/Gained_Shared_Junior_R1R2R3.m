function [R1, R2, R3] = Gained_Shared_Junior_R1R2R3(indBest)
%GAINED_SHARED_JUNIOR_R1R2R3 Junior-phase donor indices for GSK variants.
%
%   [R1, R2, R3] = Gained_Shared_Junior_R1R2R3(indBest)
%
% Input:
%   indBest : permutation of 1..NP (row or column), individuals sorted by
%             ascending fitness; indBest(1) is the current best.
%             Needs NP >= 4: with NP = 3, i, R1 and R2 cover every index, so
%             no valid R3 exists.
% Output:
%   R1, R2, R3 : 1 x NP donor index rows. For individual i with rank r:
%     r == 1  (best)  : R1 = 2nd best,        R2 = 3rd best
%     r == NP (worst) : R1 = rank NP-2,       R2 = rank NP-1
%     otherwise       : R1 = one rank better, R2 = one rank worse
%   R3 is uniform over 1..NP, redrawn until R3(i) differs from i, R1(i)
%   and R2(i). Raises 'gsk_common:juniorR3' if collisions remain after
%   1000 redraw rounds.
%
% R1 and R2 use the vectorized inverse-permutation form of GSK_Enhanced.m:
% same indices as the reference find() loop, no random numbers drawn.
% R3 keeps the reference floor(rand(...)*NP)+1 form (GSK.m, AGSK, APGSK) so
% the random stream matches those references. GSK_Enhanced uses randi(),
% which has the same distribution but a different raw stream.
%
% Source: identical copies of Gained_Shared_Junior_R1R2R3.m in
%   atmalsgsk/atmalsgsk/cec2017/, agsk/agsk/AGSK-CODE-FINAL/ and
%   apgsk/apgsk/APGSK Code/; cross-checked against the inlined O(N) form in
%   gsk/gsk/GSK_Enhanced.m.

pop_size = numel(indBest);
idx = 1:pop_size;

% rankOf(i) is the rank of individual i in indBest.
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

% Draw R3 as the reference does, then redraw entries equal to i, R1 or R2.
R3 = floor(rand(1, pop_size) * pop_size) + 1;

for it = 1:99999999
    pos = ((R3 == R2) | (R3 == R1) | (R3 == idx));
    if sum(pos) == 0
        break;
    else
        R3(pos) = floor(rand(1, sum(pos)) * pop_size) + 1;
    end
    if it > 1000
        % Reference guard, kept verbatim; the reference notes it never fired.
        error('gsk_common:juniorR3', 'Can not generate R3 in 1000 iterations');
    end
end

end
