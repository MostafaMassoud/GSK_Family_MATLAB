#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F13: Shifted Schwefel's Function 1.2 with Conforming Overlapping
/// Subcomponents, D = 905 (20 groups summing to 1000, overlap 5),
/// [-100, 100].
class F13 : public Benchmarks {
public:
    explicit F13(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
