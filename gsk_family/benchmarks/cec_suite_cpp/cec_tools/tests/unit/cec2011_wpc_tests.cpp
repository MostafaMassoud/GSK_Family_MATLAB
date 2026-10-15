// cec2011_wpc_tests.cpp -- validation harness for work package C of the
// CEC2011 port (cec2011_problems_c.cpp): problems 21 (Messenger full
// mission) and 22 (Cassini 2), both MGA-DSM trajectory costs sharing the
// mga_dsm.m astrodynamics core.
//
// Layers:
//   1. Metadata: suite name, ids, dimensions (26 / 22), NaN optimum.
//   2. Bounds: exact (bitwise) match against the MATLAB-exported
//      tests/data/cec2011_bounds.txt -- independently confirms the
//      dossier-flagged quirk that P22 element 9 lower bound is 400
//      (define_boundaries.m, GSK-canonical) and NOT the 800 of
//      getlimit_cassini2.m / the .mat bounds field.
//   3. Ground truth: the 3 probe vectors per problem from
//      tests/data/cec2011_points_F21.txt / _F22.txt evaluated against the
//      MATLAB R2025b reference values in tests/data/cec2011_expected.csv
//      (Calc_Fitx_2011, includes the NaN->0 rule) at RELATIVE 1e-12.
//      The achieved agreement is printed per probe; see the tolerance
//      note above kProbeTolerance.
//   4. Determinism (bit-identical repeat evaluations), wrong-size
//      argument errors, unsupported-id errors (20, 23 -> the work-package
//      factory owns only 21/22).
//
// Usage: cec2011_wpc_tests [project_root]   (default ".")

#include "cec2011_detail.hpp"

#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <span>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
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

// Probe tolerance: RELATIVE 1e-12 against the MATLAB ground truth, as
// required by the port plan; the gate is met, no relaxation was needed.
// Achieved agreement (printed as NOTE lines) is ~2e-13 worst-case on the
// MinGW UCRT toolchain: the port reproduces MATLAB's mod/dot/norm/sum
// kernels bitwise (see cec2011_problems_c.cpp), so the residual is
// elementary-function scatter (MATLAB's libm vs UCRT's differ by ~1 ulp
// per sin/cos/acos/... call) amplified through 5-6 chained swingby legs.
// If a toolchain/libm change ever pushes a probe above 1e-12, compare
// per-leg DV values against the reference before loosening this gate.
constexpr double kProbeTolerance = 1e-12;

double rel_error(double actual, double expected) {
    if (actual == expected) {
        return 0.0;
    }
    const double scale = std::max(std::fabs(actual), std::fabs(expected));
    if (scale == 0.0 || !std::isfinite(scale)) {
        return std::numeric_limits<double>::infinity();
    }
    return std::fabs(actual - expected) / scale;
}

// Bounds file: '#' comment lines, then per function "fn n" followed by a
// lower-bound row and an upper-bound row of n values each.
struct BoundsEntry {
    int dimension = 0;
    std::vector<double> lower;
    std::vector<double> upper;
};

std::map<int, BoundsEntry> load_bounds_file(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("Cannot open bounds file: " + path.string());
    }
    std::string content, line;
    while (std::getline(in, line)) {
        if (!line.empty() && line[0] == '#') {
            continue;
        }
        content += line;
        content += ' ';
    }
    std::istringstream tokens(content);
    std::map<int, BoundsEntry> table;
    int fn = 0;
    while (tokens >> fn) {
        BoundsEntry entry;
        if (!(tokens >> entry.dimension) || entry.dimension <= 0) {
            throw std::runtime_error("Malformed bounds file (dimension) at function " +
                                     std::to_string(fn) + ": " + path.string());
        }
        entry.lower.resize(static_cast<std::size_t>(entry.dimension));
        entry.upper.resize(static_cast<std::size_t>(entry.dimension));
        for (double& value : entry.lower) {
            if (!(tokens >> value)) {
                throw std::runtime_error("Malformed bounds file (lower row) at function " +
                                         std::to_string(fn) + ": " + path.string());
            }
        }
        for (double& value : entry.upper) {
            if (!(tokens >> value)) {
                throw std::runtime_error("Malformed bounds file (upper row) at function " +
                                         std::to_string(fn) + ": " + path.string());
            }
        }
        table[fn] = std::move(entry);
    }
    return table;
}

