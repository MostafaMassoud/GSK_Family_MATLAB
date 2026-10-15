function i = atmals_roulette_select(PR)
%ATMALS_ROULETTE_SELECT Faithful port of the ATMALS-GSK roulette wheel.
%
%   i = atmals_roulette_select(PR) normalizes the weights PR and returns the
%   index of the slot hit by a single rand draw. The caller passes Prob.^RP
%   (probability table raised to the power RP), as in ATMALS_GSK.m.
%
%   historical source: atmalsgsk/atmalsgsk/cec2017/RouletteWheelSelection.m
%   (byte-identical copy in .../cec2011/). Transcribed verbatim.

r = rand;

PR = PR / sum(PR);

c = cumsum(PR);

% Insert r into the sorted cumulative sums; its position is the slot.
c = sort([c r]);

i = find(c == r, 1, 'first');

end
