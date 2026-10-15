#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2011 {

/// Creates a CEC2011 real-world benchmark problem.
///
/// Ported from the CEC2011 real-world MATLAB package
/// (define_boundaries.m, Calc_Fitx_2011.m, bench_func.m and dependent
/// objective files) into standalone C++. Problem dimensions and bounds
/// vary per problem and are fixed by the suite. Former .mat data
/// dependencies are converted into plain text assets in @p data_root.
///
/// Known reference quirks that are preserved and documented in
/// docs/reference/porting_notes.md include the reference NaN-to-zero fitness rule.
/// Most problems have no published optimum; optimum() returns NaN for
/// those and error reporting must fall back to raw objectives.
///
/// @param function_id  1..22 in the GSK reference numbering.
/// @param data_root    Directory holding the converted CEC2011 data assets.
/// @throws std::invalid_argument for unsupported function ids.
/// @throws std::runtime_error when a required data asset is missing/bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               const std::filesystem::path& data_root);

/// Function ids exposed by the suite (1..22).
const std::vector<int>& supported_functions();

/// Native dimension of @p function_id (fixed per problem).
int native_dimension(int function_id);

/// Evaluation budget used by the GSK CEC2011 reference drivers (150000).
inline constexpr long long reference_budget = 150000;

} // namespace gskcec::cec2011
