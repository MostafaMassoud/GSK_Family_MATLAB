#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gskcec {

/// Static description of one CEC suite exposed by the factory.
struct SuiteInfo {
    std::string name;
    std::vector<int> functions;
    std::vector<int> dimensions; ///< Empty when dimensions are fixed per function (cec2011, cec2013lsgo).
};

/// Names of all suites known to the factory, sorted alphabetically.
std::vector<std::string> list_suites();

/// Static description of @p suite.
/// @throws std::invalid_argument for unknown suite names.
SuiteInfo suite_info(const std::string& suite);

/// Creates a benchmark problem instance.
///
/// For suites with per-function fixed dimensions (cec2011, cec2013lsgo)
/// pass @p dimension 0 to use the native dimension, or the exact native
/// dimension; any other value is rejected.
///
/// @throws std::invalid_argument for unknown suites or unsupported
///         function/dimension combinations.
/// @throws std::runtime_error when required data files are missing/bad.
std::unique_ptr<BenchmarkProblem> make_problem(const std::string& suite,
                                               int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Conventional input-data directory for @p suite below @p project_root
/// (benchmarks/cec_suite_cpp/<suite>/input_data).
std::filesystem::path default_data_root(const std::string& suite,
                                        const std::filesystem::path& project_root);

} // namespace gskcec
