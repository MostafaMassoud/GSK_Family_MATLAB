#pragma once

#include "gskcec/core/types.hpp"

#include <string>
#include <vector>

namespace gskcec {

struct ConvergencePoint {
    EvaluationCount nfes = 0;
    Real best_fitness = 0.0;
    Real error = 0.0;
};

struct RunResult {
    std::string optimizer;
    std::string suite;
    int function_id = 0;
    int dimension = 0;
    int run = 0;
    Seed seed = 0;
    Vector best_solution;
    Real best_fitness = 0.0;
    Real error = 0.0;
    EvaluationCount nfes = 0;
    TerminationReason termination = TerminationReason::not_run;
    double runtime_seconds = 0.0;
    std::vector<ConvergencePoint> convergence;
};

} // namespace gskcec
