#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F6: 7-nonseparable, 1-separable Shifted and Rotated Ackley's Function,
/// D = 1000, [-32, 32].
class F6 : public Benchmarks {
public:
    explicit F6(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
