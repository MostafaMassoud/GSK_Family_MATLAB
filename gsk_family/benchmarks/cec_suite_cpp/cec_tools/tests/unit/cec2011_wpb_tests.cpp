// cec2011_wpb_tests.cpp -- tests for CEC2011 work package B: problems 9
// and 11-20 (benchmarks/cec_suite_cpp/cec2011/src/cec2011_problems_b.cpp).
//
// Reference values come from the MATLAB code itself:
//   1. Bounds: tests/data/cec2011_bounds.txt, exported by MATLAB from
//      define_boundaries.m. The C++ bounds must match bit for bit, including
//      problem 9, whose bounds are computed from the EBE data.
//   2. Probes: tests/data/cec2011_points_F<fn>.txt holds 3 probe rows
//      (mid, q1, q3 of the native bounds); tests/data/cec2011_expected.csv
//      holds the Calc_Fitx_2011 values (with wrapper rounding and the
//      NaN -> 0 rule). Limit: relative 1e-12.
//   3. Cross-check: problems 18 and 20 must return identical values
//      (fn_HT_ELD_Case_3 weights its POZ penalty by 0).
//   4. API: a wrong evaluate() input size and ids outside the package
//      (1, 10, 21) throw std::invalid_argument.
//
// Usage: cec2011_wpb_tests [project_root]   (default ".")

#include "cec2011_detail.hpp"

#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {

int g_checks = 0;
int g_failures = 0;

void check(bool ok, const std::string& label) {
    ++g_checks;
    if (!ok) {
        ++g_failures;
        std::cout << "FAIL: " << label << "\n";
    }
}

std::string format_value(double value) {
    char buffer[64];
    std::snprintf(buffer, sizeof buffer, "%.17g", value);
    return buffer;
}

double rel_deviation(double actual, double expected) {
    const double scale = std::max({1.0, std::fabs(actual), std::fabs(expected)});
    return std::fabs(actual - expected) / scale;
}

// Work package B ids and their native dimensions (define_boundaries.m).
const std::vector<std::pair<int, int>> kPackage = {
    {9, 126}, {11, 120}, {12, 240}, {13, 6},  {14, 13}, {15, 15},
    {16, 40}, {17, 140}, {18, 96},  {19, 96}, {20, 96}};

struct BoundsRow {
    std::vector<double> lower;
    std::vector<double> upper;
};

// cec2011_bounds.txt: '#' comment lines, then for each problem a "fn n"
// line, one lower-bound row and one upper-bound row.
std::map<int, BoundsRow> load_bounds_table(const std::filesystem::path& path) {
    std::ifstream in(path);
    check(static_cast<bool>(in), "bounds file readable: " + path.string());
    std::vector<double> tokens;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line[0] == '#') {
            continue;
        }
        std::istringstream row(line);
        double value = 0.0;
        while (row >> value) {
            tokens.push_back(value);
        }
    }
    std::map<int, BoundsRow> table;
    std::size_t pos = 0;
    while (pos + 2 <= tokens.size()) {
        const int fn = static_cast<int>(tokens[pos]);
        const auto n = static_cast<std::size_t>(tokens[pos + 1]);
        pos += 2;
        if (pos + 2 * n > tokens.size()) {
            break;
        }
        BoundsRow row;
        row.lower.assign(tokens.begin() + static_cast<std::ptrdiff_t>(pos),
                         tokens.begin() + static_cast<std::ptrdiff_t>(pos + n));
        row.upper.assign(tokens.begin() + static_cast<std::ptrdiff_t>(pos + n),
                         tokens.begin() + static_cast<std::ptrdiff_t>(pos + 2 * n));
        pos += 2 * n;
        table.emplace(fn, std::move(row));
    }
    check(table.size() == 22, "bounds table lists all 22 problems");
    return table;
}

// cec2011_expected.csv: '#' comments, "function,probe,f" header, data rows.
std::map<std::pair<int, int>, double> load_expected(const std::filesystem::path& path) {
    std::ifstream in(path);
    check(static_cast<bool>(in), "expected CSV readable: " + path.string());
    std::map<std::pair<int, int>, double> expected;
    std::string line;
    while (std::getline(in, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
            line.pop_back();
        }
        if (line.empty() || line[0] == '#' || line.rfind("function,", 0) == 0) {
            continue;
        }
        int fn = 0;
        int probe = 0;
        double f = 0.0;
        if (std::sscanf(line.c_str(), "%d,%d,%lf", &fn, &probe, &f) == 3) {
            expected[{fn, probe}] = f;
        }
    }
    check(expected.size() == 66, "expected CSV holds 22 functions x 3 probes");
    return expected;
}

// cec2011_points_F<fn>.txt: 3 rows of <dim> values (mid, q1, q3).
std::vector<std::vector<double>> load_probes(const std::filesystem::path& path, int dim) {
    const gskcec::Vector values = gskcec::load_values_file(path);
    const auto n = static_cast<std::size_t>(dim);
    check(values.size() == 3 * n, "probe file " + path.string() + " holds 3 rows of " +
                                      std::to_string(dim) + " values");
    std::vector<std::vector<double>> probes;
    if (values.size() < 3 * n) {
        return probes;
    }
    for (std::size_t r = 0; r < 3; ++r) {
        probes.emplace_back(values.begin() + static_cast<std::ptrdiff_t>(r * n),
                            values.begin() + static_cast<std::ptrdiff_t>((r + 1) * n));
    }
    return probes;
}

} // namespace

