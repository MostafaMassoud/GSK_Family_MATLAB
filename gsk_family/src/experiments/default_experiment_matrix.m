function matrix = default_experiment_matrix()
%DEFAULT_EXPERIMENT_MATRIX The project's default optimizer/suite pairings.
%
% Default experiment matrix used by the project run scripts:
%
%   | Optimizer  | CEC2017 | CEC2011 | CEC2020 |
%   | gsk        | yes     | yes     | no      |
%   | agsk       | yes     | yes     | yes     |
%   | apgsk      | yes     | yes     | no      |
%   | atmals-gsk | yes     | yes     | no      |
%   | egsk       | yes     | yes     | no      |
%   | fdb-agsk   | yes     | yes     | no      |
%
% cec2013 and cec2013lsgo are available through the CLI, configs and tests
% but are not part of the default matrix. Pairings the original reference
% sources never ran directly (e.g. fdb-agsk on CEC suites) are
% framework-level extensions, not reproductions - label results
% accordingly when reporting.

optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk'};
matrix = struct('optimizer', {}, 'suite', {});
for k = 1:numel(optimizers)
    matrix(end + 1) = struct('optimizer', optimizers{k}, 'suite', 'cec2017'); %#ok<AGROW>
    matrix(end + 1) = struct('optimizer', optimizers{k}, 'suite', 'cec2011'); %#ok<AGROW>
end
matrix(end + 1) = struct('optimizer', 'agsk', 'suite', 'cec2020');
end
