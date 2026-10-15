#pragma once

#include "gskcec/core/types.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <stdexcept>

namespace gskcec {

struct SummaryStatistics {
    Real best = 0.0;
    Real median = 0.0;
    Real mean = 0.0;
    Real worst = 0.0;
    Real sd = 0.0;
};

inline Real arithmetic_mean(const Vector& values) {
    if (values.empty()) {
        throw std::invalid_argument("Cannot compute mean of empty values.");
    }
    return std::accumulate(values.begin(), values.end(), 0.0) / static_cast<Real>(values.size());
}

inline Real median(Vector values) {
    if (values.empty()) {
        throw std::invalid_argument("Cannot compute median of empty values.");
    }
    std::sort(values.begin(), values.end());
    const Index mid = values.size() / 2;
    if (values.size() % 2 == 0) {
        return (values[mid - 1] + values[mid]) / 2.0;
    }
    return values[mid];
}

inline Real sample_standard_deviation(const Vector& values) {
    if (values.size() < 2) {
        return 0.0;
    }
    const Real m = arithmetic_mean(values);
    Real ss = 0.0;
    for (const Real v : values) {
        const Real d = v - m;
        ss += d * d;
    }
    return std::sqrt(ss / static_cast<Real>(values.size() - 1));
}

inline SummaryStatistics summarize(Vector values) {
    if (values.empty()) {
        throw std::invalid_argument("Cannot summarize empty values.");
    }
    for (const Real value : values) {
        if (!std::isfinite(value)) {
            throw std::invalid_argument("Cannot summarize non-finite value.");
        }
    }
    std::sort(values.begin(), values.end());
    SummaryStatistics out;
    out.best = values.front();
    out.worst = values.back();
    out.median = median(values);
    out.mean = arithmetic_mean(values);
    out.sd = sample_standard_deviation(values);
    return out;
}

} // namespace gskcec

