function report = cec_complexity(varargin)
%CEC_COMPLEXITY Algorithm complexity table of the CEC technical reports (T0, T1, T2).
%
%   cec_complexity('suite','cec2017', 'optimizers',{'my-gsk','gsk'})
%   report = cec_complexity('suite','cec2017', 'optimizers',{'gsk'}, 'dimensions',[10 30])
%
% Measures, as defined in the CEC2017 technical report (Awad et al., 2016):
%   T0        time of the CEC test program: x = 0.55, then 1,000,000 times
%             x = x + x; x = x / 2; x = x * x; x = sqrt(x); x = log(x);
%             x = exp(x); x = x / (x + 2);
%   T1        time of 200,000 evaluations of the suite's complexity function
%             at dimension D (random points inside the bounds, evaluated in
%             batches of 'batch' rows through the same MEX bridge the
%             optimizers use)
%   T2        time of a complete run of the optimizer with 200,000
%             evaluations of the same function (runtime_seconds of a serial
%             run_experiment run: from the optimizer's start to its result);
%             T2_hat is the mean of 'repeats' runs (default 5)
%   ratio     (T2_hat - T1) / T0
% for every optimizer (the seven, your own, or algorithms.ini aliases) and
% dimension. It RUNS the optimizers: 4 dimensions x 5 runs x 200,000
% evaluations each, serially, so it can take from minutes to hours. Close
% other programs while it runs: the numbers are wall-clock times.
%
% Options:
%   suite         'cec2017' (default function 18, as in its report). For other
%                 suites pass 'function' with the one their technical report
%                 names; there is no built-in default for them.
%   optimizers    cell of optimizer ids or aliases (required).
%   labels        display names (default GSK, AGSK, ..., or the id in capitals).
%   dimensions    default [10 30 50 100] (cec2017); 0 for native-dimension suites.
%   function      complexity function id (default 18 for cec2017).
%   evals         evaluations for T1 and T2 (default 200000).
%   repeats       runs averaged into T2_hat (default 5).
%   batch         rows per evaluation call for T1 (default 100, the usual NP).
%   output_dir    Default <project_root>/results/analysis/complexity/<suite>.
%   work_dir      Where the timing runs are written (default a temporary
%                 folder, deleted afterwards). Never results/_run_all.
%   project_root  Default pwd (the gsk_family folder).
%
% Writes complexity_<suite>.csv (optimizer, label, dimension, T0, T1, T2_hat,
% T2 of each run, ratio) and complexity_<suite>.tex (the table of the
% technical report). Times are in seconds.

p = inputParser;
p.addParameter('suite', 'cec2017', @(x) ischar(x) || isstring(x));
p.addParameter('optimizers', {}, @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('labels', {}, @(x) iscell(x) || isstring(x));
p.addParameter('dimensions', [], @isnumeric);
p.addParameter('function', [], @isnumeric);
p.addParameter('evals', 200000, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('repeats', 5, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('batch', 100, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('work_dir', '', @(x) ischar(x) || isstring(x));
p.addParameter('project_root', pwd, @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
a = p.Results;
a.suite = lower(char(a.suite));
a.project_root = char(a.project_root);
opts = cellstr(a.optimizers);
assert(~isempty(opts) && ~isempty(opts{1}), 'cec_complexity:args', 'optimizers is required');
if isempty(a.function)
    assert(strcmp(a.suite, 'cec2017'), 'cec_complexity:args', ...
           ['pass ''function'' for %s: the complexity function its technical report names ' ...
            '(cec2017 uses function 18)'], a.suite);
    a.function = 18;
end
if isempty(a.dimensions)
    if any(strcmp(a.suite, {'cec2011', 'cec2013lsgo'})); a.dimensions = 0; else; a.dimensions = [10 30 50 100]; end
end
if isempty(a.labels)
    labels = cellfun(@display_name, opts, 'UniformOutput', false);
else
    labels = cellstr(a.labels);
    assert(numel(labels) == numel(opts), 'cec_complexity:args', 'labels must have one entry per optimizer');
end
if isempty(a.output_dir); a.output_dir = fullfile(a.project_root, 'results', 'analysis', 'complexity', a.suite); end
a.output_dir = char(a.output_dir);
work = char(a.work_dir);
temp_work = isempty(work);
if temp_work; work = fullfile(tempdir, sprintf('gsk_complexity_%d', feature('getpid'))); end
assert(~contains(strrep(work, '\', '/'), 'results/_run_all'), 'cec_complexity:args', ...
       'work_dir must not be inside results/_run_all (timing runs use a changed budget)');
addpath(fullfile(a.project_root, 'src', 'runners'));
addpath(fullfile(a.project_root, 'src', 'common'));
addpath(fullfile(a.project_root, 'build', 'mex'));
if ~exist(a.output_dir, 'dir'); mkdir(a.output_dir); end
cleanup = onCleanup(@() remove_temp(work, temp_work));

t0 = measure_t0();
fprintf('cec_complexity: T0 = %.4f s\n', t0);
rows = struct('optimizer', {}, 'label', {}, 'dim', {}, 't0', {}, 't1', {}, 't2_hat', {}, 't2', {}, 'ratio', {});
for D = a.dimensions(:)'
    [t1, Dact] = measure_t1(a, D);
    fprintf('cec_complexity: %s F%d D%d: T1 = %.4f s (%d evaluations)\n', a.suite, a.function, Dact, t1, a.evals);
    for i = 1:numel(opts)
        out = fullfile(work, opts{i}, sprintf('D%d', Dact));
        run_experiment('optimizer', opts{i}, 'suite', a.suite, 'functions', a.function, ...
            'dimensions', D, 'runs', a.repeats, 'max_nfes', a.evals, 'project_root', a.project_root, ...
            'output_dir', out, 'overwrite', true, 'verbose', false, 'use_parallel', false);
        T = readtable(fullfile(out, 'summary', 'per_run.csv'), 'VariableNamingRule', 'preserve');
        t2 = T.runtime_seconds(:)';
        t2h = mean(t2);
        rows(end + 1) = struct('optimizer', opts{i}, 'label', labels{i}, 'dim', Dact, 't0', t0, ...
            't1', t1, 't2_hat', t2h, 't2', t2, 'ratio', (t2h - t1) / t0); %#ok<AGROW>
        fprintf('cec_complexity: %-12s D%-4d T2_hat = %.4f s   (T2_hat - T1)/T0 = %.4f\n', ...
                labels{i}, Dact, t2h, rows(end).ratio);
    end
end
write_tables(a, rows);
report = struct('t0', t0, 'rows', rows);
fprintf('cec_complexity: wrote complexity_%s.csv and .tex to %s\n', a.suite, a.output_dir);
end

function t = measure_t0()
% The CEC test program (see the help text).
tic;
x = 0.55;
for i = 1:1000000
    x = x + x; x = x / 2; x = x * x; x = sqrt(x); x = log(x); x = exp(x); x = x / (x + 2);
end
t = toc;
if ~isfinite(x); t = NaN; end
end

function [t, Dact] = measure_t1(a, D)
% evals evaluations of the complexity function at random points.
problem = gskcec_make_problem(a.suite, a.function, D, a.project_root, a.evals);
guard = onCleanup(@() free_problem(problem));
Dact = problem.dim;
rng(12345, 'twister');
n = a.evals; b = a.batch;
X = problem.lb + (problem.ub - problem.lb) .* rand(b, Dact);
tic;
done = 0;
while done < n
    m = min(b, n - done);
    problem.evaluate(X(1:m, :));
    done = done + m;
end
t = toc;
end

function free_problem(p)
if isfield(p, 'mex_handle'); gskcec_eval('free', p.mex_handle); end
end

function write_tables(a, rows)
fid = fopen(fullfile(a.output_dir, sprintf('complexity_%s.csv', a.suite)), 'w');
c1 = onCleanup(@() fclose(fid));
fprintf(fid, 'optimizer,label,dimension,function,evals,T0,T1,T2_hat,T2_runs,ratio\n');
for r = rows
    fprintf(fid, '%s,%s,%d,%d,%d,%.6f,%.6f,%.6f,"%s",%.6f\n', r.optimizer, r.label, r.dim, a.function, ...
            a.evals, r.t0, r.t1, r.t2_hat, strjoin(arrayfun(@(x) sprintf('%.6f', x), r.t2, ...
            'UniformOutput', false), ' '), r.ratio);
end
fid2 = fopen(fullfile(a.output_dir, sprintf('complexity_%s.tex', a.suite)), 'w');
c2 = onCleanup(@() fclose(fid2));
fprintf(fid2, '%% %s algorithm complexity, F%d, %d evaluations; T2 = mean of the runs; seconds.\n', ...
        upper(a.suite), a.function, a.evals);
fprintf(fid2, '\\begin{tabular}{llrrrr}\n\\hline\n');
fprintf(fid2, 'Algorithm & $D$ & $T_0$ & $T_1$ & $\\hat{T}_2$ & $(\\hat{T}_2 - T_1)/T_0$ \\\\\n\\hline\n');
for r = rows
    fprintf(fid2, '%s & %d & %.4f & %.4f & %.4f & %.2f \\\\\n', strrep(r.label, '_', '\_'), r.dim, ...
            r.t0, r.t1, r.t2_hat, r.ratio);
end
fprintf(fid2, '\\hline\n\\end{tabular}\n');
end

function remove_temp(work, is_temp)
if is_temp && exist(work, 'dir'); rmdir(work, 's'); end
end

function s = display_name(id)
switch id
    case 'egsk'; s = 'eGSK';
    otherwise;   s = upper(id);
end
end
