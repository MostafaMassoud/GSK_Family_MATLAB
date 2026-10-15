function matrix = default_experiment_matrix()
%DEFAULT_EXPERIMENT_MATRIX The project's default optimizer/suite pairings.
%
% Reference statement of the default experiment matrix. No runner calls this
% function: the runs are driven by configs/all_cec2017.yml,
% configs/all_cec2011.yml and configs/agsk_cec2020.yml (gsk_run /
% scripts/run_all.ps1 -Full), and the root run_all_cec*.m launchers carry
% their own optimizer lists in their CONFIG blocks. Keep this table and those
% configs in sync:
%
%   | Optimizer  | CEC2017 | CEC2011 | CEC2020 |
%   | gsk        | yes     | yes     | no      |
%   | agsk       | yes     | yes     | yes     |
%   | apgsk      | yes     | yes     | no      |
%   | atmals-gsk | yes     | yes     | no      |
%   | egsk       | yes     | yes     | no      |
%   | fdb-agsk   | yes     | yes     | no      |
%   | dt-gsk     | yes     | yes     | no      |
%
% cec2013 and cec2013lsgo are available through the CLI, configs and tests
% but are not part of the default matrix. Pairings the original reference
% sources never ran directly (e.g. fdb-agsk on CEC suites) are
% framework-level extensions, not reproductions - label results
% accordingly when reporting. dt-gsk has imported references for all five
% suites (benchmarks/cec_reference_results/<suite>/dt-gsk/) and runs the
% unified seed + threefry under every seed_policy (its reference protocol).

optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk', 'dt-gsk'};
matrix = struct('optimizer', {}, 'suite', {});
for k = 1:numel(optimizers)
    matrix(end + 1) = struct('optimizer', optimizers{k}, 'suite', 'cec2017'); %#ok<AGROW>
    matrix(end + 1) = struct('optimizer', optimizers{k}, 'suite', 'cec2011'); %#ok<AGROW>
end
matrix(end + 1) = struct('optimizer', 'agsk', 'suite', 'cec2020');
end
