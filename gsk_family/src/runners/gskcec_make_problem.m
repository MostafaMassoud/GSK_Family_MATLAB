function problem = gskcec_make_problem(suite, func_id, dim, project_root, max_nfes_override)
%GSKCEC_MAKE_PROBLEM Problem struct for the MATLAB optimizers.
%
% Usage: problem = gskcec_make_problem(suite, func_id, dim, project_root,
%                                      max_nfes_override)
% CEC suites evaluate through the gskcec_eval MEX bridge (the C++ ports under
% benchmarks/; build it with scripts/build_mex_bridge.ps1). The test-only
% 'sphere' suite is pure MATLAB, so optimizer and runner smoke tests need no
% MEX. func_id is 1-based. For cec2011 and cec2013lsgo, dim = 0 selects each
% function's fixed D.
%
% Output fields: suite, func_id, dim (actual D), lb and ub (1 x D), optimum,
% evaluate (NP x D population -> NP x 1 values), max_nfes, target_error. CEC
% suites also set mex_handle; the caller (run_experiment) must free it.
%
% Budget and target error (docs/reference/benchmark_protocol.md):
%   sphere/cec2017/cec2013: 10000*D evaluations, target error 1e-8
%   cec2020:     AGSK protocol budgets (D5 50k, D10 1M, D15 3M, D20 10M), 1e-8
%   cec2011:     150000 evaluations, no known optima (target NaN)
%   cec2013lsgo: 3e6 evaluations (LSGO competition protocol), target NaN
% A positive max_nfes_override (default 0) replaces the default budget.
%
% Errors: gskcec:badDimension (sphere with dim <= 0, cec2020 D not in
% 5/10/15/20), gskcec:mexMissing, gskcec:badSuite.

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
% Free the handle on any later failure (e.g. an unknown suite or dimension
% below) so a partial build never leaks it. On success the caller
% (run_experiment) owns and frees it, so free only in the catch.
try
    info = gskcec_eval('info', handle);

    problem.dim = info.dimension;
    problem.lb = info.lb;
    problem.ub = info.ub;
    problem.optimum = info.optimum;
    % Optimizers pass NP x D populations (one candidate per row, the reference
    % convention); the bridge, like the original CEC MEX files, takes D x NP
    % (one per column).
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
% CEC2011 F8 has continuous bounds [0,15] but indexes Candidate(ceil(x),:),
% so x == 0 would give index 0 in the original MATLAB code. Clamping to
% [eps(1), 15] maps every point to one of the 15 candidates before the MEX
% call.
pop = min(max(pop, eps(1)), 15);
end
