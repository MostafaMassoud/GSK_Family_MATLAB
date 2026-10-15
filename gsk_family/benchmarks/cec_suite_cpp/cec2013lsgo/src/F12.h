#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F12: Shifted Rosenbrock's Function (overlapping chain structure),
/// D = 1000, [-100, 100].
///
/// The optimum is at x = xopt + 1 (Rosenbrock is minimal at z = 1), so
/// f(xopt) = D - 1, not 0, and f(xopt + 1) = 0.
class F12 : public Benchmarks {
public:
    explicit F12(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
