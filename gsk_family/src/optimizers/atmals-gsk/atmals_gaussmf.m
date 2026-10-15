function y = atmals_gaussmf(x, params)
%ATMALS_GAUSSMF Local replacement for the Fuzzy Logic Toolbox gaussmf.
%
% gaussmf(x, [sig c]) evaluates the Gaussian membership function
%     y = exp(-(x - c).^2 ./ (2 * sig.^2))
% This implementation is mathematically identical to the toolbox function
% and removes the Fuzzy Logic Toolbox dependency (sanctioned replacement,
% see docs/reference/matlab_interface.md "Toolbox policy").
%
% Used by atmals_prob_update.m, which transcribes the reference call
%   gaussmf(VALs, [0.05*(max(VALs)-min(VALs)) i])
% from historical source: atmalsgsk/atmalsgsk/cec2017/ProbUpdate.m.

sig = params(1);
c = params(2);
y = exp(-(x - c).^2 ./ (2 * sig.^2));

end
