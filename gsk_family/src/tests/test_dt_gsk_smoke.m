function test_dt_gsk_smoke()
%TEST_DT_GSK_SMOKE Contract, determinism and reference-parity checks for DT-GSK.
%
% Uses only the pure-MATLAB sphere problem, so the MEX bridge is not needed.
% Checks:
%   1. the result struct follows docs/reference/matlab_interface.md;
%   2. the full budget is used exactly (nfes == max_nfes, 'max_evaluations');
%      the convergence trace is best-so-far (non-increasing), and its nfes
%      increase strictly and end at max_nfes;
%   3. the same seed reproduces the run bit for bit; a different seed does not;
%   4. a runner-supplied X0 and post-X0 RNG state are ignored (documented
%      fair-start exception), the global RNG is left untouched, and a
%      non-Threefry generator raises dt_gsk_optimize:options;
%   5. the byte-stable golden values of the DT-GSK reference implementation
%      (seed 12345, 3000 evaluations, pub profile) are matched to 1e-9
%      relative. MATLAB's Threefry doubles differ from the reference by
%      <= 1 ulp per draw, so runs agree to ~1e-13, not bit for bit;
%   6. every dimension tier (D < 20, 20 <= D < 50, D >= 50, D >= 100) runs.

here = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(here));
addpath(fullfile(project_root, 'src', 'runners'));
addpath(fullfile(project_root, 'src', 'optimizers', 'dt-gsk'));

% ---- 1-2. contract + budget + trace ------------------------------------------
p = gskcec_make_problem('sphere', 1, 10, project_root, 3000);
r = dt_gsk_optimize(p, struct('seed', 12345, 'rand_generator', 'threefry'));
fields = {'optimizer', 'suite', 'func_id', 'dim', 'seed', 'best_x', 'best_fitness', ...
          'error', 'nfes', 'termination', 'convergence', 'runtime_seconds', 'params', 'notes'};
for k = 1:numel(fields)
    assert(isfield(r, fields{k}), 'result field missing: %s', fields{k});
end
assert(strcmp(r.optimizer, 'dt-gsk'), 'optimizer id');
assert(isequal(size(r.best_x), [1 10]), 'best_x must be 1 x D');
assert(r.nfes == 3000, 'DT-GSK must use the full budget exactly (nfes=%d)', r.nfes);
assert(strcmp(r.termination, 'max_evaluations'), 'termination');
assert(abs(sum(r.best_x .^ 2) - r.best_fitness) <= 1e-12 * max(1, r.best_fitness), ...
       'best_fitness must be the objective value of best_x');
c = r.convergence;
assert(all(diff(c.nfes) > 0) && c.nfes(end) == r.nfes, 'convergence nfes must increase to nfes');
assert(all(diff(c.best_fitness) <= 0), 'convergence trace must be best-so-far');
assert(c.best_fitness(end) == r.best_fitness, 'trace must end at best_fitness');
if r.best_fitness < p.target_error
    assert(r.error == 0, 'target-error zeroing');
else
    assert(r.error == r.best_fitness - p.optimum, 'error = best - optimum');
end
assert(strcmp(r.params.profile, 'pub'), 'pub profile');

% ---- 3. determinism ------------------------------------------------------------
r2 = dt_gsk_optimize(p, struct('seed', 12345));
assert(isequal(r2.best_x, r.best_x) && r2.best_fitness == r.best_fitness && ...
       isequal(r2.convergence.best_fitness, c.best_fitness), 'same seed must reproduce the run');
r3 = dt_gsk_optimize(p, struct('seed', 12346));
assert(r3.best_fitness ~= r.best_fitness, 'a different seed should give a different run');

% ---- 4. fair-start exception + global RNG untouched -----------------------------
rng(77, 'twister');
before = rng;
x0 = -100 + 200 * rand(RandStream('twister', 'Seed', 5), 100, 10);
r4 = dt_gsk_optimize(p, struct('seed', 12345, 'initial_population', x0, ...
                               'rng_state_after_initialization', before));
assert(r4.best_fitness == r.best_fitness, 'DT-GSK must ignore a supplied X0');
assert(isequaln(rng, before), 'DT-GSK must not touch the global RNG');
threw = false;
try
    dt_gsk_optimize(p, struct('seed', 1, 'rand_generator', 'twister'));
catch err
    threw = strcmp(err.identifier, 'dt_gsk_optimize:options');
end
assert(threw, 'non-threefry generators must be rejected');

% ---- 5. parity with the reference golden values -------------------------------
golden = {10, 0.2945738850554555; 30, 761.956387784266};
for k = 1:size(golden, 1)
    pg = gskcec_make_problem('sphere', 1, golden{k, 1}, project_root, 3000);
    rg = dt_gsk_optimize(pg, struct('seed', 12345));
    rel = abs(rg.best_fitness - golden{k, 2}) / golden{k, 2};
    assert(rel <= 1e-9, 'sphere D%d golden mismatch: %.17g vs reference %.17g (rel %.3g)', ...
           golden{k, 1}, rg.best_fitness, golden{k, 2}, rel);
end

% ---- 6. every dimension tier runs to budget -------------------------------------
for D = [5 20 50 100]
    pt = gskcec_make_problem('sphere', 1, D, project_root, 2000);
    rt = dt_gsk_optimize(pt, struct('seed', 3));
    assert(rt.nfes == 2000 && isfinite(rt.best_fitness), 'tier D=%d failed', D);
end

fprintf('test_dt_gsk_smoke: PASS\n');
end
