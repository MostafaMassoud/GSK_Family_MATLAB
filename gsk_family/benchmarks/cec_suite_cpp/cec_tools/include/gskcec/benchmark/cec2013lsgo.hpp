#pragma once

#include "gskcec/benchmark/benchmark.hpp"

#include <filesystem>
#include <memory>
#include <vector>

namespace gskcec::cec2013lsgo {

/// Creates a CEC2013 Large-Scale Global Optimization benchmark problem.
///
/// Adapted from the CEC2013LSGO reference C++ source
/// (Benchmarks.cpp, F1.cpp..F15.cpp). Python/Cython binding artifacts are
/// excluded. Data files (F<id>-xopt.txt, F<id>-p.txt, F<id>-s.txt,
/// F<id>-w.txt, F<id>-R25/R50/R100.txt) load from an explicit
/// @p data_root instead of the legacy relative "cdatafiles" lookup.
/// This suite is distinct from the standard CEC2013 suite; the two must
/// never be merged. Dimensions follow the reference protocol: 1000 for
/// f1..f12 and f15, 905 for the overlapping f13/f14. The optimum value
/// is 0 for every function.
///
/// @param function_id  1..15. The dimension is fixed by the suite.
/// @param data_root    Directory holding the cdatafiles content.
/// @throws std::invalid_argument for unsupported function ids.
/// @throws std::runtime_error when a required data file is missing/bad.
std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               const std::filesystem::path& data_root);

/// Function ids exposed by the suite (1..15).
const std::vector<int>& supported_functions();

/// Native dimension of @p function_id under the reference protocol.
int native_dimension(int function_id);

} // namespace gskcec::cec2013lsgo
