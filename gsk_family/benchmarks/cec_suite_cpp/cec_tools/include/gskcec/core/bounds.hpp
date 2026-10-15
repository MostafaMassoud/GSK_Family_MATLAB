#pragma once

#include "gskcec/core/types.hpp"

#include <stdexcept>
#include <string>
#include <utility>

namespace gskcec {

/// Box constraints of a problem: one [lower, upper] range per coordinate
/// (length D). The constructor throws std::invalid_argument when D == 0,
/// the lengths differ, or a lower value is above its upper value (or NaN).
class Bounds {
public:
    Bounds() = default;

    Bounds(Vector lower, Vector upper)
        : lower_(std::move(lower)), upper_(std::move(upper)) {
        if (lower_.empty()) {
            throw std::invalid_argument("Bounds dimension must be positive.");
        }
        if (lower_.size() != upper_.size()) {
            throw std::invalid_argument("Bounds lower/upper dimensions differ.");
        }
        for (Index i = 0; i < lower_.size(); ++i) {
            // lower == upper is allowed: CEC2011 problem 12 fixes unit 10
            // at Pmin == Pmax == 55, a valid zero-width range.
            if (!(lower_[i] <= upper_[i])) {
                throw std::invalid_argument("Bounds lower value must not exceed upper value at index " + std::to_string(i) + ".");
            }
        }
    }

    static Bounds uniform(Index dimension, Real lower, Real upper) {
        return Bounds(Vector(dimension, lower), Vector(dimension, upper));
    }

    Index dimension() const noexcept {
        return lower_.size();
    }

    const Vector& lower() const noexcept {
        return lower_;
    }

    const Vector& upper() const noexcept {
        return upper_;
    }

    void validate_dimension(Index dimension) const {
        if (dimension != lower_.size()) {
            throw std::invalid_argument("Expected dimension " + std::to_string(lower_.size()) +
                                        ", got " + std::to_string(dimension) + ".");
        }
    }

    void validate_vector(const Vector& x) const {
        validate_dimension(x.size());
    }

    /// Moves each out-of-range coordinate of @p candidate halfway between
    /// @p parent and the bound it crossed.
    void repair_midpoint(Vector& candidate, const Vector& parent) const {
        validate_vector(candidate);
        validate_vector(parent);
        for (Index j = 0; j < candidate.size(); ++j) {
            if (candidate[j] < lower_[j]) {
                candidate[j] = (parent[j] + lower_[j]) / 2.0;
            } else if (candidate[j] > upper_[j]) {
                candidate[j] = (parent[j] + upper_[j]) / 2.0;
            }
        }
    }

private:
    Vector lower_;
    Vector upper_;
};

} // namespace gskcec
