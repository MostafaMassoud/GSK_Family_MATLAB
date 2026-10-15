function [R1, R2, R3] = Gained_Shared_Senior_R1R2R3(indBest, P)
%GAINED_SHARED_SENIOR_R1R2R3 Senior-phase donor indices for GSK variants.
%
%   [R1, R2, R3] = Gained_Shared_Senior_R1R2R3(indBest, P)
%
% indBest holds the NP individuals sorted by ascending fitness; P is the
% partition fraction. The ranks split into three blocks:
%   best block  : ranks 1 .. round(NP*P)
%   middle block: ranks round(NP*P)+1 .. round(NP*(1-P))
%   worst block : ranks round(NP*(1-P))+1 .. NP
% For each of the NP individuals, independently, R1 is drawn uniformly from
% the best block, R2 from the middle block and R3 from the worst block. Draw
% order matches the reference: all R1 draws, then all R2, then all R3.
%
% Port of the reference helper; the references hard-code P:
%   gsk/gsk/GSK_Enhanced.m (inlined, P = 0.1: round(NP*0.1) / round(NP*0.9))
%   agsk/agsk/AGSK-CODE-FINAL/Gained_Shared_Senior_R1R2R3.m (P = 0.05:
%     round(NP*0.05) / round(NP*0.95))
%   apgsk/apgsk/APGSK Code/Gained_Shared_Senior_R1R2R3.m (same as AGSK)
%
% Rounding: in IEEE double, (1 - 0.1) == 0.9 and (1 - 0.05) == 0.95 exactly,
% so round(NP*(1-P)) gives the reference block boundary bit for bit for
% both P values at every NP. This matters because AGSK and APGSK shrink NP
% during a run. The ATMALS-GSK copy ends the middle block at
% pop_size-PartSize instead; that differs only when NP*P is an exact
% half-integer, and that variant behavior is not used here.

pop_size = length(indBest);

R1 = indBest(1:round(pop_size * P));
R1rand = ceil(length(R1) * rand(pop_size, 1));
R1 = R1(R1rand);

R2 = indBest(round(pop_size * P) + 1:round(pop_size * (1 - P)));
R2rand = ceil(length(R2) * rand(pop_size, 1));
R2 = R2(R2rand);

R3 = indBest(round(pop_size * (1 - P)) + 1:end);
R3rand = ceil(length(R3) * rand(pop_size, 1));
R3 = R3(R3rand);

end
