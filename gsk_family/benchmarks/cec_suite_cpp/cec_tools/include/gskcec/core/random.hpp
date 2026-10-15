#pragma once

#include "gskcec/core/types.hpp"

#include <random>
#include <stdexcept>
#include <string>

namespace gskcec {

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

// C++ mirror of MATLAB get_cec_seed.m for any C++-side diagnostics that need a
// CEC run seed. The seed deliberately depends only on the campaign base seed
// and the benchmark coordinates. It must not include optimizer name/index,
// suite hash, population size, max evaluations, or any other algorithm-specific
// value; those would make a cross-family comparison start from different random
// streams. MATLAB remains the optimizer execution path, but keeping this helper
// aligned prevents stale algorithm-hashed seed logic from reappearing in tools.
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
