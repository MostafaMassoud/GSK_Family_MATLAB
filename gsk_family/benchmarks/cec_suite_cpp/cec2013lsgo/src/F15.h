#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F15: Shifted Schwefel's Function 1.2 (fully non-separable),
/// D = 1000, [-100, 100].
class F15 : public Benchmarks {
public:
    explicit F15(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
