#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2020 {

/// Creates a CEC2020 single-objective benchmark problem.
///
/// Standalone C++ port of the official CEC2020 cec20_func.cpp MEX
/// evaluator. The 10 public function ids map to the internal ids
/// {1, 2, 3, 7, 4, 16, 6, 22, 24, 25}, exactly as in the reference.
/// Search domain: [-100, 100]^D. optimum() follows the AGSK reference
/// vector {100, 1100, 700, 1900, 1700, 1600, 2100, 2200, 2400, 2500}.
///
/// @param function_id  Public function id 1..10.
/// @param dimension    5, 10, 15 or 20. Availability follows the reference
///                     data: F1 and F8 have no D=5 or D=15 shuffle_data
///                     file, so those combinations raise std::runtime_error.
/// @param data_root    Directory with the CEC2020 input_data files.
/// @throws std::invalid_argument for an unsupported function or dimension.
/// @throws std::runtime_error when a required data file is missing or bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Public function ids in the suite (1..10).
const std::vector<int>& supported_functions();

/// Dimensions used by the AGSK/APGSK CEC2020 reference protocol.
const std::vector<int>& supported_dimensions();

/// Evaluation budget (max_nfes) for @p dimension in the AGSK CEC2020
/// reference protocol: D=5: 50k, D=10: 1M, D=15: 3M, D=20: 10M.
/// @throws std::invalid_argument for unsupported dimensions.
long long budget_for_dimension(int dimension);

} // namespace gskcec::cec2020
