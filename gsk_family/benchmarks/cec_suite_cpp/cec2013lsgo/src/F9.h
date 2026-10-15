#pragma once

#include "Benchmarks.h"

namespace gskcec::cec2013lsgo {

/// F9: 20-nonseparable Shifted and Rotated Rastrigin's Function,
/// D = 1000, [-100, 100].
///
/// The reference code sets these bounds; the CEC2013-LSGO technical report
/// lists [-5, 5]. The reference code is followed, to match the published
/// C++ implementation.
class F9 : public Benchmarks {
public:
    explicit F9(const std::filesystem::path& dataDir);
    double compute(const double* x) override;
};

} // namespace gskcec::cec2013lsgo
