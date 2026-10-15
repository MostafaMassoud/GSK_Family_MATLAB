#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2013 {

/// Creates a standard CEC2013 single-objective benchmark problem.
///
/// Converted from the CEC2013 R package
/// (R/cec2013.R wrapper, src/cec2013.c R bridge, src/test_func.c
/// implementation) into standalone C++ with no R runtime dependency.
/// This is the standard 28-function suite; it is distinct from
/// CEC2013LSGO and the two must never be merged. Search domain is
/// [-100, 100]^D. Optimum values are the reference biases
/// (-1400, ..., -100 for f1..f14 and 100, ..., 1400 for f15..f28).
///
/// @param function_id  1..28.
/// @param dimension    One of 2, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90,
///                     100 (the dimensions accepted by the R wrapper).
/// @param data_root    Directory holding M_D<dim>.txt and shift_data.txt.
/// @throws std::invalid_argument for unsupported function/dimension.
/// @throws std::runtime_error when a required data file is missing/bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Function ids exposed by the suite (1..28).
const std::vector<int>& supported_functions();

/// Dimensions accepted by the reference R wrapper.
const std::vector<int>& supported_dimensions();

} // namespace gskcec::cec2013
