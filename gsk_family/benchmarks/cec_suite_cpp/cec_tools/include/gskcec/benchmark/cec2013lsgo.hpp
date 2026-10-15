#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2013lsgo {

/// Creates a CEC2013 Large-Scale Global Optimization (CEC2013-LSGO) problem.
///
/// Adapted from the CEC2013-LSGO reference C++ source (Benchmarks.cpp,
/// F1.cpp..F15.cpp); the package's language-binding code is left out.
/// Data files (F<id>-xopt.txt, F<id>-p.txt, F<id>-s.txt, F<id>-w.txt,
/// F<id>-R25/R50/R100.txt) load from @p data_root, not from the original
/// relative "cdatafiles" folder. This suite is separate from the standard
/// CEC2013 suite; never merge the two. Dimension follows the reference
/// protocol: 1000 for f1..f12 and f15, 905 for the overlapping f13/f14.
/// optimum() is 0 for every function.
///
/// @param function_id  1..15. The dimension is fixed by the suite.
/// @param data_root    Directory with the cdatafiles content.
/// @throws std::invalid_argument for unsupported function ids.
/// @throws std::runtime_error when a required data file is missing or bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               const std::filesystem::path& data_root);

/// Function ids in the suite (1..15).
const std::vector<int>& supported_functions();

/// Fixed dimension of @p function_id under the reference protocol.
int native_dimension(int function_id);

} // namespace gskcec::cec2013lsgo
