// Tests for the CEC2013-LSGO (large-scale global optimization) suite adapter
// (gskcec::cec2013lsgo). Pass the project root as argv[1] (default "."); data
// paths are built from it, never from the current working directory.

#include "gskcec/benchmark/cec2013lsgo.hpp"
#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

int g_checks = 0;
int g_failures = 0;

void check(bool condition, const std::string& label) {
    ++g_checks;
    if (!condition) {
        ++g_failures;
        std::cout << "FAIL: " << label << "\n";
    }
}

struct ExpectedFunction {
    int id;
    int dim;
    double lower;
    double upper;
};

// Native dimensions and bounds from the reference suite code (F<id>.cpp
// constructors: minX/maxX/dimension). F9 is [-100, 100] in the reference
// code, although the technical report lists [-5, 5].
constexpr ExpectedFunction kExpected[] = {
    {1, 1000, -100.0, 100.0}, {2, 1000, -5.0, 5.0},     {3, 1000, -32.0, 32.0},
    {4, 1000, -100.0, 100.0}, {5, 1000, -5.0, 5.0},     {6, 1000, -32.0, 32.0},
    {7, 1000, -100.0, 100.0}, {8, 1000, -100.0, 100.0}, {9, 1000, -100.0, 100.0},
    {10, 1000, -5.0, 5.0},    {11, 1000, -32.0, 32.0},  {12, 1000, -100.0, 100.0},
    {13, 905, -100.0, 100.0}, {14, 905, -100.0, 100.0}, {15, 1000, -100.0, 100.0},
};

// Fixed in-bounds probe point: x_j = ((-1)^j) * min(5 + j mod 17, b) * 0.3,
// with j 0-based and b the upper bound, so |x_j| <= 0.3 * b is strictly
// inside the bounds.
std::vector<double> pattern_vector(int dimension, double upper_bound) {
    std::vector<double> x(static_cast<std::size_t>(dimension));
    for (int j = 0; j < dimension; ++j) {
        const double sign = (j % 2 == 0) ? 1.0 : -1.0;
        x[j] = sign * std::min(5.0 + static_cast<double>(j % 17), upper_bound) * 0.3;
    }
    return x;
}

} // namespace

