#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2011 {

/// Creates a CEC2011 real-world benchmark problem.
///
/// Standalone C++ port of the CEC2011 MATLAB package (define_boundaries.m,
/// Calc_Fitx_2011.m, bench_func.m and the objective files they call).
/// Each problem has its own fixed dimension and bounds. The original .mat
/// data is stored as plain text files in @p data_root.
///
/// Reference quirks are kept on purpose, including the rule that a NaN
/// fitness becomes 0 (see docs/reference/porting_notes.md). optimum()
/// returns NaN for every problem (most have no published optimum), so
/// results use raw objective values instead of errors.
///
/// @param function_id  1..22, numbered as in the GSK reference code.
/// @param data_root    Directory with the converted CEC2011 data files.
/// @throws std::invalid_argument for unsupported function ids.
/// @throws std::runtime_error when a required data file is missing or bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               const std::filesystem::path& data_root);

/// Function ids in the suite (1..22).
const std::vector<int>& supported_functions();

/// Fixed dimension of problem @p function_id.
int native_dimension(int function_id);

/// Evaluation budget (max_nfes) of the GSK CEC2011 reference drivers.
inline constexpr long long reference_budget = 150000;

} // namespace gskcec::cec2011
