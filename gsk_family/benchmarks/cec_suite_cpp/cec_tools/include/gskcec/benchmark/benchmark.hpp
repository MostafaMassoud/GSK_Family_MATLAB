#pragma once

#include "gskcec/core/bounds.hpp"

#include <span>
#include <string>

namespace gskcec {

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