int main(int argc, char** argv) {
    const std::filesystem::path project_root = (argc > 1) ? argv[1] : ".";
    const std::filesystem::path data_root =
        project_root / "benchmarks" / "cec_suite_cpp" / "cec2013lsgo" / "input_data";

    using gskcec::cec2013lsgo::make_problem;
    using gskcec::cec2013lsgo::native_dimension;
    using gskcec::cec2013lsgo::supported_functions;

    // --- supported_functions: exactly 1..15 ---
    {
        const std::vector<int>& ids = supported_functions();
        check(ids.size() == 15, "supported_functions returns 15 ids");
        for (int id = 1; id <= 15; ++id) {
            check(std::find(ids.begin(), ids.end(), id) != ids.end(),
                  "supported_functions contains id " + std::to_string(id));
        }
    }

    for (const ExpectedFunction& expected : kExpected) {
        const std::string tag = "f" + std::to_string(expected.id) + ": ";

        check(native_dimension(expected.id) == expected.dim, tag + "native_dimension");

        auto problem = make_problem(expected.id, data_root);

        // --- identity, dimension, bounds, optimum ---
        check(problem->suite_name() == "cec2013lsgo", tag + "suite_name");
        check(problem->function_id() == expected.id, tag + "function_id");
        check(problem->dimension() == native_dimension(expected.id),
              tag + "dimension matches native_dimension");
        check(problem->dimension() == expected.dim, tag + "dimension value");

        const gskcec::Bounds bounds = problem->bounds();
        check(static_cast<int>(bounds.dimension()) == expected.dim, tag + "bounds dimension");
        bool bounds_ok = true;
        for (gskcec::Index j = 0; j < bounds.dimension(); ++j) {
            if (bounds.lower()[j] != expected.lower || bounds.upper()[j] != expected.upper ||
                !(bounds.lower()[j] < bounds.upper()[j])) {
                bounds_ok = false;
                break;
            }
        }
        check(bounds_ok, tag + "bounds values sane");

        check(problem->optimum() == 0.0, tag + "optimum is 0");

        // --- f(xopt) == 0 (to 1e-6) where the construction guarantees it ---
        // f1..f11, f13, f15: z = x - xopt = 0 at x = xopt, and every base
        //   function (elliptic/rastrigin/ackley/schwefel/sphere, including
        //   the weighted rotated subcomponents, since R * 0 = 0) is 0 at z = 0.
        // f12 (Rosenbrock): sum(100 (z_j^2 - z_{j+1})^2 + (z_j - 1)^2) has its
        //   minimum at z = 1, so f(xopt) = D - 1. The optimum is xopt + 1, so
        //   the test checks f(xopt + 1) == 0 instead.
        // f14 (conflicting overlapping Schwefel): F14-xopt.txt holds 1000
        //   shift values for 20 subcomponents that share overlapping
        //   coordinates of the 905-dim x. They conflict by design, so no single
        //   x zeroes them all and there is no f(xopt) identity. f14 is skipped
        //   here but still gets the smoke checks below.
        if (expected.id != 14) {
            const std::filesystem::path xopt_path =
                data_root / ("F" + std::to_string(expected.id) + "-xopt.txt");
            std::vector<double> xopt = gskcec::load_values_file(
                xopt_path, static_cast<std::size_t>(expected.dim));
            if (expected.id == 12) {
                for (double& value : xopt) {
                    value += 1.0;
                }
                const double f_shifted_opt = problem->evaluate(xopt);
                check(std::abs(f_shifted_opt) <= 1.0e-6, tag + "f(xopt + 1) == 0 (Rosenbrock)");
            } else {
                const double f_xopt = problem->evaluate(xopt);
                check(std::abs(f_xopt) <= 1.0e-6,
                      tag + "f(xopt) == 0 (got " + std::to_string(f_xopt) + ")");
            }
        }

        // --- smoke test: finite values at all-zeros and the pattern vector ---
        const std::vector<double> zeros(static_cast<std::size_t>(expected.dim), 0.0);
        const double f_zeros = problem->evaluate(zeros);
        check(std::isfinite(f_zeros), tag + "f(zeros) finite");

        const std::vector<double> pattern = pattern_vector(expected.dim, expected.upper);
        const double f_pattern = problem->evaluate(pattern);
        check(std::isfinite(f_pattern), tag + "f(pattern) finite");

        // --- determinism: the same point gives the same result ---
        check(problem->evaluate(pattern) == f_pattern, tag + "deterministic evaluation");
        check(problem->evaluate(zeros) == f_zeros, tag + "deterministic evaluation (zeros)");

        std::cout << "f" << expected.id << " D=" << problem->dimension() << " ["
                  << expected.lower << "," << expected.upper << "]"
                  << " f(zeros)=" << f_zeros << " f(pattern)=" << f_pattern << "\n";
    }

    // --- error handling: bad function ids -> std::invalid_argument ---
    for (int bad_id : {0, -1, 16}) {
        const std::string tag = "bad id " + std::to_string(bad_id) + ": ";
        bool threw_invalid = false;
        try {
            (void)make_problem(bad_id, data_root);
        } catch (const std::invalid_argument&) {
            threw_invalid = true;
        } catch (...) {
        }
        check(threw_invalid, tag + "make_problem throws std::invalid_argument");

        threw_invalid = false;
        try {
            (void)native_dimension(bad_id);
        } catch (const std::invalid_argument&) {
            threw_invalid = true;
        } catch (...) {
        }
        check(threw_invalid, tag + "native_dimension throws std::invalid_argument");
    }

    // --- error handling: bad data root -> std::runtime_error ---
    {
        bool threw_runtime = false;
        try {
            (void)make_problem(1, data_root / "no_such_directory");
        } catch (const std::runtime_error&) {
            threw_runtime = true;
        } catch (...) {
        }
        check(threw_runtime, "bad data root: make_problem throws std::runtime_error");
    }

    // --- error handling: wrong evaluation dimension -> std::invalid_argument ---
    {
        auto problem = make_problem(1, data_root);
        const std::vector<double> wrong_size(10, 0.0);
        bool threw_invalid = false;
        try {
            (void)problem->evaluate(wrong_size);
        } catch (const std::invalid_argument&) {
            threw_invalid = true;
        } catch (...) {
        }
        check(threw_invalid, "wrong dimension: evaluate throws std::invalid_argument");
    }

    if (g_failures == 0) {
        std::cout << "cec2013lsgo_tests passed (" << g_checks << " checks)\n";
        return 0;
    }
    std::cout << "cec2013lsgo_tests FAILED: " << g_failures << " of " << g_checks
              << " checks failed\n";
    return 1;
}
