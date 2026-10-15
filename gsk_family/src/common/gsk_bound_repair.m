function vi = gsk_bound_repair(vi, pop, lb, ub)
%GSK_BOUND_REPAIR Midpoint (L-SHADE style) bound repair.
%
%   vi = gsk_bound_repair(vi, pop, lb, ub)
%
% vi (candidates) and pop (parents) are NP x D; lb and ub are 1 x D rows.
% A component of vi below lb becomes the midpoint of the parent component
% and lb; likewise for ub. Violations use strict < and >; components inside
% the bounds are unchanged. Draws no random numbers.
%
% Source: boundConstraint.m, identical copies in agsk/agsk/AGSK-CODE-FINAL/,
% apgsk/apgsk/APGSK Code/ and atmalsgsk/atmalsgsk/cec2017/; inlined with the
% same 0.5*(pop+bound) rule in gsk/gsk/GSK_Enhanced.m.

[np, ~] = size(pop);

% Lower bound.
xl = repmat(lb, np, 1);
pos = vi < xl;
vi(pos) = (pop(pos) + xl(pos)) / 2;

% Upper bound.
xu = repmat(ub, np, 1);
pos = vi > xu;
vi(pos) = (pop(pos) + xu(pos)) / 2;

end
