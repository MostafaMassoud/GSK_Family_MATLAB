function pop = gsk_init_population(np, lb, ub)
%GSK_INIT_POPULATION Uniform random initialization within bounds.
%
%   pop = gsk_init_population(np, lb, ub)
%
% np is the population size NP; lb and ub are 1 x D bound rows. Returns an
% NP x D matrix. Draws exactly one rand(NP, D), as the references do.
% Implicit expansion gives the same values as the reference repmat form
% without two full-size bound copies.
%
% Source: the initialization line shared verbatim by gsk/gsk/GSK_Enhanced.m,
% atmalsgsk/atmalsgsk/cec2017/GSK.m and Adaptive_GSK_ALI.m in
% agsk/agsk/AGSK-CODE-FINAL/ and apgsk/apgsk/APGSK Code/:
%     popold = repmat(lu(1,:), pop_size, 1) + rand(pop_size, problem_size)
%              .* (repmat(lu(2,:) - lu(1,:), pop_size, 1));

dim = numel(lb);
pop = lb + rand(np, dim) .* (ub - lb);

end
