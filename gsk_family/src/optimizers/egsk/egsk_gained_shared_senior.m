function [R1, R2, R3] = egsk_gained_shared_senior(indBest)
%EGSK_GAINED_SHARED_SENIOR Senior-phase donor indices (eGSK-local helper).
%
%   [R1, R2, R3] = egsk_gained_shared_senior(indBest)
%
% Transcribed verbatim from:
%   historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Senior_R1R2R3.m
%
% indBest lists population indices sorted by ascending fitness (NP = its
% length). Blocks by rank:
%   best  : 1 .. round(NP*0.1)
%   middle: round(NP*0.1)+1 .. round(NP*0.9)
%   worst : round(NP*0.9)+1 .. NP
% For each of the NP individuals, R1, R2 and R3 are drawn uniformly from
% the best, middle and worst block. Draw order: all R1, then all R2, then
% all R3.
%
% Kept as an eGSK-local copy instead of the shared
% src/common/Gained_Shared_Senior_R1R2R3.m: it takes no P argument and
% hard-codes the 0.1 / 0.9 boundaries above, as in the reference file.
% Byte-identical to the ATMALS-GSK cec2011 senior helper.

pop_size = length(indBest);

R1 = indBest(1:round(pop_size * 0.1));
R1rand = ceil(length(R1) * rand(pop_size, 1));
R1 = R1(R1rand);

R2 = indBest(round(pop_size * 0.1) + 1:round(pop_size * 0.9));
R2rand = ceil(length(R2) * rand(pop_size, 1));
R2 = R2(R2rand);

R3 = indBest(round(pop_size * 0.9) + 1:end);
R3rand = ceil(length(R3) * rand(pop_size, 1));
R3 = R3(R3rand);

end
