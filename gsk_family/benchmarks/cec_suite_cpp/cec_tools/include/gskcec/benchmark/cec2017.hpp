#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2017 {

/// Creates a CEC2017 single-objective benchmark problem.
///
/// Standalone C++ port of the official CEC2017 cec17_func.cpp MEX
/// evaluator. All input data (rotation matrices M_<f>_D<dim>.txt,
/// shift_data_<f>.txt, shuffle_data_<f>_D<dim>.txt) loads from
/// @p data_root when the problem is created. Search domain:
/// [-100, 100]^D. optimum() is 100 * function_id.
///
/// @param function_id  1..30. F2 works but is left out of default
///                     comparisons, as in the reference protocol.
/// @param dimension    10, 30, 50 or 100.
/// @param data_root    Directory with the CEC2017 input_data files.
/// @throws std::invalid_argument for an unsupported function or dimension.
/// @throws std::runtime_error when a required data file is missing or bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Function ids in the suite (1..30).
const std::vector<int>& supported_functions();

/// Dimensions with complete input data in the reference protocol.
const std::vector<int>& supported_dimensions();

/// Evaluations per dimension in the reference GSK drivers:
/// max_nfes = 10000 * D.
inline constexpr long long default_budget_per_dimension = 10000;

} // namespace gskcec::cec2017
