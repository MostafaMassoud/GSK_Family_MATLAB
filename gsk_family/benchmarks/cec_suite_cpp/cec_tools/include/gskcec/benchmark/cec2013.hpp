#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2013 {

/// Creates a standard CEC2013 single-objective benchmark problem.
///
/// Standalone C++ port of the CEC2013 R package (R/cec2013.R wrapper,
/// src/cec2013.c bridge, src/test_func.c functions); no R runtime needed.
/// This is the standard 28-function suite. It is separate from
/// CEC2013-LSGO; never merge the two. Search domain: [-100, 100]^D.
/// optimum() is the reference bias: -1400, ..., -100 for f1..f14 and
/// 100, ..., 1400 for f15..f28.
///
/// @param function_id  1..28.
/// @param dimension    2, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90 or 100
///                     (the dimensions the R wrapper accepts).
/// @param data_root    Directory with M_D<dim>.txt and shift_data.txt.
/// @throws std::invalid_argument for an unsupported function or dimension.
/// @throws std::runtime_error when a required data file is missing or bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root);

/// Function ids in the suite (1..28).
const std::vector<int>& supported_functions();

/// Dimensions the reference R wrapper accepts.
const std::vector<int>& supported_dimensions();

} // namespace gskcec::cec2013
