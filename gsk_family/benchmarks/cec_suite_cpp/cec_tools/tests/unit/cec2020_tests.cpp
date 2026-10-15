// Unit tests for the standalone CEC2020 port (cec2020_problem.cpp).
//
// Checks the port against every row of the MEX-generated reference values in
//   benchmarks/cec_suite_cpp/cec_tools/tests/data/cec2020_expected.csv
// (probe points from points_D<D>.txt), plus the public API: optimum vector,
// budgets, bounds, supported lists, error types, and which (function, D)
// combos the data files support.
//
// Usage: cec2020_tests [project_root]   (default ".")

#include "gskcec/benchmark/cec2020.hpp"
#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

int g_checks = 0;
int g_failures = 0;

void check(bool ok, const std::string& what) {
    ++g_checks;
    if (!ok) {
        ++g_failures;
        std::printf("FAIL: %s\n", what.c_str());
    }
}

struct ExpectedRow {
    int function = 0;
    int dimension = 0;
    int point = 0; // 1-based row in points_D<dimension>.txt
    double f = 0.0;
};

std::vector<ExpectedRow> read_expected_csv(const std::filesystem::path& csv_path) {
    std::ifstream in(csv_path);
    check(static_cast<bool>(in), "cannot open expected CSV: " + csv_path.string());
    std::vector<ExpectedRow> rows;
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }
        ExpectedRow row;
        if (std::sscanf(line.c_str(), "%d,%d,%d,%lf", &row.function, &row.dimension,
                        &row.point, &row.f) == 4) {
            rows.push_back(row);
        } else {
            check(line.rfind("function,", 0) == 0,
                  "unparseable CSV line in " + csv_path.string() + ": " + line);
        }
    }
    return rows;
}

std::string combo_name(int function, int dimension) {
    return "f" + std::to_string(function) + " D" + std::to_string(dimension);
}

} // namespace

