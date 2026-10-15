#pragma once

// Internal work-package factories for the CEC2011 port. Not installed as a
// public header; only cec2011_problem.cpp and the per-package translation
// units include it. See docs/reference/cec2011_port_plan.md for the port plan.

#include "gskcec/benchmark/benchmark.hpp"

#include <cmath>
#include <filesystem>
#include <memory>

namespace gskcec::cec2011::detail {

/// Reference NaN->0 fitness rule from Calc_Fitx_2011.m (lines 57-61): every
/// CEC2011 objective applies this as its FINAL step. Inf passes through
/// (isnan(Inf) is false in the reference too). Preserved deliberately even
/// though NaN usually signals an invalid evaluation; see
/// docs/reference/cec2011_port_plan.md section 3.1.
inline Real apply_reference_nan_rule(Real f) {
    return std::isnan(f) ? 0.0 : f;
}

/// Work package A: problems 1-8 and 10 (FM, Lennard-Jones, bifunctional
/// catalyst ODE, stirred-tank ODE, Tersoff Si(B)/Si(C), spread spectrum,
/// TNEP, circular antenna).
std::unique_ptr<BenchmarkProblem> make_problem_wpa(int function_id,
                                                   const std::filesystem::path& data_root);

/// Work package B: problems 9 and 11-20 (EBE transmission pricing, DED,
/// static ELD family, hydrothermal scheduling family).
std::unique_ptr<BenchmarkProblem> make_problem_wpb(int function_id,
                                                   const std::filesystem::path& data_root);

/// Work package C: problems 21-22 (Messenger full and Cassini 2 MGA-DSM
/// trajectories).
std::unique_ptr<BenchmarkProblem> make_problem_wpc(int function_id,
                                                   const std::filesystem::path& data_root);

} // namespace gskcec::cec2011::detail
