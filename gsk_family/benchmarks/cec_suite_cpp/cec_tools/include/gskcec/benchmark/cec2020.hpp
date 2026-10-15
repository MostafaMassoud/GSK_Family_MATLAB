#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2020 {

/// Creates a CEC2020 single-objective benchmark problem.
///
/// Ported from the CEC2020 competition cec20_func.cpp MEX evaluator into
/// standalone C++. The suite
/// exposes 10 public function ids that map internally to
/// {1, 2, 3, 7, 4, 16, 6, 22, 24, 25}; that mapping is preserved. Search
/// domain is [-100, 100]^D. The optimum values follow the AGSK reference
/// vector {100, 1100, 700, 1900, 1700, 1600, 2100, 2200, 2400, 2500}.
///
/// @param function_id  Public function id 1..10.
/// @param dimension    5, 10, 15 or 20 (10 only for several functions,
///                     matching reference data availability).
/// @param data_root    Directory holding the CEC2020 input_data files.
/// @throws std::invalid_argument for unsupported function/dimension.
/// @throws std::runtime_error when a required data file is missing/bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Public function ids exposed by the suite (1..10).
const std::vector<int>& supported_functions();

/// Dimensions used by the AGSK/APGSK CEC2020 reference protocol.
const std::vector<int>& supported_dimensions();

/// Evaluation budget per dimension from the AGSK CEC2020 reference
/// protocol (D=5: 50k, D=10: 1M, D=15: 3M, D=20: 10M).
/// @throws std::invalid_argument for unsupported dimensions.
long long budget_for_dimension(int dimension);

} // namespace gskcec::cec2020
