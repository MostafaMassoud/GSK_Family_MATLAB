#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F7: 7-nonseparable, 1-separable Shifted Schwefel's Function 1.2
/// (rotated subcomponents, separable Sphere remainder), D = 1000, [-100, 100].
class F7 : public Benchmarks {
public:
    explicit F7(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
