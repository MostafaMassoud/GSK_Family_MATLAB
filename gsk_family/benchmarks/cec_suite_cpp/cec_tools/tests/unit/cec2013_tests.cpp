// cec2013_tests.cpp -- tests for the standalone C++ port of the standard
// CEC2013 suite (benchmarks/cec_suite_cpp/cec2013/src/cec2013_problem.cpp).
//
// No R installation is available, so there are no external reference
// values. The test has four parts:
//   1. Analytic check: f1 is a shifted sphere plus bias, recomputed here
//      from shift_data.txt (relative tolerance 1e-9).
//   2. Optimum at the shift: f(o) == bias for every function at every
//      supported dimension, where o is the first D values of
//      shift_data.txt (tolerance 1e-6; the suite README explains why all
//      28 functions satisfy this by construction).
//   3. Self-regression: evaluates functions 1..28 at D = 10/30/50 on the
//      5 probe points in tests/data/points_D<dim>.txt. Writes
//      tests/data/cec2013_regression.csv if it is missing, otherwise
//      compares against it (relative tolerance 1e-12). The CSV comes from
//      this port itself: it guards against regressions and is NOT an
//      external reference.
//   4. API and metadata checks; bad ids, dimensions and input sizes throw
//      std::invalid_argument, a missing data root throws std::runtime_error.
//
// Usage: cec2013_tests [project_root]   (default ".")

#include "gskcec/benchmark/cec2013.hpp"
#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <span>
#include <stdexcept>
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

bool rel_close(double actual, double expected, double tol) {
    const double scale = std::max({1.0, std::fabs(actual), std::fabs(expected)});
    return std::fabs(actual - expected) <= tol * scale;
}

double reference_bias(int function_id) {
    return function_id <= 14 ? 100.0 * function_id - 1500.0 : 100.0 * function_id - 1400.0;
}

// Loads tests/data/points_D<dim>.txt as 5 rows of <dim> values.
std::vector<std::vector<double>> load_probe_points(const std::filesystem::path& path, int dim) {
    const gskcec::Vector values = gskcec::load_values_file(path);
    std::vector<std::vector<double>> points;
    const std::size_t n = static_cast<std::size_t>(dim);
    check(values.size() == 5 * n, "probe point file " + path.string() + " holds 5 rows of " +
                                      std::to_string(dim) + " values");
    if (values.size() < 5 * n) {
        return points;
    }
    for (std::size_t r = 0; r < 5; ++r) {
        points.emplace_back(values.begin() + static_cast<std::ptrdiff_t>(r * n),
                            values.begin() + static_cast<std::ptrdiff_t>((r + 1) * n));
    }
    return points;
}

struct RegressionRow {
    int function = 0;
    int dimension = 0;
    int point = 0;
    double f = 0.0;
};

std::string format_value(double value) {
    char buffer[64];
    std::snprintf(buffer, sizeof buffer, "%.17g", value);
    return buffer;
}

} // namespace

