#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>
#include <string>
#include <vector>

namespace gskcec {

/// Experiment settings read from a flat YAML-subset config file under
/// configs/.
///
/// Supported syntax: `key: value` lines, `[a, b, c]` inline lists, `all`
/// for functions/dimensions (use the suite defaults) and `#` comments; a
/// leading UTF-8 BOM is allowed. Unknown keys, an empty list (`[]`; use
/// `all`) and the unsupported `data_root` key are rejected with the line
/// number, so a typo cannot silently change an experiment.
struct ExperimentConfig {
    std::vector<std::string> optimizers;
    std::string suite;
    std::vector<int> functions;   ///< Empty = all functions of the suite.
    std::vector<int> dimensions;  ///< Empty = suite default/native dimensions.
    int runs = 1;
    Seed seed = 20240620;                    ///< MATLAB base_seed; run_experiment.m default. [0, 2^53].
    std::string seed_policy = "reference";   ///< seed_policy passed to MATLAB run_experiment.
    std::string rand_generator = "threefry"; ///< rand_generator passed to MATLAB run_experiment.
    long long max_evaluations = 0; ///< 0 = suite default budget.
    /// Initial population size for every optimizer (run_experiment 'np_init');
    /// 0 = each optimizer's default (100; 5*D for dt-gsk), else >= 12.
    int np_init = 0;
    /// Final population size of agsk, apgsk, fdb-agsk and dt-gsk
    /// (run_experiment 'min_pop_size'); 0 = each one's default, else >= 11.
    int min_pop_size = 0;
    std::string output_root;       ///< Empty = chosen by the caller; relative = under --root.
    std::string reference_root;    ///< Empty = benchmarks/cec_reference_results; relative = under --root.
    bool overwrite = false;
    /// Runs are sequential. `parallel: false` is accepted (for forward
    /// compatibility); `parallel: true` is rejected with an error, never
    /// silently ignored.
    bool parallel = false;
    std::filesystem::path source_path;
};

/// Reads and strictly checks the config file @p path; optimizers and suite
/// are required.
/// @throws std::runtime_error naming the file (and line, when there is one)
///         on any problem.
ExperimentConfig load_experiment_config(const std::filesystem::path& path);

/// True for reference, native, unified or derived.
bool is_valid_seed_policy(const std::string& value);
/// True for threefry, twister, seed or state.
bool is_valid_rand_generator(const std::string& value);
/// True for 0 (default) or an np_init the whole family accepts (>= 12).
bool is_valid_np_init(long long value);
/// True for 0 (default) or a min_pop_size the whole family accepts (>= 11).
bool is_valid_min_pop_size(long long value);

/// Strict base-seed parser for the config file and `gsk_run --seed`. The
/// whole token must be a decimal integer in [0, 2^53] with no sign or
/// whitespace, so it is exact as a MATLAB double and a negative value can
/// never wrap to 2^64-k.
/// @throws std::invalid_argument naming the token otherwise.
Seed parse_seed_value(const std::string& token);

} // namespace gskcec
