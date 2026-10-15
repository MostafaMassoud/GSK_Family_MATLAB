// CEC2011 suite-level integration test: exercises the public dispatcher
// (gskcec::cec2011::make_problem) and the generic factory across all 22
// problems against the MATLAB-generated ground truth. The per-work-package
// tests (cec2011_wpa/wpb/wpc_tests.cpp) cover construction details; this
// one proves the assembled suite.

#include "gskcec/benchmark/cec2011.hpp"
#include "gskcec/benchmark/factory.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

namespace fs = std::filesystem;
int failures = 0;
int checks = 0;

void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        ++failures;
    }
}

std::vector<double> read_numbers(std::istream& in, std::size_t count) {
    std::vector<double> v(count);
    for (std::size_t i = 0; i < count; ++i) {
        if (!(in >> v[i])) {
            throw std::runtime_error("unexpected end of numeric data");
        }
    }
    return v;
}

struct BoundsRecord {
    int dimension = 0;
    std::vector<double> lower;
    std::vector<double> upper;
};

std::map<int, BoundsRecord> load_bounds(const fs::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cannot open " + path.string());
    }
    std::map<int, BoundsRecord> out;
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }
        std::istringstream header(line);
        int fn = 0;
        BoundsRecord rec;
        header >> fn >> rec.dimension;
        std::string lower_line;
        std::string upper_line;
        std::getline(in, lower_line);
        std::getline(in, upper_line);
        std::istringstream ls(lower_line);
        std::istringstream us(upper_line);
        rec.lower = read_numbers(ls, static_cast<std::size_t>(rec.dimension));
        rec.upper = read_numbers(us, static_cast<std::size_t>(rec.dimension));
        out[fn] = std::move(rec);
    }
    return out;
}

std::vector<std::vector<double>> load_probes(const fs::path& path, int dimension) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cannot open " + path.string());
    }
    std::vector<std::vector<double>> probes;
    for (int r = 0; r < 3; ++r) {
        probes.push_back(read_numbers(in, static_cast<std::size_t>(dimension)));
    }
    return probes;
}

std::map<std::pair<int, int>, double> load_expected(const fs::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cannot open " + path.string());
    }
    std::map<std::pair<int, int>, double> out;
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#' || line.rfind("function", 0) == 0) {
            continue;
        }
        std::istringstream ss(line);
        std::string fn_s;
        std::string probe_s;
        std::string f_s;
        std::getline(ss, fn_s, ',');
        std::getline(ss, probe_s, ',');
        std::getline(ss, f_s, ',');
        out[{std::stoi(fn_s), std::stoi(probe_s)}] = std::stod(f_s);
    }
    return out;
}

} // namespace

int main(int argc, char** argv) {
    const fs::path root = argc >= 2 ? argv[1] : ".";
    const fs::path data_root = root / "benchmarks" / "cec_suite_cpp" / "cec2011" / "input_data";
    const fs::path test_data = root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data";

    try {
        const auto bounds_ref = load_bounds(test_data / "cec2011_bounds.txt");
        const auto expected = load_expected(test_data / "cec2011_expected.csv");
        check(bounds_ref.size() == 22, "bounds export covers 22 problems");
        check(expected.size() == 66, "expected CSV has 66 rows");

        double max_rel = 0.0;
        int worst_fn = 0;
        for (int fn = 1; fn <= 22; ++fn) {
            const auto& ref = bounds_ref.at(fn);
            check(gskcec::cec2011::native_dimension(fn) == ref.dimension,
                  "native_dimension matches MATLAB export for f" + std::to_string(fn));

            // Through the generic factory with dimension 0 (native).
            const auto problem = gskcec::make_problem("cec2011", fn, 0, data_root);
            check(problem->suite_name() == "cec2011", "suite name f" + std::to_string(fn));
            check(problem->function_id() == fn, "function id f" + std::to_string(fn));
            check(problem->dimension() == ref.dimension, "dimension f" + std::to_string(fn));
            check(std::isnan(problem->optimum()), "optimum is NaN f" + std::to_string(fn));

            const auto b = problem->bounds();
            bool bounds_equal = static_cast<int>(b.dimension()) == ref.dimension;
            for (std::size_t j = 0; bounds_equal && j < b.dimension(); ++j) {
                bounds_equal = b.lower()[j] == ref.lower[j] && b.upper()[j] == ref.upper[j];
            }
            check(bounds_equal, "bounds bit-equal to MATLAB export f" + std::to_string(fn));

            const auto probes = load_probes(test_data / ("cec2011_points_F" + std::to_string(fn) + ".txt"),
                                            ref.dimension);
            for (int p = 1; p <= 3; ++p) {
                const double exp_f = expected.at({fn, p});
                const double got = problem->evaluate(probes[static_cast<std::size_t>(p - 1)]);
                const double rel = std::abs(got - exp_f) / std::max(1.0, std::abs(exp_f));
                if (rel > max_rel) {
                    max_rel = rel;
                    worst_fn = fn;
                }
                check(rel <= 1.0e-12,
                      "probe match f" + std::to_string(fn) + " p" + std::to_string(p) +
                          " (got " + std::to_string(got) + ", expected " + std::to_string(exp_f) + ")");
                check(!std::isnan(got), "NaN rule keeps values non-NaN f" + std::to_string(fn));
            }
        }
        std::cout << "max relative probe deviation: " << max_rel << " (f" << worst_fn << ")\n";

        // Dispatcher/factory error handling.
        bool threw = false;
        try {
            (void)gskcec::cec2011::make_problem(0, data_root);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        check(threw, "function id 0 throws invalid_argument");
        threw = false;
        try {
            (void)gskcec::cec2011::make_problem(23, data_root);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        check(threw, "function id 23 throws invalid_argument");
        threw = false;
        try {
            (void)gskcec::make_problem("cec2011", 1, 7, data_root);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        check(threw, "non-native dimension through factory throws invalid_argument");
    } catch (const std::exception& ex) {
        std::cerr << "FATAL: " << ex.what() << "\n";
        return 2;
    }

    if (failures == 0) {
        std::cout << "cec2011_tests passed (" << checks << " checks)\n";
        return 0;
    }
    std::cerr << failures << " failure(s) out of " << checks << " checks\n";
    return 1;
}
