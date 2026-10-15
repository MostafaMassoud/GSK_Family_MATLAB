function test_mex_bridge()
%TEST_MEX_BRIDGE Verify gskcec_eval evaluates the C++ ports correctly.
%
% Cross-checks the bridge against the MEX-derived ground truth in
% benchmarks/cec_suite_cpp/cec_tools/tests/data/ (the same values the C++ unit tests
% use), proving the bridge wiring: D x NP orientation, the 'info' struct,
% batch evaluation, and handle lifecycle.
%
% Skips with a clear message (not a failure) when the bridge has not been
% built, so the smoke suite still runs without the optional MEX component.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
mex_dir = fullfile(project_root, 'build', 'mex');
addpath(mex_dir);
if exist('gskcec_eval', 'file') ~= 3
    fprintf('test_mex_bridge: SKIP (gskcec_eval not built; run scripts/build_mex_bridge.ps1)\n');
    return;
end

data_root = fullfile(project_root, 'benchmarks', 'cec_suite_cpp', 'cec2017', 'input_data');
test_data = fullfile(project_root, 'benchmarks', 'cec_suite_cpp', 'cec_tools', 'tests', 'data');

% Ground truth: function, dimension, point index, expected f.
expected = readmatrix(fullfile(test_data, 'cec2017_expected.csv'), 'FileType', 'text', ...
                      'NumHeaderLines', 3);
points10 = readmatrix(fullfile(test_data, 'points_D10.txt'), 'FileType', 'text');
assert(size(points10, 2) == 10, 'points_D10 must have 10 columns');

% Single-problem correctness: cec2017 f1, D=10, all 5 probe points.
h = gskcec_eval('new', 'cec2017', 1, 10, data_root);
info = gskcec_eval('info', h);
assert(info.dimension == 10, 'info dimension');
assert(numel(info.lb) == 10 && all(info.lb == -100) && all(info.ub == 100), 'info bounds');
assert(info.optimum == 100, 'cec2017 f1 optimum is 100');

% Batch evaluate: bridge expects D x NP (one candidate per column).
X = points10';                       % 10 x 5
f = gskcec_eval('eval', h, X);       % 1 x 5
assert(isequal(size(f), [1, 5]), 'batch output shape 1 x NP');

max_rel = 0;
for p = 1:5
    rows = expected(expected(:, 1) == 1 & expected(:, 2) == 10 & expected(:, 3) == p, :);
    assert(~isempty(rows), 'missing expected row f1 D10 p%d', p);
    exp_f = rows(1, 4);
    rel = abs(f(p) - exp_f) / max(1, abs(exp_f));
    max_rel = max(max_rel, rel);
    assert(rel <= 1e-10, 'f1 D10 p%d: bridge %.17g vs expected %.17g (rel %g)', ...
           p, f(p), exp_f, rel);
end
gskcec_eval('free', h);

% A second suite + handle lifecycle: cec2020 public f5 (internal 4), D=10.
h2 = gskcec_eval('new', 'cec2020', 5, 10, ...
                 fullfile(project_root, 'benchmarks', 'cec_suite_cpp', 'cec2020', 'input_data'));
info2 = gskcec_eval('info', h2);
assert(info2.optimum == 1700, 'cec2020 public f5 optimum (AGSK vector) is 1700');
f2 = gskcec_eval('eval', h2, info2.lb');   % single column
assert(isscalar(f2) && isfinite(f2), 'cec2020 single-column eval');
gskcec_eval('free', h2);

% Error handling surfaces as MATLAB errors.
threw = false;
try
    gskcec_eval('new', 'cec2017', 99, 10, data_root);
catch
    threw = true;
end
assert(threw, 'invalid function id must raise');

gskcec_eval('clear');
fprintf('test_mex_bridge: PASS (cec2017 f1 D10 max rel %.3g vs MEX ground truth)\n', max_rel);
end
