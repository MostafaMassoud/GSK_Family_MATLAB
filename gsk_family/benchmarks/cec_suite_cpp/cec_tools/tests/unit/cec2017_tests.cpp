// cec2017_tests.cpp
//
// Tests for the standalone CEC2017 port
// (benchmarks/cec_suite_cpp/cec2017/src/cec2017_problem.cpp) against
// reference values from the original MEX evaluator.
//
// Usage: cec2017_tests [project_root]   (default ".")
//   data root     = <root>/benchmarks/cec_suite_cpp/cec2017/input_data
//   expected data = <root>/benchmarks/cec_suite_cpp/cec_tools/tests/data/
//
// A plain main() like core_tests.cpp, but check() prints the failing
// message and exits 1 instead of using <cassert>.

#include "gskcec/benchmark/cec2017.hpp"
#include "gskcec/benchmark/data_loading.hpp"
#include "gskcec/core/bounds.hpp"
#include "gskcec/core/types.hpp"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>

namespace {

int g_checks = 0;

void check(bool condition, const std::string& message) {
    ++g_checks;
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        std::exit(1);
    }
}

std::string fmt(double v) {
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%.17g", v);
    return buffer;
}

}  // namespace

int main(int argc, char** argv) {
    namespace fs = std::filesystem;
    using gskcec::Vector;

    const fs::path root = (argc > 1) ? fs::path(argv[1]) : fs::path(".");
    const fs::path data_root = root / "benchmarks" / "cec_suite_cpp" / "cec2017" / "input_data";
    const fs::path tests_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";

    const std::vector<int>& functions = gskcec::cec2017::supported_functions();
    const std::vector<int>& dimensions = gskcec::cec2017::supported_dimensions();
    check(functions.size() == 30 && functions.front() == 1 && functions.back() == 30,
          "supported_functions() must be 1..30");
    check(dimensions == std::vector<int>({10, 30, 50, 100}),
          "supported_dimensions() must be {10, 30, 50, 100}");

    // ---- 1) Build every (function, dimension) problem; check metadata ----
    std::map<std::pair<int, int>, std::unique_ptr<gskcec::BenchmarkProblem>> problems;
    for (int f : functions) {
        for (int d : dimensions) {
            auto problem = gskcec::cec2017::make_problem(f, d, data_root);
            const std::string tag = "F" + std::to_string(f) + " D" + std::to_string(d);
            check(problem != nullptr, tag + ": make_problem returned null");
            check(problem->suite_name() == "cec2017", tag + ": suite_name");
            check(problem->function_id() == f, tag + ": function_id");
            check(problem->dimension() == d, tag + ": dimension");
            check(problem->optimum() == 100.0 * f, tag + ": optimum must be 100*function_id");
            const gskcec::Bounds bounds = problem->bounds();
            check(bounds.dimension() == static_cast<gskcec::Index>(d), tag + ": bounds dimension");
            bool uniform = true;
            for (gskcec::Index i = 0; i < bounds.dimension(); ++i) {
                uniform = uniform && bounds.lower()[i] == -100.0 && bounds.upper()[i] == 100.0;
            }
            check(uniform, tag + ": bounds must be uniform [-100, 100]^D");
            problems[{f, d}] = std::move(problem);
        }
    }
    std::cout << "metadata OK for 30 functions x 4 dimensions\n";

    // ---- 2) f(shift vector) == 100*f for representative basic functions ----
    // The shift vector is the global optimum for f1, f3..f8 and f10.
    // F9 (Levy) is a known quirk of the reference code: it uses
    // w = 1 + (z - 1)/4, so at z = 0 (x = shift) the value is NOT the bias.
    // The test checks the analytic quirk value instead.
    for (int f : {1, 3, 4, 5, 6, 7, 8, 10}) {
        const Vector shift =
            gskcec::load_values_file(data_root / ("shift_data_" + std::to_string(f) + ".txt"));
        for (int d : dimensions) {
            check(shift.size() >= static_cast<std::size_t>(d), "shift data too short");
            const double value =
                problems[{f, d}]->evaluate(std::span<const double>(shift.data(), d));
            check(std::fabs(value - 100.0 * f) <= 1.0e-6,
                  "F" + std::to_string(f) + " D" + std::to_string(d) +
                      " at shift vector: expected " + fmt(100.0 * f) + ", got " + fmt(value));
        }
    }
    {
        const double pi = 3.1415926535897932384626433832795029;  // reference PI
        const Vector shift = gskcec::load_values_file(data_root / "shift_data_9.txt");
        for (int d : dimensions) {
            const double value =
                problems[{9, d}]->evaluate(std::span<const double>(shift.data(), d));
            // Levy with z = 0 everywhere: w_i = 0.75 for all i.
            const double w = 0.75;
            const double term1 = std::pow(std::sin(pi * w), 2.0);
            const double per_i =
                std::pow(w - 1.0, 2.0) * (1.0 + 10.0 * std::pow(std::sin(pi * w + 1.0), 2.0));
            const double term3 =
                std::pow(w - 1.0, 2.0) * (1.0 + std::pow(std::sin(2.0 * pi * w), 2.0));
            const double expected = 900.0 + term1 + (d - 1) * per_i + term3;
            check(std::fabs(value - expected) <= 1.0e-6,
                  "F9 D" + std::to_string(d) + " at shift vector (Levy quirk): expected " +
                      fmt(expected) + ", got " + fmt(value));
        }
        std::cout << "NOTE: F9 (Levy) quirk confirmed: f(shift) != 900 by design of the "
                     "reference code; analytic quirk value matched\n";
    }
    std::cout << "shift-vector sanity OK (f1, f3..f10)\n";

    // ---- 3) Compare with every row of cec2017_expected.csv ----
    // Reference values come from the original MEX evaluator; each row must
    // satisfy |got - exp| <= 1e-10 * max(1, |exp|).
    const fs::path csv_path = tests_data / "cec2017_expected.csv";
    if (!fs::exists(csv_path)) {
        std::cout << "SKIP expected-value comparison (" << csv_path.string() << " missing)\n";
    } else {
        std::map<int, Vector> points;  // dimension -> 5 probe points, row-flattened
        for (int d : dimensions) {
            const fs::path points_path = tests_data / ("points_D" + std::to_string(d) + ".txt");
            points[d] = gskcec::load_values_file(points_path);
            check(points[d].size() == 5u * static_cast<std::size_t>(d),
                  points_path.string() + ": expected 5 rows of " + std::to_string(d) + " values");
        }

        std::ifstream in(csv_path);
        check(static_cast<bool>(in), "cannot open " + csv_path.string());
        std::string line;
        long rows = 0;
        double max_rel = 0.0;
        int max_f = 0;
        int max_d = 0;
        int max_p = 0;
        while (std::getline(in, line)) {
            if (line.empty() || line[0] == '#' || line.rfind("function", 0) == 0) {
                continue;
            }
            int f = 0;
            int d = 0;
            int pt = 0;
            double expected = 0.0;
            check(std::sscanf(line.c_str(), "%d,%d,%d,%lf", &f, &d, &pt, &expected) == 4,
                  "unparseable CSV line: " + line);
            check(points.count(d) == 1, "CSV row has unsupported dimension: " + line);
            check(pt >= 1 && static_cast<std::size_t>(pt) * d <= points[d].size(),
                  "CSV row has out-of-range point index: " + line);
            const auto it = problems.find({f, d});
            check(it != problems.end(), "CSV row has unsupported function id: " + line);
            const double* x = &points[d][static_cast<std::size_t>(pt - 1) * d];
            const double got = it->second->evaluate(std::span<const double>(x, d));
            const double rel = std::fabs(got - expected) / std::max(1.0, std::fabs(expected));
            if (rel > max_rel) {
                max_rel = rel;
                max_f = f;
                max_d = d;
                max_p = pt;
            }
            check(rel <= 1.0e-10, "F" + std::to_string(f) + " D" + std::to_string(d) + " point " +
                                      std::to_string(pt) + ": got " + fmt(got) + ", expected " +
                                      fmt(expected) + ", rel dev " + fmt(rel));
            ++rows;
        }
        check(rows == 600, "expected 600 CSV data rows, parsed " + std::to_string(rows));
        std::printf("expected-value comparison OK: %ld rows, max rel deviation %.3e (F%d D%d point %d)\n",
                    rows, max_rel, max_f, max_d, max_p);
    }

    // ---- 4) Error handling ----
    const auto throws_invalid_argument = [&data_root](int f, int d) {
        try {
            (void)gskcec::cec2017::make_problem(f, d, data_root);
        } catch (const std::invalid_argument&) {
            return true;
        } catch (...) {
            return false;
        }
        return false;
    };
    check(throws_invalid_argument(0, 10), "function 0 must throw std::invalid_argument");
    check(throws_invalid_argument(31, 10), "function 31 must throw std::invalid_argument");
    check(throws_invalid_argument(1, 7), "dimension 7 must throw std::invalid_argument");
    {
        bool threw = false;
        try {
            (void)gskcec::cec2017::make_problem(1, 10, root / "benchmarks" / "no_such_data_root");
        } catch (const std::runtime_error&) {
            threw = true;
        } catch (...) {
        }
        check(threw, "missing data root must throw std::runtime_error");
    }
    {
        bool threw = false;
        try {
            const Vector too_short(5, 0.0);
            (void)problems[{1, 10}]->evaluate(too_short);
        } catch (const std::invalid_argument&) {
            threw = true;
        } catch (...) {
        }
        check(threw, "evaluate with wrong-size vector must throw std::invalid_argument");
    }
    std::cout << "error-handling OK\n";

    std::cout << "cec2017_tests passed (" << g_checks << " checks)\n";
    return 0;
}
