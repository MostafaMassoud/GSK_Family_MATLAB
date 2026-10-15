function gskcec_require_mex(project_root, caller_name)
%GSKCEC_REQUIRE_MEX Require the project-local CEC MEX bridge before CEC runs.
%
% Usage: gskcec_require_mex(project_root, caller_name)
% caller_name labels the error message (default 'CEC experiment').
%
% The run_all_cec*.m launchers and run_experiment call this at setup, so a
% missing build\mex\gskcec_eval.<mexext> fails early with build instructions
% instead of a long run of skipped result cells. It adds build\mex to the
% front of the path and forces a real load, so a file that exists but cannot
% load (e.g. a dependent DLL missing from PATH) fails here too.
%
% Errors: gskcec:badProjectRoot, gskcec:mexMissingPrerequisite,
% gskcec:mexNotLoadable.

if nargin < 2 || isempty(caller_name)
    caller_name = 'CEC experiment';
end

if nargin < 1 || isempty(project_root)
    error('gskcec:badProjectRoot', 'project_root is required.');
end

mex_dir = fullfile(project_root, 'build', 'mex');
mex_file = fullfile(mex_dir, ['gskcec_eval.' mexext()]);

if ~isfile(mex_file)
    workspace_root = fileparts(project_root);
    error('gskcec:mexMissingPrerequisite', ...
          ['%s requires the project-local gskcec_eval MEX bridge, but it was not found:\n%s\n\n' ...
           'Build CEC/C++ prerequisites before running MATLAB CEC experiments:\n' ...
           '  cd(''%s'')\n' ...
           '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\build_mex_bridge.ps1\n\n' ...
           'For full step-by-step C++ and MEX build commands, see:\n' ...
           '  %s\n' ...
           '  %s'], ...
          caller_name, mex_file, project_root, ...
          fullfile(workspace_root, 'build.txt'), fullfile(project_root, 'build.txt'));
end

addpath(mex_dir, '-begin');
if exist('gskcec_eval', 'file') ~= 3
    error('gskcec:mexNotLoadable', ...
          ['gskcec_eval exists at %s but MATLAB did not recognize it as a MEX file. ' ...
           'Rebuild the bridge with scripts\\build_mex_bridge.ps1.'], mex_file);
end

% exist() only inspects the file. A bare call loads the MEX and raises its
% own gskcec:usage error without touching any handle; any other error means
% MATLAB could not load it.
try
    gskcec_eval();
catch err
    if ~strcmp(err.identifier, 'gskcec:usage')
        error('gskcec:mexNotLoadable', ...
              ['gskcec_eval exists at %s but MATLAB could not load it (%s: %s). ' ...
               'Rebuild the bridge with scripts\\build_mex_bridge.ps1.'], ...
              mex_file, err.identifier, err.message);
    end
end
end
