#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2017 {

/// Creates a CEC2017 single-objective benchmark problem.
///
/// Ported from the CEC2017 competition cec17_func.cpp MEX evaluator into
/// standalone C++. All input
/// data (rotation matrices M_<f>_D<dim>.txt, shift_data_<f>.txt and
/// shuffle_data_<f>_D<dim>.txt) is loaded from @p data_root at
/// construction. Search domain is [-100, 100]^D, optimum value is
/// 100 * function_id.
///
/// @param function_id  1..30 (F2 is supported but excluded from default
///                     comparisons, matching the reference protocol).
/// @param dimension    10, 30, 50 or 100.
/// @param data_root    Directory holding the CEC2017 input_data files.
/// @throws std::invalid_argument for unsupported function/dimension.
/// @throws std::runtime_error when a required data file is missing/bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Function ids exposed by the suite (1..30).
const std::vector<int>& supported_functions();

/// Dimensions with complete input data in the reference protocol.
const std::vector<int>& supported_dimensions();

/// Default evaluation budget used by the reference GSK drivers.
inline constexpr long long default_budget_per_dimension = 10000;

} // namespace gskcec::cec2017
