function tr = gsk_trace_add(tr, nfes, pop, lb, ub, names, values)
%GSK_TRACE_ADD Add one generation to an opt-in dynamics trace.
%
%   tr = gsk_trace_add(tr, nfes, pop, lb, ub)
%   tr = gsk_trace_add(tr, nfes, pop, lb, ub, names, values)
%
% Records nfes, the population size NP = size(pop, 1) and the population
% diversity, plus the optimizer's own parameters (names: cell of column
% names; values: numbers, one per name, NaN where undefined). The first call
% fixes the columns. Callers guard the call with "if tr.on".
%
% Diversity follows the dimension-wise measure of Hussain et al. (2019,
% Artif. Intell. Rev. 52:2191-2233): for each dimension j,
%   Div_j = mean_i |median(x(:, j)) - x(i, j)|,
% here divided by the dimension's range ub(j) - lb(j) so that it is
% comparable across problems; Div is the mean of Div_j over the dimensions
% with a nonzero range. Plain arithmetic: no random numbers.
if nargin < 6; names = {}; values = []; end
if tr.n == 0
    tr.names = [{'nfes', 'np', 'diversity'}, names(:)'];
    tr.rows = nan(tr.max_rows, numel(tr.names));
end
lb = lb(:)'; ub = ub(:)';
if isscalar(lb); lb = repmat(lb, 1, size(pop, 2)); end
if isscalar(ub); ub = repmat(ub, 1, size(pop, 2)); end
span = ub - lb;
use = span > 0;
if any(use)
    dev = mean(abs(pop(:, use) - median(pop(:, use), 1)), 1) ./ span(use);
    div = mean(dev);
else
    div = 0;
end
tr.n = tr.n + 1;
if tr.n > size(tr.rows, 1)
    tr.rows = [tr.rows; nan(size(tr.rows, 1), numel(tr.names))];
end
tr.rows(tr.n, :) = [nfes, size(pop, 1), div, double(values(:)')];
end
