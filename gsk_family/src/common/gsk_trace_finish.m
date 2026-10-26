function trace = gsk_trace_finish(tr)
%GSK_TRACE_FINISH The dynamics trace as a struct for result.trace.
%
%   trace = gsk_trace_finish(tr)
%
% Returns struct('names', {column names}, 'rows', G x numel(names) matrix),
% one row per traced generation (nfes, np, diversity, then the optimizer's
% parameters), or [] when tracing was off.
if ~tr.on
    trace = [];
    return;
end
trace = struct('names', {tr.names}, 'rows', tr.rows(1:tr.n, :));
end
