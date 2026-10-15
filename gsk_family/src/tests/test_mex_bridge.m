function test_mex_bridge()
%TEST_MEX_BRIDGE Verify gskcec_eval evaluates the C++ ports correctly.
%
% Compares the bridge with the MEX-derived ground truth in
% benchmarks/cec_suite_cpp/cec_tools/tests/data/ (the same values the C++
% unit tests use). Checks:
%   - D x NP input (one candidate per column), the 'info' struct and
%     batch evaluation;
%   - handle lifecycle: a live handle keeps the MEX locked, so 'clear'
%     cannot reuse its id;
%   - input validation: sparse X and non-integer or non-finite integer
%     arguments raise gskcec:badInput;
%   - the gskcec_require_mex load probe.
%
% If the bridge is not built, prints SKIP and returns (not a failure), so
% the smoke suite still runs without the optional MEX component.

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

% Ground truth columns: function, dimension, point index, expected f.
expected = readmatrix(fullfile(test_data, 'cec2017_expected.csv'), 'FileType', 'text', ...
                      'NumHeaderLines', 3);
points10 = readmatrix(fullfile(test_data, 'points_D10.txt'), 'FileType', 'text');
assert(size(points10, 2) == 10, 'points_D10 must have 10 columns');

% Single-problem correctness: CEC2017 f1, D = 10, all 5 probe points.
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

% Input validation: sparse X is rejected (the bridge would see only its
% nonzero buffer), and integer arguments must not be silently truncated
% (1.7 -> 1, h+0.5 -> h).
expect_bad_input(@() gskcec_eval('eval', h, sparse(X)), 'sparse X');
expect_bad_input(@() gskcec_eval('eval', h, sparse(10, 2)), 'all-zero sparse X');
expect_bad_input(@() gskcec_eval('new', 'cec2017', 1.7, 10, data_root), 'non-integer function_id');
expect_bad_input(@() gskcec_eval('new', 'cec2017', 1, 10.9, data_root), 'non-integer dimension');
expect_bad_input(@() gskcec_eval('new', 'cec2017', NaN, 10, data_root), 'NaN function_id');
expect_bad_input(@() gskcec_eval('new', 'cec2017', 1, Inf, data_root), 'Inf dimension');
expect_bad_input(@() gskcec_eval('new', 'cec2017', 1, 2^40, data_root), 'out-of-int-range dimension');
expect_bad_input(@() gskcec_eval('eval', h + 0.5, X), 'non-integer eval handle');
expect_bad_input(@() gskcec_eval('info', NaN), 'NaN info handle');
expect_bad_input(@() gskcec_eval('free', h + 0.5), 'non-integer free handle');
assert(isequal(gskcec_eval('eval', h, X), f), 'rejected calls must leave handle h intact');
gskcec_eval('free', h);

% Handle lifecycle: a live handle locks the MEX, so 'clear' cannot unload it
% and hand the same id to a new problem; freeing the last handle unlocks it.
gskcec_eval('clear');
assert(~mislocked('gskcec_eval'), 'bridge must be unlocked with no live handle');
h_live = gskcec_eval('new', 'cec2017', 1, 10, data_root);
assert(mislocked('gskcec_eval'), 'a live handle must lock the bridge');
clear('gskcec_eval');
h_other = gskcec_eval('new', 'cec2017', 5, 10, data_root);
assert(h_other ~= h_live, 'clear must not recycle a live handle id');
assert(isequal(gskcec_eval('eval', h_live, X), f), ...
       'a live handle must still evaluate its own problem after clear');
gskcec_eval('free', h_live);
assert(mislocked('gskcec_eval'), 'bridge stays locked while any handle is live');
gskcec_eval('free', h_other);
assert(~mislocked('gskcec_eval'), 'freeing the last handle must unlock the bridge');

% Second suite and handle lifecycle: CEC2020 public f5 (internal 4), D = 10.
h2 = gskcec_eval('new', 'cec2020', 5, 10, ...
                 fullfile(project_root, 'benchmarks', 'cec_suite_cpp', 'cec2020', 'input_data'));
info2 = gskcec_eval('info', h2);
assert(info2.optimum == 1700, 'cec2020 public f5 optimum (AGSK vector) is 1700');
f2 = gskcec_eval('eval', h2, info2.lb');   % single column
assert(isscalar(f2) && isfinite(f2), 'cec2020 single-column eval');
gskcec_eval('free', h2);

% Bridge errors surface as MATLAB errors (here: an invalid function id).
threw = false;
try
    gskcec_eval('new', 'cec2017', 99, 10, data_root);
catch
    threw = true;
end
assert(threw, 'invalid function id must raise');

gskcec_eval('clear');
assert(~mislocked('gskcec_eval'), '''clear'' must unlock the bridge');

% The gskcec_require_mex startup check must accept a bridge that loads
% (it forces a real load) and must not leave a live handle behind.
addpath(fullfile(project_root, 'src', 'runners'));
gskcec_require_mex(project_root, 'test_mex_bridge');
assert(~mislocked('gskcec_eval'), 'the gskcec_require_mex probe must not create a handle');

fprintf('test_mex_bridge: PASS (cec2017 f1 D10 max rel %.3g vs MEX ground truth)\n', max_rel);
end

function expect_bad_input(fn, label)
%EXPECT_BAD_INPUT Assert that fn raises the bridge's gskcec:badInput error.
try
    fn();
catch err
    assert(strcmp(err.identifier, 'gskcec:badInput'), ...
           '%s: expected gskcec:badInput, got %s (%s)', label, err.identifier, err.message);
    return;
end
error('test_mex_bridge:noError', '%s: expected gskcec:badInput, but the call succeeded', label);
end
