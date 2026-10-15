function problem = gskcec_make_problem(suite, func_id, dim, project_root, max_nfes_override)
%GSKCEC_MAKE_PROBLEM Problem struct for the MATLAB optimizers.
%
% CEC suites evaluate through the gskcec_eval MEX bridge (the ported C++
% benchmarks under benchmarks/; build it with scripts/build_mex_bridge.ps1).
% The test-only 'sphere' suite is pure MATLAB so optimizer and runner smoke
% tests need no MEX.
%
% Budget and target-error policy (docs/reference/benchmark_protocol.md):
%   cec2017/cec2013: 10000*D evaluations, target error 1e-8
%   cec2020:         AGSK protocol budgets (D5 50k, D10 1M, D15 3M, D20 10M), 1e-8
%   cec2011:         150000 evaluations, no known optima (target NaN)
%   cec2013lsgo:     3e6 evaluations (LSGO competition protocol), target NaN
% A nonzero max_nfes_override replaces the default budget.

if nargin < 5
    max_nfes_override = 0;
end

problem = struct();
problem.suite = suite;
problem.func_id = func_id;

if strcmp(suite, 'sphere')
    % Pure-MATLAB test suite: no MEX, no data files.
    if dim <= 0
        error('gskcec:badDimension', 'sphere suite needs an explicit dimension');
    end
    problem.dim = dim;
    problem.lb = -100 * ones(1, dim);
    problem.ub = 100 * ones(1, dim);
    problem.optimum = 0;
    problem.evaluate = @(pop) sum(pop .^ 2, 2);
    problem.max_nfes = pick_budget(10000 * dim, max_nfes_override);
    problem.target_error = 1e-8;
    return;
end

if exist('gskcec_eval', 'file') ~= 3
    error('gskcec:mexMissing', ...
          ['gskcec_eval MEX bridge not found on the MATLAB path. Build it with ' ...
           'scripts\\build_mex_bridge.ps1 (output build\\mex\\gskcec_eval.mexw64). ' ...
           'See build.txt for the full C++/CEC prerequisite checklist.']);
end

data_root = fullfile(project_root, 'benchmarks', 'cec_suite_cpp', suite, 'input_data');
handle = gskcec_eval('new', suite, func_id, dim, data_root);
% Once the bridge handle is allocated, free it on any later failure (e.g. an
% unknown-dimension/unknown-suite error below) so a partial construction never
% leaks a live handle. On success the handle is returned to the caller, which
% frees it (run_experiment); hence free in the catch only, not unconditionally.
try
    info = gskcec_eval('info', handle);

    problem.dim = info.dimension;
    problem.lb = info.lb;
    problem.ub = info.ub;
    problem.optimum = info.optimum;
    % Optimizers use row-wise NPxD populations (reference convention); the
    % bridge wants one candidate per column like the original CEC MEX files.
    if strcmp(suite, 'cec2011') && func_id == 8
        problem.evaluate = @(pop) gskcec_eval('eval', handle, repair_cec2011_f8_population(pop)')';
    else
        problem.evaluate = @(pop) gskcec_eval('eval', handle, pop')';
    end
    problem.mex_handle = handle;

    switch suite
        case {'cec2017', 'cec2013'}
            problem.max_nfes = pick_budget(10000 * problem.dim, max_nfes_override);
            problem.target_error = 1e-8;
        case 'cec2020'
            budgets = containers.Map({5, 10, 15, 20}, {50000, 1000000, 3000000, 10000000});
            if ~isKey(budgets, problem.dim)
                error('gskcec:badDimension', 'cec2020 has no reference budget for D=%d', problem.dim);
            end
            problem.max_nfes = pick_budget(budgets(problem.dim), max_nfes_override);
            problem.target_error = 1e-8;
        case 'cec2011'
            problem.max_nfes = pick_budget(150000, max_nfes_override);
            problem.target_error = NaN;
        case 'cec2013lsgo'
            problem.max_nfes = pick_budget(3000000, max_nfes_override);
            problem.target_error = NaN;
        otherwise
            error('gskcec:badSuite', 'Unknown suite ''%s''.', suite);
    end
catch err
    gskcec_eval('free', handle);
    rethrow(err);
end
end

function budget = pick_budget(default_budget, override)
if override > 0
    budget = override;
else
    budget = default_budget;
end
end

function pop = repair_cec2011_f8_population(pop)
%REPAIR_CEC2011_F8_POPULATION Keep F8's discrete candidate index in 1..15.
% CEC2011 F8 publishes continuous bounds [0,15], but internally uses
% Candidate(ceil(x),:). The inclusive lower bound x == 0 would produce index
% 0 in the historical MATLAB code. Map the usable benchmark domain to the 15
% documented candidates before calling the MEX evaluator.
pop = min(max(pop, eps(1)), 15);
end
