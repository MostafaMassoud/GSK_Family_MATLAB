function [R1, R2, R3] = Gained_Shared_Senior_R1R2R3(indBest, P)
%GAINED_SHARED_SENIOR_R1R2R3 Senior-phase donor indices for GSK variants.
%
%   [R1, R2, R3] = Gained_Shared_Senior_R1R2R3(indBest, P)
%
% Faithful port of the reference helper. The reference copies hard-code
% the partition fraction; this shared port takes it as parameter P:
%   historical source: gsk/gsk/GSK_Enhanced.m
%     (inlined, P = 0.1: round(NP*0.1) / round(NP*0.9))
%   historical source: agsk/agsk/AGSK-CODE-FINAL/Gained_Shared_Senior_R1R2R3.m
%     (P = 0.05: round(NP*0.05) / round(NP*0.95))
%   historical source: apgsk/apgsk/APGSK Code/Gained_Shared_Senior_R1R2R3.m
%     (P = 0.05, identical to the AGSK copy)
%
% Population partition by rank (indBest sorted ascending by fitness):
%   best block  : ranks 1 .. round(NP*P)
%   middle block: ranks round(NP*P)+1 .. round(NP*(1-P))
%   worst block : ranks round(NP*(1-P))+1 .. NP
% R1 is drawn uniformly from the best block, R2 from the middle block and
% R3 from the worst block, independently for each of the NP individuals,
% with the reference draw order (R1 draws, then R2 draws, then R3 draws).
%
% Note on rounding: the reference files write round(NP*0.9) / round(NP*0.95)
% literally. In IEEE double arithmetic (1 - 0.1) == 0.9 and
% (1 - 0.05) == 0.95 exactly, so round(NP*(1-P)) reproduces the reference
% boundary bit-for-bit for both P = 0.1 and P = 0.05 at every NP (this
% matters because AGSK/APGSK shrink NP during a run).
% (The ATMALS-GSK copy of this helper uses pop_size-PartSize for the middle
% block end, which differs from round(NP*(1-P)) only when NP*P is an exact
% half-integer; that variant-local behavior is not used here.)

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
