function [R1, R2, R3] = egsk_gained_shared_senior(indBest)
%EGSK_GAINED_SHARED_SENIOR Faithful port of the eGSK-local senior helper.
%
% Source (transcribed verbatim):
%   historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Senior_R1R2R3.m
%
% Kept as an eGSK-local copy because it DIFFERS from the shared
% src/common/Gained_Shared_Senior_R1R2R3.m: it takes no P argument and uses
% fixed round(pop_size*0.1) / round(pop_size*0.9) partition boundaries,
% which deviate from Senior(indBest, 0.1) whenever round(pop_size*0.9) ~=
% pop_size - round(pop_size*0.1). (It is byte-identical to the ATMALS-GSK
% cec2011 senior helper.)

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
