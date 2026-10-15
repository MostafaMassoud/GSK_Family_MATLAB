function [P_new, P_old] = atmals_prob_update(P_old, VALs, val, Mean_Fit, Mean_Fit_New, alpha)
%ATMALS_PROB_UPDATE Faithful port of the ATMALS-GSK probability-table update.
%
%   Appends one reward row for the pool value val to the history P_old and
%   returns P_new, the memory-weighted sum of all rows (1 x numel(VALs)).
%   VALs is the value pool (row vector) and must contain val. Mean_Fit and
%   Mean_Fit_New are the best-half mean signals of the previous and current
%   generation; alpha is the memory factor (0.98 in ATMALS-GSK).
%
%   historical source: atmalsgsk/atmalsgsk/cec2017/ProbUpdate.m
%   (byte-identical copy in .../cec2011/). Transcribed verbatim; only
%   gaussmf is replaced by atmals_gaussmf (same formula, no toolbox).
%
% Reference quirks, kept on purpose (do NOT "fix"):
%   * The gaussmf CENTER is the pool INDEX i, but it is evaluated at the
%     pool VALUES, so the two use different scales.
%   * Row j gets weight alpha^j, so the OLDEST row (the all-ones prior)
%     weighs MOST and the newest reward least.
%   * P_old grows by one row per call, with no limit (as in the reference).
%   * Mean_Fit == 0 divides by zero in exp(... / abs(Mean_Fit)), as in the
%     reference.

i = find(abs(VALs - val) < eps);   % pool index of val (the gaussmf center)
yy = atmals_gaussmf(VALs, [0.05 * (max(VALs) - min(VALs)) i]);

% New reward row: yy if the signal improved (went down), 0.1*(1 - yy) if it
% got worse, both scaled by exp(-change / abs(Mean_Fit)); zeros if equal.
if Mean_Fit_New < Mean_Fit
    P_old = [P_old; yy * (exp(-(Mean_Fit_New - Mean_Fit) / abs(Mean_Fit)))];
elseif Mean_Fit_New > Mean_Fit
    P_old = [P_old; (1 - yy) * 0.1 * (exp(-(Mean_Fit_New - Mean_Fit) / abs(Mean_Fit)))];
else
    P_old = [P_old; zeros(1, size(P_old, 2))];
end

% Sum the history rows, row j weighted by alpha^j.
P_new = zeros(1, length(yy));
for i = 1:size(P_old, 1)
    P_new = P_new + alpha^(size(P_old, 1) - i + 1) * P_old(size(P_old, 1) - i + 1, :);
end

end