int main(int argc, char** argv) {
    namespace fs = std::filesystem;
    using gskcec::Real;
    using gskcec::Vector;
    namespace cec2020 = gskcec::cec2020;

    const fs::path root = (argc > 1) ? fs::path(argv[1]) : fs::path(".");
    const fs::path data_root = root / "benchmarks" / "cec_suite_cpp" / "cec2020" / "input_data";
    const fs::path tests_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";

    // --- Supported function/dimension lists -------------------------------
    {
        const auto& functions = cec2020::supported_functions();
        check(functions.size() == 10, "supported_functions has 10 entries");
        for (int i = 0; i < 10; ++i) {
            check(i < static_cast<int>(functions.size()) && functions[i] == i + 1,
                  "supported_functions[" + std::to_string(i) + "] == " + std::to_string(i + 1));
        }
        const auto& dimensions = cec2020::supported_dimensions();
        const std::vector<int> expected_dims{5, 10, 15, 20};
        check(dimensions == expected_dims, "supported_dimensions == {5, 10, 15, 20}");
    }

    // --- Budgets (AGSK CEC2020 protocol) -----------------------------------
    {
        check(cec2020::budget_for_dimension(5) == 50000LL, "budget D5 == 50000");
        check(cec2020::budget_for_dimension(10) == 1000000LL, "budget D10 == 1000000");
        check(cec2020::budget_for_dimension(15) == 3000000LL, "budget D15 == 3000000");
        check(cec2020::budget_for_dimension(20) == 10000000LL, "budget D20 == 10000000");
        for (int bad : {-1, 0, 2, 30, 50, 100}) {
            bool threw = false;
            try {
                (void)cec2020::budget_for_dimension(bad);
            } catch (const std::invalid_argument&) {
                threw = true;
            }
            check(threw, "budget_for_dimension(" + std::to_string(bad) +
                             ") throws std::invalid_argument");
        }
    }

    // --- Invalid function ids / dimensions ---------------------------------
    {
        const std::vector<std::pair<int, int>> bad_args{
            {0, 10}, {-3, 10}, {11, 10}, {42, 10}, {1, 2}, {1, 7}, {1, 30}, {5, 100}};
        for (const auto& [func, dim] : bad_args) {
            bool threw = false;
            try {
                (void)cec2020::make_problem(func, dim, data_root);
            } catch (const std::invalid_argument&) {
                threw = true;
            }
            check(threw, "make_problem(" + std::to_string(func) + ", " + std::to_string(dim) +
                             ") throws std::invalid_argument");
        }
    }

    // --- Combos missing from the reference data ----------------------------
    // Internal ids 1 (public 1) and 22 (public 8) have no D5/D15 shuffle
    // files, so the reference has no values there and the constructor must
    // throw std::runtime_error naming the missing file.
    {
        const std::vector<std::pair<int, int>> missing{{1, 5}, {1, 15}, {8, 5}, {8, 15}};
        const std::vector<std::string> file_names{
            "shuffle_data_1_D5.txt", "shuffle_data_1_D15.txt",
            "shuffle_data_22_D5.txt", "shuffle_data_22_D15.txt"};
        for (std::size_t i = 0; i < missing.size(); ++i) {
            const auto [func, dim] = missing[i];
            bool threw = false;
            std::string message;
            try {
                (void)cec2020::make_problem(func, dim, data_root);
            } catch (const std::runtime_error& e) {
                threw = true;
                message = e.what();
            }
            check(threw, combo_name(func, dim) + " (missing data) throws std::runtime_error");
            check(message.find(file_names[i]) != std::string::npos,
                  combo_name(func, dim) + " error names " + file_names[i] + " (got: \"" +
                      message + "\")");
        }
    }

    // --- Metadata: suite name, ids, bounds, optimum vector -----------------
    const double agsk_optimum[10] = {100.0,  1100.0, 700.0,  1900.0, 1700.0,
                                     1600.0, 2100.0, 2200.0, 2400.0, 2500.0};
    for (int func = 1; func <= 10; ++func) {
        // D=10 has data for all 10 functions.
        std::unique_ptr<gskcec::BenchmarkProblem> problem;
        try {
            problem = cec2020::make_problem(func, 10, data_root);
        } catch (const std::exception& e) {
            check(false, "make_problem(" + std::to_string(func) + ", 10) constructs (" +
                             e.what() + ")");
            continue;
        }
        check(problem != nullptr, combo_name(func, 10) + " problem not null");
        check(problem->suite_name() == "cec2020", combo_name(func, 10) + " suite_name");
        check(problem->function_id() == func, combo_name(func, 10) + " function_id");
        check(problem->dimension() == 10, combo_name(func, 10) + " dimension");
        check(problem->optimum() == agsk_optimum[func - 1],
              combo_name(func, 10) + " optimum == " + std::to_string(agsk_optimum[func - 1]));
        const gskcec::Bounds bounds = problem->bounds();
        check(bounds.dimension() == 10, combo_name(func, 10) + " bounds dimension");
        bool bounds_ok = true;
        for (gskcec::Index j = 0; j < bounds.dimension(); ++j) {
            bounds_ok = bounds_ok && bounds.lower()[j] == -100.0 && bounds.upper()[j] == 100.0;
        }
        check(bounds_ok, combo_name(func, 10) + " bounds are [-100, 100]^D");
    }

    // --- Wrong-size evaluate throws; separate instances agree -------------
    {
        auto problem = cec2020::make_problem(1, 10, data_root);
        bool threw = false;
        try {
            const Vector short_x(5, 0.0);
            (void)problem->evaluate(short_x);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        check(threw, "evaluate with wrong-size input throws std::invalid_argument");

        // f1 at its own shift vector: z == 0 exactly, so f == bias == optimum.
        const Vector shift = gskcec::load_values_file(data_root / "shift_data_1.txt", 10);
        check(problem->evaluate(shift) == 100.0, "f1 D10 at shift vector evaluates to 100");

        auto problem_b = cec2020::make_problem(1, 10, data_root);
        const Vector x(10, 3.25);
        check(problem->evaluate(x) == problem_b->evaluate(x),
              "two instances produce bit-identical values");
    }

    // --- Reference values: every CSV row vs the original MEX ---------------
    // Each row must satisfy |got - exp| <= 1e-10 * max(1, |exp|).
    const std::vector<ExpectedRow> rows = read_expected_csv(tests_data / "cec2020_expected.csv");
    check(rows.size() == 180, "expected CSV holds 180 rows (got " +
                                  std::to_string(rows.size()) + ")");

    std::map<int, Vector> points_by_dim; // flat 5 x D probe-point tables
    std::map<std::pair<int, int>, std::unique_ptr<gskcec::BenchmarkProblem>> problems;
    double max_rel_dev = 0.0;
    ExpectedRow max_row;
    for (const ExpectedRow& row : rows) {
        auto points_it = points_by_dim.find(row.dimension);
        if (points_it == points_by_dim.end()) {
            const fs::path points_path =
                tests_data / ("points_D" + std::to_string(row.dimension) + ".txt");
            Vector flat = gskcec::load_values_file(points_path);
            check(flat.size() == 5u * static_cast<std::size_t>(row.dimension),
                  points_path.string() + " holds 5 points");
            points_it = points_by_dim.emplace(row.dimension, std::move(flat)).first;
        }

        const auto key = std::make_pair(row.function, row.dimension);
        auto problem_it = problems.find(key);
        if (problem_it == problems.end()) {
            std::unique_ptr<gskcec::BenchmarkProblem> problem;
            try {
                problem = cec2020::make_problem(row.function, row.dimension, data_root);
            } catch (const std::exception& e) {
                check(false, combo_name(row.function, row.dimension) + " constructs (" +
                                 e.what() + ")");
                continue;
            }
            problem_it = problems.emplace(key, std::move(problem)).first;
        }

        const Vector& flat = points_it->second;
        const std::size_t offset =
            static_cast<std::size_t>(row.point - 1) * static_cast<std::size_t>(row.dimension);
        const std::span<const Real> x(flat.data() + offset,
                                      static_cast<std::size_t>(row.dimension));
        const double got = problem_it->second->evaluate(x);
        const double abs_err = std::fabs(got - row.f);
        const double rel_dev = abs_err / std::max(1.0, std::fabs(row.f));
        if (rel_dev > max_rel_dev) {
            max_rel_dev = rel_dev;
            max_row = row;
        }
        if (!(abs_err <= 1.0e-10 * std::max(1.0, std::fabs(row.f)))) {
            char buffer[256];
            std::snprintf(buffer, sizeof(buffer),
                          "f%d D%d point %d: got %.17g expected %.17g (rel dev %.3e)",
                          row.function, row.dimension, row.point, got, row.f, rel_dev);
            check(false, buffer);
        } else {
            check(true, "");
        }
    }
    check(problems.size() == 36, "36 (function, dimension) combos evaluated (got " +
                                     std::to_string(problems.size()) + ")");

    std::printf("max relative deviation vs MEX ground truth: %.6e (f%d D%d point %d)\n",
                max_rel_dev, max_row.function, max_row.dimension, max_row.point);
    std::printf("cec2020_tests: %d checks, %d failures\n", g_checks, g_failures);
    if (g_failures == 0) {
        std::printf("cec2020_tests passed\n");
    }
    return g_failures == 0 ? 0 : 1;
}
