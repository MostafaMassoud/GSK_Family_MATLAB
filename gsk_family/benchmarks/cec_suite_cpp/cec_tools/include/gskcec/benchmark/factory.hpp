#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gskcec {

/// Fixed description of one CEC suite in the factory.
struct SuiteInfo {
    std::string name;
    std::vector<int> functions;
    std::vector<int> dimensions; ///< Empty when dimensions are fixed per function (cec2011, cec2013lsgo).
};

/// Names of all suites in the factory, in alphabetical order.
std::vector<std::string> list_suites();

/// Description of @p suite.
/// @throws std::invalid_argument for unknown suite names.
SuiteInfo suite_info(const std::string& suite);

/// Creates a benchmark problem for @p suite.
///
/// For suites where each function has a fixed dimension (cec2011,
/// cec2013lsgo), pass @p dimension 0 (meaning "use the fixed dimension")
/// or that exact value; any other value is rejected.
///
/// @throws std::invalid_argument for unknown suites or unsupported
///         function/dimension combinations.
/// @throws std::runtime_error when a required data file is missing or bad.
std::unique_ptr<BenchmarkProblem> make_problem(const std::string& suite,
                                               int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Standard input-data folder for @p suite:
/// <project_root>/benchmarks/cec_suite_cpp/<suite>/input_data.
/// @throws std::invalid_argument for unknown suite names.
std::filesystem::path default_data_root(const std::string& suite,
                                        const std::filesystem::path& project_root);

} // namespace gskcec
