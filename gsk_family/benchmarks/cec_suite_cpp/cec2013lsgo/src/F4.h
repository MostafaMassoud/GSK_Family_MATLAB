#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F4: 7-nonseparable, 1-separable Shifted and Rotated Elliptic Function,
/// D = 1000, [-100, 100].
class F4 : public Benchmarks {
public:
    explicit F4(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
