#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace gskcec {

using Real = double;
using Index = std::size_t;
using EvaluationCount = std::uint64_t;
using Seed = std::uint64_t;
using Vector = std::vector<Real>;

enum class TerminationReason {
    max_evaluations,
    target_error_reached,
    invalid_configuration,
    not_run
};

inline std::string to_string(TerminationReason reason) {
    switch (reason) {
    case TerminationReason::max_evaluations:
        return "max_evaluations";
    case TerminationReason::target_error_reached:
        return "target_error_reached";
    case TerminationReason::invalid_configuration:
        return "invalid_configuration";
    case TerminationReason::not_run:
        return "not_run";
    }
    return "unknown";
}

} // namespace gskcec

