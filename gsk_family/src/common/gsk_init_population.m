function pop = gsk_init_population(np, lb, ub)
%GSK_INIT_POPULATION Uniform random initialization within bounds.
%
%   pop = gsk_init_population(np, lb, ub)
%
% np : population size, lb/ub : 1xD bound rows. Returns an np x D matrix.
%
% Transcribed from the initialization shared verbatim by all references:
%   historical source: gsk/gsk/GSK_Enhanced.m
%   historical source: atmalsgsk/atmalsgsk/cec2017/GSK.m
%   historical source: agsk/agsk/AGSK-CODE-FINAL/Adaptive_GSK_ALI.m
%   historical source: apgsk/apgsk/APGSK Code/Adaptive_GSK_ALI.m
%     popold = repmat(lu(1,:), pop_size, 1) + rand(pop_size, problem_size)
%              .* (repmat(lu(2,:) - lu(1,:), pop_size, 1));
% Consumes exactly one rand(np, D) draw, like the references. MATLAB implicit
% expansion keeps the same values while avoiding two full-size bound copies.

dim = numel(lb);
pop = lb + rand(np, dim) .* (ub - lb);

end