// Expected-values CSV: "function,probe,f" rows, '#' comments and header.
std::map<std::pair<int, int>, double> load_expected_csv(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("Cannot open expected-values CSV: " + path.string());
    }
    std::map<std::pair<int, int>, double> table;
    std::string line;
    while (std::getline(in, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
            line.pop_back();
        }
        if (line.empty() || line[0] == '#' || line.rfind("function,", 0) == 0) {
            continue;
        }
        int function = 0;
        int probe = 0;
        double f = 0.0;
        if (std::sscanf(line.c_str(), "%d,%d,%lf", &function, &probe, &f) == 3) {
            table[{function, probe}] = f;
        }
    }
    return table;
}

// Probe points file: 3 whitespace-separated rows of <dim> values.
std::vector<std::vector<double>> load_probe_points(const std::filesystem::path& path, int dim) {
    const gskcec::Vector values = gskcec::load_values_file(path);
    const std::size_t n = static_cast<std::size_t>(dim);
    check(values.size() == 3 * n, "probe file " + path.filename().string() + " holds 3 rows of " +
                                      std::to_string(dim) + " values");
    std::vector<std::vector<double>> points;
    if (values.size() != 3 * n) {
        return points;
    }
    for (std::size_t row = 0; row < 3; ++row) {
        points.emplace_back(values.begin() + static_cast<std::ptrdiff_t>(row * n),
                            values.begin() + static_cast<std::ptrdiff_t>((row + 1) * n));
    }
    return points;
}

bool bits_equal(double a, double b) {
    return std::memcmp(&a, &b, sizeof(double)) == 0;
}

} // namespace

