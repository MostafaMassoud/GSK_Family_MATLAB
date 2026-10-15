#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F11: 20-nonseparable Shifted Schwefel's Function 1.2
/// (rotated subcomponents), D = 1000, [-32, 32].
class F11 : public Benchmarks {
public:
    explicit F11(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