int main(int argc, char** argv) {
    const std::filesystem::path root = argc > 1 ? argv[1] : ".";
    const std::filesystem::path data_root = root / "benchmarks" / "cec_suite_cpp" / "cec2013" / "input_data";
    const std::filesystem::path tests_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";
    const std::filesystem::path regression_csv = tests_data / "cec2013_regression.csv";

    // ---- API ----
    {
        const std::vector<int>& functions = gskcec::cec2013::supported_functions();
        check(functions.size() == 28, "supported_functions() lists 28 ids");
        bool ascending = !functions.empty() && functions.front() == 1 && functions.back() == 28;
        for (std::size_t i = 0; ascending && i < functions.size(); ++i) {
            ascending = functions[i] == static_cast<int>(i) + 1;
        }
        check(ascending, "supported_functions() is 1..28");

        const std::vector<int> expected_dims = {2, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100};
        check(gskcec::cec2013::supported_dimensions() == expected_dims,
              "supported_dimensions() matches the R wrapper whitelist");
    }

    // ---- Metadata ----
    for (int func = 1; func <= 28; ++func) {
        const auto problem = gskcec::cec2013::make_problem(func, 10, data_root);
        const std::string tag = "f" + std::to_string(func);
        check(problem->suite_name() == "cec2013", tag + " suite_name() == cec2013");
        check(problem->function_id() == func, tag + " function_id()");
        check(problem->dimension() == 10, tag + " dimension()");
        check(problem->optimum() == reference_bias(func), tag + " optimum() equals reference bias");
        const gskcec::Bounds bounds = problem->bounds();
        bool box_ok = bounds.dimension() == 10;
        for (std::size_t j = 0; box_ok && j < bounds.dimension(); ++j) {
            box_ok = bounds.lower()[j] == -100.0 && bounds.upper()[j] == 100.0;
        }
        check(box_ok, tag + " bounds are [-100,100]^D");
    }

    // ---- Invalid arguments and missing data ----
    {
        const auto expect_invalid = [&](int func, int dim, const std::string& label) {
            bool threw = false;
            try {
                gskcec::cec2013::make_problem(func, dim, data_root);
            } catch (const std::invalid_argument&) {
                threw = true;
            } catch (...) {
            }
            check(threw, label + " throws std::invalid_argument");
        };
        expect_invalid(0, 10, "function_id 0");
        expect_invalid(29, 10, "function_id 29");
        expect_invalid(-3, 10, "function_id -3");
        expect_invalid(1, 15, "dimension 15");
        expect_invalid(1, 0, "dimension 0");
        expect_invalid(1, -10, "dimension -10");

        bool missing_root_threw = false;
        try {
            gskcec::cec2013::make_problem(1, 10, root / "no_such_data_dir");
        } catch (const std::runtime_error&) {
            missing_root_threw = true;
        } catch (...) {
        }
        check(missing_root_threw, "missing data_root throws std::runtime_error");

        const auto problem = gskcec::cec2013::make_problem(1, 10, data_root);
        bool size_threw = false;
        try {
            const std::vector<double> wrong(9, 0.0);
            problem->evaluate(wrong);
        } catch (const std::invalid_argument&) {
            size_threw = true;
        } catch (...) {
        }
        check(size_threw, "evaluate() with wrong-size vector throws std::invalid_argument");
    }

    // ---- Part 1: analytic f1 (shifted sphere + bias) ----
    const gskcec::Vector shift_table = gskcec::load_values_file(data_root / "shift_data.txt");
    check(shift_table.size() >= 1000, "shift_data.txt holds at least 10*100 values");

    for (const int dim : {10, 30, 50}) {
        const auto problem = gskcec::cec2013::make_problem(1, dim, data_root);
        const std::size_t n = static_cast<std::size_t>(dim);
        const std::vector<double> shift(shift_table.begin(),
                                        shift_table.begin() + static_cast<std::ptrdiff_t>(n));

        const auto points = load_probe_points(
            tests_data / ("points_D" + std::to_string(dim) + ".txt"), dim);
        std::vector<std::vector<double>> probes = points;
        probes.push_back(shift); // the shifted optimum itself

        for (std::size_t p = 0; p < probes.size(); ++p) {
            double expected = 0.0;
            for (std::size_t j = 0; j < n; ++j) {
                const double d = probes[p][j] - shift[j];
                expected += d * d;
            }
            expected += -1400.0;
            const double got = problem->evaluate(probes[p]);
            check(rel_close(got, expected, 1e-9),
                  "f1 D" + std::to_string(dim) + " probe " + std::to_string(p + 1) +
                      " matches analytic shifted sphere (got " + format_value(got) +
                      ", expected " + format_value(expected) + ")");
        }
    }

    // ---- Part 2: optimum at the shift, every function x every D ----
    for (const int dim : gskcec::cec2013::supported_dimensions()) {
        const std::size_t n = static_cast<std::size_t>(dim);
        const std::vector<double> shift(shift_table.begin(),
                                        shift_table.begin() + static_cast<std::ptrdiff_t>(n));
        for (int func = 1; func <= 28; ++func) {
            const auto problem = gskcec::cec2013::make_problem(func, dim, data_root);
            const double value = problem->evaluate(shift);
            const double bias = problem->optimum();
            check(std::fabs(value - bias) <= 1e-6,
                  "f" + std::to_string(func) + " D" + std::to_string(dim) +
                      " optimum-at-shift |f(o) - bias| <= 1e-6 (got " + format_value(value) +
                      ", bias " + format_value(bias) + ")");
        }
    }

    // ---- Part 3: self-regression CSV (written if missing) ----
    {
        std::vector<RegressionRow> rows;
        bool all_finite = true;
        for (int func = 1; func <= 28; ++func) {
            for (const int dim : {10, 30, 50}) {
                const auto problem = gskcec::cec2013::make_problem(func, dim, data_root);
                const auto points = load_probe_points(
                    tests_data / ("points_D" + std::to_string(dim) + ".txt"), dim);
                for (std::size_t p = 0; p < points.size(); ++p) {
                    RegressionRow row;
                    row.function = func;
                    row.dimension = dim;
                    row.point = static_cast<int>(p) + 1;
                    row.f = problem->evaluate(points[p]);
                    all_finite = all_finite && std::isfinite(row.f);
                    rows.push_back(row);
                }
            }
        }
        check(rows.size() == 28u * 3u * 5u, "regression sweep covers 28 functions x 3 dims x 5 points");
        check(all_finite, "all regression values are finite");

        if (!std::filesystem::exists(regression_csv)) {
            std::ofstream out(regression_csv);
            check(static_cast<bool>(out), "regression CSV is writable: " + regression_csv.string());
            out << "# self-generated by the C++ port -- regression guard, NOT external ground truth\n";
            out << "# produced by cec2013_tests.cpp: gskcec::cec2013 evaluated at the probe points\n";
            out << "# in points_D{10,30,50}.txt; regenerate by deleting this file and re-running\n";
            out << "function,dimension,point,f\n";
            for (const RegressionRow& row : rows) {
                out << row.function << ',' << row.dimension << ',' << row.point << ','
                    << format_value(row.f) << '\n';
            }
            out.close();
            check(static_cast<bool>(out), "regression CSV written: " + regression_csv.string());
            std::cout << "NOTE: generated " << rows.size() << "-row regression baseline at "
                      << regression_csv.string() << "\n";
        } else {
            std::ifstream in(regression_csv);
            check(static_cast<bool>(in), "regression CSV is readable: " + regression_csv.string());
            std::vector<RegressionRow> expected;
            std::string line;
            while (std::getline(in, line)) {
                while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
                    line.pop_back();
                }
                if (line.empty() || line[0] == '#' || line.rfind("function,", 0) == 0) {
                    continue;
                }
                RegressionRow row;
                const int fields =
                    std::sscanf(line.c_str(), "%d,%d,%d,%lf", &row.function, &row.dimension,
                                &row.point, &row.f);
                check(fields == 4, "regression CSV row parses: '" + line + "'");
                if (fields == 4) {
                    expected.push_back(row);
                }
            }
            check(expected.size() == rows.size(),
                  "regression CSV row count " + std::to_string(expected.size()) + " matches sweep " +
                      std::to_string(rows.size()));
            const std::size_t count = std::min(expected.size(), rows.size());
            for (std::size_t r = 0; r < count; ++r) {
                const RegressionRow& want = expected[r];
                const RegressionRow& got = rows[r];
                const std::string tag = "regression f" + std::to_string(want.function) + " D" +
                                        std::to_string(want.dimension) + " p" +
                                        std::to_string(want.point);
                check(want.function == got.function && want.dimension == got.dimension &&
                          want.point == got.point,
                      tag + " key order matches");
                check(rel_close(got.f, want.f, 1e-12),
                      tag + " value matches baseline (got " + format_value(got.f) + ", baseline " +
                          format_value(want.f) + ")");
            }
        }
    }

    std::cout << (g_failures == 0 ? "cec2013_tests passed" : "cec2013_tests FAILED") << " ("
              << (g_checks - g_failures) << "/" << g_checks << " checks)\n";
    return g_failures == 0 ? 0 : 1;
}
