function run_matlab_smoke_tests()
%RUN_MATLAB_SMOKE_TESTS Discover and run every src/tests/test_*.m.
%
% Usage (CI / command line):
%   matlab -batch "cd('<repo>/src/tests'); run_matlab_smoke_tests"
%
% Finds every test_*.m in this folder at run time, so new tests are picked
% up automatically. Runs each test in try/catch and prints PASS or FAIL.
% Raises run_matlab_smoke_tests:failed if any test fails, so that
% matlab -batch exits nonzero.

this_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(this_dir);

% Put the tests, the shared helpers and all optimizers on the path.
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
