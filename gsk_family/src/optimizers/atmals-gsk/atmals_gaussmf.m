function y = atmals_gaussmf(x, params)
%ATMALS_GAUSSMF Local replacement for the Fuzzy Logic Toolbox gaussmf.
%
%   y = atmals_gaussmf(x, [sig c]) returns the Gaussian membership values
%       y = exp(-(x - c).^2 ./ (2 * sig.^2))
%   This is the same formula as the toolbox gaussmf, so that toolbox is not
%   needed (approved under "Toolbox policy" in
%   docs/reference/matlab_interface.md).
%
%   Used by atmals_prob_update.m for the reference call
%     gaussmf(VALs, [0.05*(max(VALs)-min(VALs)) i])
%   from historical source: atmalsgsk/atmalsgsk/cec2017/ProbUpdate.m

sig = params(1);
c = params(2);
y = exp(-(x - c).^2 ./ (2 * sig.^2));

end
