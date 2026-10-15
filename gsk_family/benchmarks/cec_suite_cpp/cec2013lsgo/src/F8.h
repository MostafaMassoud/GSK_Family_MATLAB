#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F8: 20-nonseparable Shifted and Rotated Elliptic Function,
/// D = 1000, [-100, 100].
class F8 : public Benchmarks {
public:
    explicit F8(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
