#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>
#include <string>
#include <vector>

namespace gskcec {

/// Experiment configuration parsed from the project's flat YAML-subset
/// config files under configs/.
///
/// Supported syntax: `key: value` lines, `[a, b, c]` inline lists, the
/// literal `all` for functions/dimensions (meaning suite defaults), and
/// `#` comments. Unknown keys are rejected with the offending line number
/// so typos cannot silently change an experiment.
struct ExperimentConfig {
    std::vector<std::string> optimizers;
    std::string suite;
    std::vector<int> functions;   ///< Empty = all functions of the suite.
    std::vector<int> dimensions;  ///< Empty = suite default/native dimensions.
    int runs = 1;
    Seed seed = 20240620;                    ///< Shared default base_seed for MATLAB CEC runs.
    std::string seed_policy = "reference";   ///< MATLAB seed_policy passed to run_experiment.
    std::string rand_generator = "threefry"; ///< MATLAB rand_generator passed to run_experiment.
    long long max_evaluations = 0; ///< 0 = suite default budget policy.
    std::string output_root;       ///< Empty = derived by the caller.
    std::string data_root;         ///< Empty = default_data_root(suite).
    std::string reference_root;    ///< Empty = benchmarks/cec_reference_results.
    bool overwrite = false;
    /// Execution is sequential in this version; `parallel: false` is
    /// accepted for forward compatibility and `parallel: true` is
    /// rejected explicitly (never silently ignored).
    bool parallel = false;
    std::filesystem::path source_path;
};

/// Parses @p path strictly.
/// @throws std::runtime_error naming the file/line on any problem.
ExperimentConfig load_experiment_config(const std::filesystem::path& path);

bool is_valid_seed_policy(const std::string& value);
bool is_valid_rand_generator(const std::string& value);

} // namespace gskcec
