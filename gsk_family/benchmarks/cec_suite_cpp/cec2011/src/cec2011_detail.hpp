#pragma once

// Internal helpers for the CEC2011 port: the NaN rule and one problem factory
// per work package. Not installed as a public header; only
// cec2011_problem.cpp, cec2011_problems_a/b/c.cpp and their unit tests
// include it.
// Port plan: docs/reference/cec2011_port_plan.md.

#include "gskcec/benchmark/benchmark.hpp"

#include <cmath>
#include <filesystem>
#include <memory>

namespace gskcec::cec2011::detail {

/// Returns 0 if f is NaN, else f (Calc_Fitx_2011.m lines 57-61). Every CEC2011
/// objective applies this as its last step. Inf passes through, as in the
/// reference (isnan(Inf) is false). Kept on purpose so results match the
/// original code, even though NaN usually means an invalid evaluation
/// (port plan section 3.1).
inline Real apply_reference_nan_rule(Real f) {
    return std::isnan(f) ? 0.0 : f;
}

/// Work package A: creates problems 1-8 and 10 (FM, Lennard-Jones,
/// bifunctional catalyst ODE, stirred-tank ODE, Tersoff Si(B)/Si(C), spread
/// spectrum radar, TNEP, circular antenna). Other ids throw
/// std::invalid_argument.
std::unique_ptr<BenchmarkProblem> make_problem_wpa(int function_id,
                                                   const std::filesystem::path& data_root);

/// Work package B: creates problems 9 and 11-20 (EBE transmission pricing,
/// DED, static ELD family, hydrothermal scheduling family). Other ids throw
/// std::invalid_argument.
std::unique_ptr<BenchmarkProblem> make_problem_wpb(int function_id,
                                                   const std::filesystem::path& data_root);

/// Work package C: creates problems 21-22 (Messenger full and Cassini 2
/// MGA-DSM trajectories). Other ids throw std::invalid_argument.
std::unique_ptr<BenchmarkProblem> make_problem_wpc(int function_id,
                                                   const std::filesystem::path& data_root);

} // namespace gskcec::cec2011::detail
