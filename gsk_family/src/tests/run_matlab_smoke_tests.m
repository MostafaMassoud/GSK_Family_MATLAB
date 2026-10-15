function run_matlab_smoke_tests()
%RUN_MATLAB_SMOKE_TESTS Discover and run every src/tests/test_*.m.
%
% Usage (CI / command line):
%   matlab -batch "cd('<repo>/src/tests'); run_matlab_smoke_tests"
%
% Discovers every test_*.m in this folder dynamically with dir() (tests
% added later are picked up automatically), runs each test function in a
% try/catch, prints PASS/FAIL per test, and ends with error() if any test
% failed so that matlab -batch exits nonzero.

this_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(this_dir);

% Make the tests, the shared helpers and every optimizer reachable.
addpath(this_dir);
addpath(genpath(src_dir));

listing = dir(fullfile(this_dir, 'test_*.m'));
names = sort({listing.name});
n_total = numel(names);
n_failed = 0;

fprintf('Running %d MATLAB smoke test(s) from %s\n', n_total, this_dir);
fprintf('--------------------------------------------------------------\n');

for i = 1:n_total
    [~, func_name] = fileparts(names{i});
    t0 = tic;
    try
        feval(func_name);
        fprintf('PASS  %-28s (%.2fs)\n', func_name, toc(t0));
    catch err
        n_failed = n_failed + 1;
        fprintf('FAIL  %-28s (%.2fs)\n', func_name, toc(t0));
        msg = strrep(err.message, sprintf('\n'), sprintf('\n      '));
        fprintf('      %s\n', msg);
        if ~isempty(err.stack)
            fprintf('      at %s (line %d)\n', err.stack(1).name, err.stack(1).line);
        end
    end
end

fprintf('--------------------------------------------------------------\n');
if n_failed > 0
    error('run_matlab_smoke_tests:failed', ...
        '%d of %d test(s) FAILED', n_failed, n_total);
else
    fprintf('All %d test(s) passed.\n', n_total);
end

end