int main(int argc, char** argv) {
    const std::filesystem::path root = argc > 1 ? argv[1] : ".";
    const std::filesystem::path data_root =
        root / "benchmarks" / "cec_suite_cpp" / "cec2011" / "input_data";
    const std::filesystem::path tests_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";

    const std::map<int, BoundsRow> bounds_table =
        load_bounds_table(tests_data / "cec2011_bounds.txt");
    const std::map<std::pair<int, int>, double> expected =
        load_expected(tests_data / "cec2011_expected.csv");

    // ---- Metadata, exact bounds and reference probes per problem ----
    std::map<int, double> max_rel_dev;
    std::map<int, std::vector<double>> probe_values; // for the P18==P20 check

    for (const auto& [fn, dim] : kPackage) {
        const std::string tag = "f" + std::to_string(fn);
        const auto problem = gskcec::cec2011::detail::make_problem_wpb(fn, data_root);

        check(problem->suite_name() == "cec2011", tag + " suite_name() == cec2011");
        check(problem->function_id() == fn, tag + " function_id()");
        check(problem->dimension() == dim,
              tag + " dimension() == " + std::to_string(dim) + " (got " +
                  std::to_string(problem->dimension()) + ")");
        check(std::isnan(problem->optimum()), tag + " optimum() is quiet NaN");

        // Bounds must match the MATLAB export bit for bit, including
        // problem 9 (bounds computed from the EBE input data) and
        // problem 12's zero-width unit-10 range (Pmin == Pmax == 55).
        const auto bounds_it = bounds_table.find(fn);
        check(bounds_it != bounds_table.end(), tag + " present in bounds table");
        if (bounds_it != bounds_table.end()) {
            const gskcec::Bounds bounds = problem->bounds();
            const BoundsRow& want = bounds_it->second;
            check(bounds.dimension() == static_cast<std::size_t>(dim),
                  tag + " bounds dimension");
            bool lower_ok = want.lower.size() == bounds.dimension();
            bool upper_ok = want.upper.size() == bounds.dimension();
            for (std::size_t i = 0; i < bounds.dimension() && (lower_ok || upper_ok); ++i) {
                lower_ok = lower_ok && bounds.lower()[i] == want.lower[i];
                upper_ok = upper_ok && bounds.upper()[i] == want.upper[i];
            }
            check(lower_ok, tag + " lower bounds match define_boundaries exactly");
            check(upper_ok, tag + " upper bounds match define_boundaries exactly");
        }

        // Probes vs MATLAB Calc_Fitx_2011 values, relative tolerance 1e-12.
        const auto probes =
            load_probes(tests_data / ("cec2011_points_F" + std::to_string(fn) + ".txt"), dim);
        double worst = 0.0;
        for (std::size_t p = 0; p < probes.size(); ++p) {
            const double got = problem->evaluate(probes[p]);
            probe_values[fn].push_back(got);
            const auto expected_it = expected.find({fn, static_cast<int>(p) + 1});
            check(expected_it != expected.end(),
                  tag + " probe " + std::to_string(p + 1) + " has a reference value");
            if (expected_it == expected.end()) {
                continue;
            }
            const double want = expected_it->second;
            const double dev = rel_deviation(got, want);
            worst = std::max(worst, dev);
            check(dev <= 1e-12, tag + " probe " + std::to_string(p + 1) +
                                    " matches MATLAB at 1e-12 relative (got " +
                                    format_value(got) + ", expected " + format_value(want) +
                                    ", rel dev " + format_value(dev) + ")");
        }
        max_rel_dev[fn] = worst;
    }

    // ---- P18 == P20 exactly (case 3 weights its POZ penalty by 0) ----
    {
        const auto& f18 = probe_values[18];
        const auto& f20 = probe_values[20];
        check(f18.size() == 3 && f20.size() == 3, "P18/P20 probe values collected");
        for (std::size_t p = 0; p < std::min(f18.size(), f20.size()); ++p) {
            check(f18[p] == f20[p], "P18 probe " + std::to_string(p + 1) +
                                        " == P20 probe value exactly (" + format_value(f18[p]) +
                                        " vs " + format_value(f20[p]) + ")");
        }
    }

    // ---- Error handling ----
    {
        const auto problem = gskcec::cec2011::detail::make_problem_wpb(13, data_root);
        bool size_threw = false;
        try {
            const std::vector<double> wrong(7, 100.0);
            problem->evaluate(wrong);
        } catch (const std::invalid_argument&) {
            size_threw = true;
        } catch (...) {
        }
        check(size_threw, "evaluate() with wrong-size vector throws std::invalid_argument");

        for (const int outside : {1, 10, 21}) {
            bool threw = false;
            try {
                gskcec::cec2011::detail::make_problem_wpb(outside, data_root);
            } catch (const std::invalid_argument&) {
                threw = true;
            } catch (...) {
            }
            check(threw, "make_problem_wpb(" + std::to_string(outside) +
                             ") throws std::invalid_argument (outside work package B)");
        }
    }

    // ---- Report ----
    std::cout << "max relative deviation vs MATLAB per problem:\n";
    for (const auto& [fn, dev] : max_rel_dev) {
        std::cout << "  f" << fn << ": " << format_value(dev) << "\n";
    }
    std::cout << (g_failures == 0 ? "cec2011_wpb_tests passed" : "cec2011_wpb_tests FAILED")
              << " (" << (g_checks - g_failures) << "/" << g_checks << " checks)\n";
    return g_failures == 0 ? 0 : 1;
}
