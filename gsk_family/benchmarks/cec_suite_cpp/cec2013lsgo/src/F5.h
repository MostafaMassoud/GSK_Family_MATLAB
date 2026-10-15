#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F5: 7-nonseparable, 1-separable Shifted and Rotated Rastrigin's Function,
/// D = 1000, [-5, 5].
class F5 : public Benchmarks {
public:
    explicit F5(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
