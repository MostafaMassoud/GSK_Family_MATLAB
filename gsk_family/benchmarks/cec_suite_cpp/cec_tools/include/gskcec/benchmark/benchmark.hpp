#pragma once

#include "gskcec/core/bounds.hpp"

#include <span>
#include <string>

namespace gskcec {

/// Interface for one CEC benchmark function at a fixed dimension D.
///
/// evaluate() takes a point of length D and returns its objective value; it
/// throws std::invalid_argument for any other length. Most suites reuse
/// scratch buffers inside evaluate(), so do not share one object across
/// threads; use one per thread. optimum() is the known best value, or NaN
/// when the suite publishes none (CEC2011).
class BenchmarkProblem {
public:
    virtual ~BenchmarkProblem() = default;

    virtual std::string suite_name() const = 0;
    virtual int function_id() const = 0;
    virtual int dimension() const = 0;
    virtual Bounds bounds() const = 0;
    virtual Real optimum() const = 0;
    virtual Real evaluate(std::span<const Real> x) const = 0;
};

} // namespace gskcec

