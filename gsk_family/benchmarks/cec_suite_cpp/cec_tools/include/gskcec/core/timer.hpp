#pragma once

#include <chrono>

namespace gskcec {

class Stopwatch {
public:
    Stopwatch()
        : start_(std::chrono::steady_clock::now()) {}

    double elapsed_seconds() const {
        const auto now = std::chrono::steady_clock::now();
        return std::chrono::duration<double>(now - start_).count();
    }

private:
    std::chrono::steady_clock::time_point start_;
};

} // namespace gskcec

