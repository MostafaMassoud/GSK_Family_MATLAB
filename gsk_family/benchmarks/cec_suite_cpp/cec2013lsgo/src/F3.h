#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F3: Shifted Ackley's Function (fully separable), D = 1000, [-32, 32].
class F3 : public Benchmarks {
public:
    explicit F3(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
