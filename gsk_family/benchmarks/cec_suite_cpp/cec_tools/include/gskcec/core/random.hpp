#pragma once

#include "gskcec/core/types.hpp"

#include <random>
#include <stdexcept>
#include <string>

namespace gskcec {

/// Seeded std::mt19937_64 engine with uniform real and integer draws.
/// uniform01() draws from [0, 1) and uniform_real() from [lower, upper);
/// uniform_index() includes both ends. uniform_real() and uniform_index()
/// throw std::invalid_argument if lower > upper.
class RandomEngine {
public:
    explicit RandomEngine(Seed seed)
        : seed_(seed), engine_(seed) {}

    Seed seed() const noexcept {
        return seed_;
    }

    Real uniform01() {
        return std::uniform_real_distribution<Real>(0.0, 1.0)(engine_);
    }

    Real uniform_real(Real lower, Real upper) {
        if (!(lower <= upper)) {
            throw std::invalid_argument("uniform_real lower must be <= upper.");
        }
        return std::uniform_real_distribution<Real>(lower, upper)(engine_);
    }

    Index uniform_index(Index inclusive_lower, Index inclusive_upper) {
        if (inclusive_lower > inclusive_upper) {
            throw std::invalid_argument("uniform_index lower must be <= upper.");
        }
        return std::uniform_int_distribution<Index>(inclusive_lower, inclusive_upper)(engine_);
    }

    std::mt19937_64& raw() noexcept {
        return engine_;
    }

private:
    Seed seed_;
    std::mt19937_64 engine_;
};

// Per-run CEC seed; same formula as MATLAB get_cec_seed.m (keep the two in
// sync). Result is in [1, 2147483646]. The seed depends only on the base seed
// and the (dimension, function, run) cell, never on the optimizer, suite,
// population size, max_nfes or any other algorithm setting, so every
// optimizer gets the same random stream on the same cell. MATLAB runs the
// optimizers; this copy serves C++-side tools and diagnostics.
inline Seed make_run_seed(Seed base_seed,
                          int dimension,
                          int function_id,
                          int run_id) {
    constexpr Seed modulus = 2147483646ULL;
    const Seed raw = base_seed
        + static_cast<Seed>(dimension) * 1000003ULL
        + static_cast<Seed>(function_id) * 1000033ULL
        + static_cast<Seed>(run_id) * 1000037ULL;
    return (raw % modulus) + 1ULL;
}

} // namespace gskcec
