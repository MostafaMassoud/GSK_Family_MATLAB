// cec2011_wpa_tests.cpp -- validation harness for the CEC2011 work package A
// port (problems 1-8 and 10; benchmarks/cec_suite_cpp/cec2011/src/cec2011_problems_a.cpp).
//
// Ground truth: MATLAB R2025b evaluations of the reference code
// (Calc_Fitx_2011, including the NaN->0 rule) stored in
//   tests/data/cec2011_bounds.txt      -- define_boundaries.m bounds (0 ulp)
//   tests/data/cec2011_points_F<fn>.txt -- 3 probe rows (mid, q1, q3)
//   tests/data/cec2011_expected.csv     -- (function,probe,f) at %.17g
//
// Gates:
//   * dimension and suite metadata per problem;
//   * bounds equal the MATLAB export bit-for-bit (0 ulp);
//   * probe objectives within relative 1e-12 of MATLAB, where
//     |got - exp| <= tol * max(1, |exp|). Problems 3 and 4 run through the
//     re-implemented MATLAB ode45; they are gated at 1e-12 as well -- the
//     replica reproduces MATLAB's exact step sequence and the only residual
//     deviation is C-runtime vs MATLAB libm 1-ulp noise in exp/pow.
//   * error handling: wrong evaluate() size and out-of-package ids throw
//     std::invalid_argument.
//
// Usage: cec2011_wpa_tests [project_root]   (default ".")

#include "cec2011_detail.hpp"

#include "gskcec/benchmark/data_loading.hpp"

#include <cmath>
#include <cstdio>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
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

// Work package A ids and their native dimensions.
const std::vector<std::pair<int, int>> kProblems = {
    {1, 6}, {2, 30}, {3, 1}, {4, 1}, {5, 30}, {6, 30}, {7, 20}, {8, 7}, {10, 12}};

// Whitespace tokens of a text file with '#' comment lines removed.
std::vector<std::string> read_tokens(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cannot open " + path.string());
    }
    std::vector<std::string> tokens;
    std::string line;
    while (std::getline(in, line)) {
        const std::size_t first = line.find_first_not_of(" \t\r");
        if (first == std::string::npos || line[first] == '#') {
            continue;
        }
        std::istringstream stream(line);
        std::string token;
        while (stream >> token) {
            tokens.push_back(token);
        }
    }
    return tokens;
}

double parse_double(const std::string& token) {
    std::size_t consumed = 0;
    const double value = std::stod(token, &consumed);
    if (consumed != token.size()) {
        throw std::runtime_error("bad numeric token '" + token + "'");
    }
    return value;
}

struct BoundsRecord {
    int dimension = 0;
    std::vector<double> lower;
    std::vector<double> upper;
};

// cec2011_bounds.txt: per problem "fn n", then n lower values, n upper values.
std::map<int, BoundsRecord> load_bounds(const std::filesystem::path& path) {
    const std::vector<std::string> tokens = read_tokens(path);
    std::map<int, BoundsRecord> records;
    std::size_t pos = 0;
    while (pos < tokens.size()) {
        if (pos + 2 > tokens.size()) {
            throw std::runtime_error("truncated bounds file: " + path.string());
        }
        const int fn = std::stoi(tokens[pos]);
        const int n = std::stoi(tokens[pos + 1]);
        pos += 2;
        if (pos + 2 * static_cast<std::size_t>(n) > tokens.size()) {
            throw std::runtime_error("truncated bounds rows in " + path.string());
        }
        BoundsRecord record;
        record.dimension = n;
        for (int j = 0; j < n; ++j) {
            record.lower.push_back(parse_double(tokens[pos++]));
        }
        for (int j = 0; j < n; ++j) {
            record.upper.push_back(parse_double(tokens[pos++]));
        }
        records[fn] = std::move(record);
    }
    return records;
}

