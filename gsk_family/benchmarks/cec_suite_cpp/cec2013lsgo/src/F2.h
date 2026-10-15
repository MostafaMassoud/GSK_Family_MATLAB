#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F2: Shifted Rastrigin's Function (fully separable), D = 1000, [-5, 5].
class F2 : public Benchmarks {
public:
    explicit F2(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
