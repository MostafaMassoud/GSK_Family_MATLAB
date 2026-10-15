#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F10: 20-nonseparable Shifted and Rotated Ackley's Function,
/// D = 1000, [-32, 32].
class F10 : public Benchmarks {
public:
    explicit F10(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