// cec2011_expected.csv: "function,probe,f" rows ('#' comments, one header).
std::map<std::pair<int, int>, double> load_expected(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cannot open " + path.string());
    }
    std::map<std::pair<int, int>, double> expected;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        const std::size_t first = line.find_first_not_of(" \t");
        if (first == std::string::npos || line[first] == '#') {
            continue;
        }
        if (line.find("function") != std::string::npos) {
            continue;  // header
        }
        std::istringstream stream(line);
        std::string fn_text, probe_text, f_text;
        if (!std::getline(stream, fn_text, ',') || !std::getline(stream, probe_text, ',') ||
            !std::getline(stream, f_text)) {
            throw std::runtime_error("bad CSV row '" + line + "' in " + path.string());
        }
        expected[{std::stoi(fn_text), std::stoi(probe_text)}] = parse_double(f_text);
    }
    return expected;
}

double relative_deviation(double got, double exp) {
    return std::fabs(got - exp) / std::max(1.0, std::fabs(exp));
}

}  // namespace

int main(int argc, char** argv) {
    const std::filesystem::path root = argc > 1 ? argv[1] : ".";
    const std::filesystem::path data_root = root / "benchmarks" / "cec_suite_cpp" / "cec2011" / "input_data";
    const std::filesystem::path test_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";

    // Relative tolerance gates. Problems 3-4 (MATLAB ode45 replica) achieved
    // the same 1e-12 gate as the closed-form problems in validation runs; if
    // a future toolchain's libm perturbs the step sequence, this is the knob
    // the port plan says to document and adjust.
    const double kTolClosedForm = 1e-12;
    const double kTolOde = 1e-12;

    std::map<int, BoundsRecord> bounds_records;
    std::map<std::pair<int, int>, double> expected;
    try {
        bounds_records = load_bounds(test_data / "cec2011_bounds.txt");
        expected = load_expected(test_data / "cec2011_expected.csv");
    } catch (const std::exception& e) {
        std::cout << "FATAL: cannot load ground-truth data: " << e.what() << "\n";
        return 1;
    }

    std::cout << "CEC2011 work package A validation (problems 1-8, 10)\n";

    for (const auto& [fn, dim] : kProblems) {
        std::unique_ptr<gskcec::BenchmarkProblem> problem;
        try {
            problem = gskcec::cec2011::detail::make_problem_wpa(fn, data_root);
        } catch (const std::exception& e) {
            check(false, "f" + std::to_string(fn) + " construction: " + e.what());
            continue;
        }
        const std::string tag = "f" + std::to_string(fn);

        check(problem->suite_name() == "cec2011", tag + " suite_name");
        check(problem->function_id() == fn, tag + " function_id");
        check(problem->dimension() == dim, tag + " dimension is " + std::to_string(dim));
        check(std::isnan(problem->optimum()), tag + " optimum is NaN (no published optimum)");

        // Bounds: exact (0 ulp) match against the MATLAB export.
        const auto bounds_it = bounds_records.find(fn);
        check(bounds_it != bounds_records.end(), tag + " bounds present in cec2011_bounds.txt");
        if (bounds_it != bounds_records.end()) {
            const BoundsRecord& expected_bounds = bounds_it->second;
            const gskcec::Bounds actual = problem->bounds();
            check(expected_bounds.dimension == dim, tag + " exported bounds dimension");
            check(actual.dimension() == static_cast<gskcec::Index>(dim), tag + " bounds dimension");
            bool lower_ok = true;
            bool upper_ok = true;
            for (std::size_t j = 0; j < static_cast<std::size_t>(dim); ++j) {
                lower_ok = lower_ok && (actual.lower()[j] == expected_bounds.lower[j]);
                upper_ok = upper_ok && (actual.upper()[j] == expected_bounds.upper[j]);
            }
            check(lower_ok, tag + " lower bounds match MATLAB export to 0 ulp");
            check(upper_ok, tag + " upper bounds match MATLAB export to 0 ulp");
        }

        // Probes: 3 rows from cec2011_points_F<fn>.txt vs cec2011_expected.csv.
        const std::filesystem::path points_path =
            test_data / ("cec2011_points_F" + std::to_string(fn) + ".txt");
        gskcec::Vector points;
        try {
            points = gskcec::load_values_file(points_path, 3 * static_cast<std::size_t>(dim));
        } catch (const std::exception& e) {
            check(false, tag + " probe points: " + e.what());
            continue;
        }
        const double tol = (fn == 3 || fn == 4) ? kTolOde : kTolClosedForm;
        double max_dev = 0.0;
        for (int probe = 1; probe <= 3; ++probe) {
            const std::size_t offset = static_cast<std::size_t>(probe - 1) * static_cast<std::size_t>(dim);
            const std::span<const gskcec::Real> x(points.data() + offset, static_cast<std::size_t>(dim));
            double got = 0.0;
            try {
                got = problem->evaluate(x);
            } catch (const std::exception& e) {
                check(false, tag + " probe " + std::to_string(probe) + " evaluation threw: " + e.what());
                continue;
            }
            const auto exp_it = expected.find({fn, probe});
            check(exp_it != expected.end(), tag + " probe " + std::to_string(probe) + " has expected value");
            if (exp_it == expected.end()) {
                continue;
            }
            const double exp = exp_it->second;
            const double dev = relative_deviation(got, exp);
            if (dev > max_dev) {
                max_dev = dev;
            }
            check(dev <= tol, tag + " probe " + std::to_string(probe) + " matches MATLAB: got " +
                                  format_value(got) + ", expected " + format_value(exp) +
                                  ", rel dev " + format_value(dev) + " (tol " + format_value(tol) + ")");
        }
        std::printf("f%-2d max relative deviation over 3 probes: %.3e (gate %.0e)\n", fn, max_dev, tol);

        // Wrong evaluate() size must throw std::invalid_argument.
        bool threw_invalid = false;
        try {
            const gskcec::Vector wrong(static_cast<std::size_t>(dim) + 1, 0.5);
            (void)problem->evaluate(wrong);
        } catch (const std::invalid_argument&) {
            threw_invalid = true;
        } catch (...) {
        }
        check(threw_invalid, tag + " evaluate rejects wrong dimension with std::invalid_argument");
    }

    // Problem 8 maps the inclusive lower bound x == 0 to candidate index 1.
    // This keeps the published [0,15] bound usable for optimizers that land
    // exactly on lb; it is equivalent to any tiny positive value.
    {
        const auto p8 = gskcec::cec2011::detail::make_problem_wpa(8, data_root);
        const gskcec::Vector zeros(7, 0.0);
        const gskcec::Vector tiny_positive(7, 1.0e-12);
        const double f_zero = p8->evaluate(zeros);
        const double f_tiny = p8->evaluate(tiny_positive);
        check(std::isfinite(f_zero), "f8 evaluate at x == 0 is finite");
        check(std::abs(f_zero - f_tiny) <= 1.0e-12 * std::max(1.0, std::abs(f_tiny)),
              "f8 x == 0 maps to the first candidate index");
    }

    // Problem 3 requires c_bifunc_data.txt; a bad data root must surface as
    // std::runtime_error naming the asset.
    {
        bool threw_runtime = false;
        try {
            (void)gskcec::cec2011::detail::make_problem_wpa(3, root / "no_such_data_root");
        } catch (const std::runtime_error&) {
            threw_runtime = true;
        } catch (...) {
        }
        check(threw_runtime, "f3 with missing data root throws std::runtime_error");
    }

    // Ids outside the work package must be rejected with std::invalid_argument.
    for (const int bad_id : {0, 9, 11, 20, 23}) {
        bool threw_invalid = false;
        try {
            (void)gskcec::cec2011::detail::make_problem_wpa(bad_id, data_root);
        } catch (const std::invalid_argument&) {
            threw_invalid = true;
        } catch (...) {
        }
        check(threw_invalid, "make_problem_wpa(" + std::to_string(bad_id) +
                                 ") throws std::invalid_argument");
    }

    std::cout << (g_failures == 0 ? "PASS" : "FAIL") << ": " << (g_checks - g_failures) << "/"
              << g_checks << " checks passed\n";
    return g_failures == 0 ? 0 : 1;
}
