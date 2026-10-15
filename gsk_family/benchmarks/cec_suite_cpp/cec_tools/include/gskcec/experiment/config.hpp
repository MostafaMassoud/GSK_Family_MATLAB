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
/// `#` comments; a leading UTF-8 BOM is tolerated. Unknown keys, an empty
/// list (`[]`; use `all`) and the unsupported `data_root` key are rejected
/// with the offending line number so typos cannot silently change an
/// experiment.
struct ExperimentConfig {
    std::vector<std::string> optimizers;
    std::string suite;
    std::vector<int> functions;   ///< Empty = all functions of the suite.
    std::vector<int> dimensions;  ///< Empty = suite default/native dimensions.
    int runs = 1;
    Seed seed = 20240620;                    ///< Shared default base_seed for MATLAB CEC runs; [0, 2^53].
    std::string seed_policy = "reference";   ///< MATLAB seed_policy passed to run_experiment.
    std::string rand_generator = "threefry"; ///< MATLAB rand_generator passed to run_experiment.
    long long max_evaluations = 0; ///< 0 = suite default budget policy.
    std::string output_root;       ///< Empty = derived by the caller; relative = under --root.
    std::string reference_root;    ///< Empty = benchmarks/cec_reference_results; relative = under --root.
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

/// Strict base-seed parser shared by the config file and `gsk_run --seed`:
/// the whole token must be a decimal integer in [0, 2^53] (no sign, no
/// whitespace), so it survives exactly as a MATLAB double and can never wrap
/// a negative value to 2^64-k.
/// @throws std::invalid_argument naming the token otherwise.
Seed parse_seed_value(const std::string& token);

} // namespace gskcec
