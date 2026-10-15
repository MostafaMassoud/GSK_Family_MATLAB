#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F14: Shifted Schwefel's Function 1.2 with Conflicting Overlapping
/// Subcomponents, D = 905 (20 groups summing to 1000, overlap 5),
/// [-100, 100].
///
/// Each subcomponent has its own shift group (F14-xopt.txt holds all 1000
/// group values in order). The groups disagree on the shared coordinates,
/// so no single x makes every subcomponent zero.
class F14 : public Benchmarks {
public:
    explicit F14(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
