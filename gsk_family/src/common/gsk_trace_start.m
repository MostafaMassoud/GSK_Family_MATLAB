function tr = gsk_trace_start(options, max_rows)
%GSK_TRACE_START Start the opt-in per-generation dynamics trace of an optimizer.
%
%   tr = gsk_trace_start(options, max_rows)
%
% tr.on is true only when options.log_trace is true; then the optimizer adds
% one row per generation with gsk_trace_add and returns gsk_trace_finish(tr)
% as result.trace. With log_trace off (the default) the optimizer does
% nothing else, so its results are exactly those of a run without tracing.
% Tracing draws no random numbers and changes no value of the search, so a
% traced run also gives exactly the same results.
%
% max_rows is the expected number of rows (the convergence log's size);
% more rows are still accepted.
tr = struct('on', isfield(options, 'log_trace') && ~isempty(options.log_trace) && ...
                  logical(options.log_trace), ...
            'n', 0, 'rows', [], 'names', {{}}, 'max_rows', max(1, max_rows));
end
