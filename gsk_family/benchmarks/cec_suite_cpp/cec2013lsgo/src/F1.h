#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F1: Shifted Elliptic Function (fully separable), D = 1000, [-100, 100].
class F1 : public Benchmarks {
public:
    explicit F1(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
