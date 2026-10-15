function i = atmals_roulette_select(PR)
%ATMALS_ROULETTE_SELECT Faithful port of the ATMALS-GSK roulette wheel.
%
% Source (transcribed verbatim):
%   historical source: atmalsgsk/atmalsgsk/cec2017/RouletteWheelSelection.m
%   (byte-identical copy: .../cec2011/RouletteWheelSelection.m)
%
% The caller passes Prob.^RP (the probability table raised to the RP
% exponent), exactly as in ATMALS_GSK.m. The sort([c r]) / find(c==r)
% construction locates the roulette slot of the single rand draw.

r = rand;

PR = PR / sum(PR);

c = cumsum(PR);

c = sort([c r]);

i = find(c == r, 1, 'first');

end
