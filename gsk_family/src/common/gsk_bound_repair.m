function vi = gsk_bound_repair(vi, pop, lb, ub)
%GSK_BOUND_REPAIR Midpoint (L-SHADE style) bound repair.
%
%   vi = gsk_bound_repair(vi, pop, lb, ub)
%
% Any component of vi below the lower bound is replaced by the midpoint of
% the parent component and the lower bound; symmetrically for the upper
% bound. Components inside the bounds are untouched. Consumes no random
% numbers.
%
% Transcribed from boundConstraint.m, identical copies at:
%   historical source: agsk/agsk/AGSK-CODE-FINAL/boundConstraint.m
%   historical source: apgsk/apgsk/APGSK Code/boundConstraint.m
%   historical source: atmalsgsk/atmalsgsk/cec2017/boundConstraint.m
% and inlined with the same rule (0.5*(pop+bound)) in:
%   historical source: gsk/gsk/GSK_Enhanced.m

[np, ~] = size(pop);

% check the lower bound
xl = repmat(lb, np, 1);
pos = vi < xl;
vi(pos) = (pop(pos) + xl(pos)) / 2;

% check the upper bound
xu = repmat(ub, np, 1);
pos = vi > xu;
vi(pos) = (pop(pos) + xu(pos)) / 2;

end
