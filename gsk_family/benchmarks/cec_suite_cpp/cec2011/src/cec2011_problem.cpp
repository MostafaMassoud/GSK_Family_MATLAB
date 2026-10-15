// CEC2011 real-world suite: public factory and dispatch.
//
// Ported from the CEC2011 real-world MATLAB package (define_boundaries.m,
// Calc_Fitx_2011.m and the files they call). The 22 problems live in three
// work-package files, cec2011_problems_a/b/c.cpp. This file sends each
// function id to its package and holds the suite metadata (ids, native
// dimensions). Ids outside 1..22 throw std::invalid_argument.
// Port plan: docs/reference/cec2011_port_plan.md.

#include "gskcec/benchmark/cec2011.hpp"

#include "cec2011_detail.hpp"

#include <array>
#include <stdexcept>
#include <string>

namespace gskcec::cec2011 {

namespace {

// Native dimension D of problems 1..22 (index = id - 1), from
// define_boundaries.m; checked against the MATLAB-exported test-data file
// cec2011_bounds.txt.
constexpr std::array<int, 22> kNativeDimensions = {
    6, 30, 1, 1, 30, 30, 20, 7, 126, 12,
    120, 240, 6, 13, 15, 40, 140, 96, 96, 96,
    26, 22};

} // namespace

const std::vector<int>& supported_functions() {
    static const std::vector<int> ids = [] {
        std::vector<int> v(22);
        for (int i = 0; i < 22; ++i) {
            v[static_cast<std::size_t>(i)] = i + 1;
        }
        return v;
    }();
    return ids;
}

int native_dimension(int function_id) {
    if (function_id < 1 || function_id > 22) {
        throw std::invalid_argument("cec2011: function id must be in 1..22, got " +
                                    std::to_string(function_id) + ".");
    }
    return kNativeDimensions[static_cast<std::size_t>(function_id - 1)];
}

std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               const std::filesystem::path& data_root) {
    if (function_id < 1 || function_id > 22) {
        throw std::invalid_argument("cec2011: function id must be in 1..22, got " +
                                    std::to_string(function_id) + ".");
    }
    if ((function_id >= 1 && function_id <= 8) || function_id == 10) {
        return detail::make_problem_wpa(function_id, data_root);
    }
    if (function_id == 9 || (function_id >= 11 && function_id <= 20)) {
        return detail::make_problem_wpb(function_id, data_root);
    }
    return detail::make_problem_wpc(function_id, data_root);
}

} // namespace gskcec::cec2011
