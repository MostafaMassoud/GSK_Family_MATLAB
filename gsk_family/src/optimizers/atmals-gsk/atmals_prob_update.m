function [P_new, P_old] = atmals_prob_update(P_old, VALs, val, Mean_Fit, Mean_Fit_New, alpha)
%ATMALS_PROB_UPDATE Faithful port of the ATMALS-GSK probability-table update.
%
% Source (transcribed verbatim, only gaussmf replaced):
%   historical source: atmalsgsk/atmalsgsk/cec2017/ProbUpdate.m
%   (byte-identical copy: .../cec2011/ProbUpdate.m)
%
% The Fuzzy Logic Toolbox gaussmf is replaced by atmals_gaussmf, which is
% mathematically identical: gaussmf(x,[sig c]) = exp(-(x-c).^2./(2*sig.^2)).
%
% Preserved reference quirks (deliberate, do NOT "fix"):
%   * The gaussian membership CENTER is the pool INDEX i (find(...)), while
%     the membership is evaluated at the pool VALUES, so bump location and
%     evaluation points live on different scales.
%   * Exponential memory with alpha = 0.98: history row j is weighted
%     alpha^j, so the OLDEST row (the initial all-ones prior) carries the
%     LARGEST weight and the newest reward the smallest.
%   * P_old grows by one row per call (unbounded history, as the reference
%     accumulates *_OLDMAT matrices).
%   * If Mean_Fit == 0 the exp(... / abs(Mean_Fit)) terms divide by zero,
%     exactly as in the reference.

i = find(abs(VALs - val) < eps);
yy = atmals_gaussmf(VALs, [0.05 * (max(VALs) - min(VALs)) i]);

if Mean_Fit_New < Mean_Fit
    P_old = [P_old; yy * (exp(-(Mean_Fit_New - Mean_Fit) / abs(Mean_Fit)))];
elseif Mean_Fit_New > Mean_Fit
    P_old = [P_old; (1 - yy) * 0.1 * (exp(-(Mean_Fit_New - Mean_Fit) / abs(Mean_Fit)))];
else
    P_old = [P_old; zeros(1, size(P_old, 2))];
end

P_new = zeros(1, length(yy));
for i = 1:size(P_old, 1)
    P_new = P_new + alpha^(size(P_old, 1) - i + 1) * P_old(size(P_old, 1) - i + 1, :);
end

end