int main(int argc, char** argv) {
    const std::filesystem::path root = argc > 1 ? argv[1] : ".";
    const std::filesystem::path data_root =
        root / "benchmarks" / "cec_suite_cpp" / "cec2011" / "input_data";
    const std::filesystem::path tests_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";

    try {
        /* -------------------------------------------------------- */
        /* Construction + metadata                                   */
        /* -------------------------------------------------------- */
        const auto p21 = gskcec::cec2011::detail::make_problem_wpc(21, data_root);
        const auto p22 = gskcec::cec2011::detail::make_problem_wpc(22, data_root);

        check(p21->suite_name() == "cec2011", "f21 suite_name() == cec2011");
        check(p22->suite_name() == "cec2011", "f22 suite_name() == cec2011");
        check(p21->function_id() == 21, "f21 function_id()");
        check(p22->function_id() == 22, "f22 function_id()");
        check(p21->dimension() == 26, "f21 dimension() == 26 (Messenger full)");
        check(p22->dimension() == 22, "f22 dimension() == 22 (Cassini 2)");
        check(std::isnan(p21->optimum()), "f21 optimum() is NaN (no published optimum)");
        check(std::isnan(p22->optimum()), "f22 optimum() is NaN (no published optimum)");

        /* -------------------------------------------------------- */
        /* Bounds vs MATLAB-exported cec2011_bounds.txt (exact)      */
        /* -------------------------------------------------------- */
        const auto bounds_table = load_bounds_file(tests_data / "cec2011_bounds.txt");
        for (const auto* problem : {p21.get(), p22.get()}) {
            const int fn = problem->function_id();
            const std::string tag = "f" + std::to_string(fn);
            const auto it = bounds_table.find(fn);
            check(it != bounds_table.end(), tag + " present in cec2011_bounds.txt");
            if (it == bounds_table.end()) {
                continue;
            }
            const BoundsEntry& expected = it->second;
            check(expected.dimension == problem->dimension(),
                  tag + " bounds-file dimension matches problem dimension");
            const gskcec::Bounds bounds = problem->bounds();
            check(static_cast<int>(bounds.dimension()) == expected.dimension,
                  tag + " bounds() dimension");
            bool lower_ok = true;
            bool upper_ok = true;
            for (std::size_t j = 0; j < bounds.dimension(); ++j) {
                if (bounds.lower()[j] != expected.lower[j]) {
                    lower_ok = false;
                }
                if (bounds.upper()[j] != expected.upper[j]) {
                    upper_ok = false;
                }
            }
            check(lower_ok, tag + " lower bounds match define_boundaries export exactly");
            check(upper_ok, tag + " upper bounds match define_boundaries export exactly");
        }
        // The dossier-flagged quirk, asserted explicitly: Cassini 2
        // element 9 (1-based) lower bound is 400 per define_boundaries.m,
        // NOT the 800 of getlimit_cassini2.m / the .mat bounds field.
        check(p22->bounds().lower()[8] == 400.0,
              "f22 element 9 lower bound is the GSK-canonical 400 (not GTOP's 800)");
        const auto bounds22 = bounds_table.find(22);
        if (bounds22 != bounds_table.end()) {
            check(bounds22->second.lower[8] == 400.0,
                  "bounds file independently confirms f22 element 9 lower bound 400");
        }

        /* -------------------------------------------------------- */
        /* Ground-truth probes vs MATLAB (relative 1e-12)            */
        /* -------------------------------------------------------- */
        const auto expected_csv = load_expected_csv(tests_data / "cec2011_expected.csv");
        for (const auto* problem : {p21.get(), p22.get()}) {
            const int fn = problem->function_id();
            const std::string tag = "f" + std::to_string(fn);
            const auto points = load_probe_points(
                tests_data / ("cec2011_points_F" + std::to_string(fn) + ".txt"),
                problem->dimension());
            double worst = 0.0;
            for (std::size_t p = 0; p < points.size(); ++p) {
                const auto key = std::make_pair(fn, static_cast<int>(p) + 1);
                const auto it = expected_csv.find(key);
                check(it != expected_csv.end(),
                      tag + " probe " + std::to_string(p + 1) + " present in cec2011_expected.csv");
                if (it == expected_csv.end()) {
                    continue;
                }
                const double got = problem->evaluate(points[p]);
                const double err = rel_error(got, it->second);
                worst = std::max(worst, err);
                check(err <= kProbeTolerance,
                      tag + " probe " + std::to_string(p + 1) + " matches MATLAB at rel 1e-12 (got " +
                          format_value(got) + ", expected " + format_value(it->second) +
                          ", rel err " + format_value(err) + ")");
            }
            std::cout << "NOTE: " << tag << " worst probe relative error vs MATLAB = "
                      << format_value(worst) << "\n";
        }

        /* -------------------------------------------------------- */
        /* Determinism: repeat evaluations are bit-identical         */
        /* -------------------------------------------------------- */
        for (const auto* problem : {p21.get(), p22.get()}) {
            const int fn = problem->function_id();
            const auto points = load_probe_points(
                tests_data / ("cec2011_points_F" + std::to_string(fn) + ".txt"),
                problem->dimension());
            if (!points.empty()) {
                const double first = problem->evaluate(points[0]);
                const double second = problem->evaluate(points[0]);
                check(bits_equal(first, second), "f" + std::to_string(fn) +
                                                     " repeat evaluation is bit-identical");
            }
        }

        /* -------------------------------------------------------- */
        /* Error handling                                            */
        /* -------------------------------------------------------- */
        {
            bool threw = false;
            try {
                const std::vector<double> wrong(25, 0.0);
                p21->evaluate(wrong);
            } catch (const std::invalid_argument&) {
                threw = true;
            } catch (...) {
            }
            check(threw, "f21 evaluate() with 25 values throws std::invalid_argument");
        }
        {
            bool threw = false;
            try {
                const std::vector<double> wrong(26, 0.0);
                p22->evaluate(wrong);
            } catch (const std::invalid_argument&) {
                threw = true;
            } catch (...) {
            }
            check(threw, "f22 evaluate() with 26 values throws std::invalid_argument");
        }
        for (const int bad_id : {20, 23}) {
            bool threw = false;
            try {
                gskcec::cec2011::detail::make_problem_wpc(bad_id, data_root);
            } catch (const std::invalid_argument&) {
                threw = true;
            } catch (...) {
            }
            check(threw, "make_problem_wpc(" + std::to_string(bad_id) +
                             ") throws std::invalid_argument");
        }
    } catch (const std::exception& ex) {
        check(false, std::string("unexpected exception: ") + ex.what());
    }

    std::cout << (g_failures == 0 ? "cec2011_wpc_tests passed" : "cec2011_wpc_tests FAILED")
              << " (" << (g_checks - g_failures) << "/" << g_checks << " checks)\n";
    return g_failures == 0 ? 0 : 1;
}
