// gsk_bench: micro-benchmark for the C++ CEC benchmark ports.
//
// Times raw evaluate() throughput on representative (suite, function,
// dimension) cells so performance work can be measured before/after with no
// guesswork. Pure timing of deterministic evaluations - it changes no state
// and reads no RNG, so results are comparable across builds (e.g. default vs
// the GSKCEC_NATIVE optimized build).
//
// Usage:
//   gsk_bench --root <project_root> [--iterations N] [--csv <out.csv>]
//             [--cell <suite> <function> <dimension>]...
//
// With no --cell, a default representative set spanning all five suites and
// the heaviest configurations is used. Dimension 0 means the suite's native
// per-function dimension (cec2011, cec2013lsgo).

#include "gskcec/benchmark/factory.hpp"
#include "gskcec/core/timer.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

namespace fs = std::filesystem;

struct Cell {
    std::string suite;
    int function_id;
    int dimension; // 0 => native
};

// Representative cells: cheap and heavy functions across every suite. The
// heavy large-scale and high-dimension cells dominate real run cost, so they
// anchor the optimization targets.
std::vector<Cell> default_cells() {
    return {
        {"cec2017", 1, 100},  {"cec2017", 11, 100}, {"cec2017", 21, 100},
        {"cec2020", 1, 20},   {"cec2020", 6, 20},
        {"cec2013", 1, 100},  {"cec2013", 15, 100},
        {"cec2013lsgo", 1, 0}, {"cec2013lsgo", 13, 0},
        {"cec2011", 9, 0},    {"cec2011", 17, 0}, {"cec2011", 21, 0},
    };
}

// A deterministic in-bounds probe; varied per evaluation index so the
// optimizer/compiler cannot fold the loop to a single call.
gskcec::Vector probe(const gskcec::Bounds& bounds, std::uint64_t k) {
    gskcec::Vector x(bounds.dimension());
    for (gskcec::Index j = 0; j < x.size(); ++j) {
        const double lo = bounds.lower()[j];
        const double hi = bounds.upper()[j];
        const double t = 0.25 + 0.5 * (static_cast<double>((j + k) % 9973) / 9972.0);
        x[j] = lo + t * (hi - lo);
    }
    return x;
}

} // namespace

int main(int argc, char** argv) {
    fs::path project_root = ".";
    long long iterations = 20000;
    fs::path csv_path;
    std::vector<Cell> cells;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&](const char* what) -> std::string {
            if (i + 1 >= argc) {
                throw std::runtime_error(std::string("missing value for ") + what);
            }
            return argv[++i];
        };
        try {
            if (a == "--root") {
                project_root = next("--root");
            } else if (a == "--iterations") {
                iterations = std::stoll(next("--iterations"));
            } else if (a == "--csv") {
                csv_path = next("--csv");
            } else if (a == "--cell") {
                Cell c;
                c.suite = next("--cell suite");
                c.function_id = std::stoi(next("--cell function"));
                c.dimension = std::stoi(next("--cell dimension"));
                cells.push_back(c);
            } else if (a == "--help" || a == "-h") {
                std::cout << "Usage: gsk_bench --root <dir> [--iterations N] [--csv out.csv]"
                             " [--cell <suite> <function> <dimension>]...\n";
                return 0;
            } else {
                std::cerr << "gsk_bench: unknown argument '" << a << "'\n";
                return 1;
            }
        } catch (const std::exception& ex) {
            std::cerr << "gsk_bench: " << ex.what() << "\n";
            return 1;
        }
    }
    if (cells.empty()) {
        cells = default_cells();
    }

    std::ofstream csv;
    if (!csv_path.empty()) {
        csv.open(csv_path);
        csv << "suite,function,dimension,iterations,seconds,ns_per_eval,evals_per_sec\n";
    }

    std::cout << "gsk_bench: " << iterations << " evaluations per cell\n";
    std::cout << "suite        f   D     ns/eval     Mevals/s\n";
    double checksum = 0.0; // consumed so the work cannot be optimized away
    int failures = 0;
    for (const auto& c : cells) {
        try {
            const auto data_root = gskcec::default_data_root(c.suite, project_root);
            auto problem = gskcec::make_problem(c.suite, c.function_id, c.dimension, data_root);
            const auto bounds = problem->bounds();

            // Warm up caches and the first-touch of the instance scratch.
            for (int w = 0; w < 100; ++w) {
                checksum += problem->evaluate(probe(bounds, static_cast<std::uint64_t>(w)));
            }

            gskcec::Stopwatch watch;
            for (long long k = 0; k < iterations; ++k) {
                checksum += problem->evaluate(probe(bounds, static_cast<std::uint64_t>(k)));
            }
            const double seconds = watch.elapsed_seconds();
            const double ns_per_eval = seconds / static_cast<double>(iterations) * 1e9;
            const double mevals = static_cast<double>(iterations) / seconds / 1e6;

            std::printf("%-11s %3d %3d  %10.1f  %9.3f\n", c.suite.c_str(), c.function_id,
                        problem->dimension(), ns_per_eval, mevals);
            if (csv) {
                csv << c.suite << ',' << c.function_id << ',' << problem->dimension() << ','
                    << iterations << ',' << seconds << ',' << ns_per_eval << ',' << (mevals * 1e6)
                    << '\n';
            }
        } catch (const std::exception& ex) {
            std::cerr << "gsk_bench: " << c.suite << " f" << c.function_id << " D" << c.dimension
                      << ": " << ex.what() << "\n";
            ++failures;
        }
    }
    // Touch the checksum so the compiler must keep every evaluation.
    if (checksum == 1.2345e-300) {
        std::cerr << "(unreachable)\n";
    }
    return failures == 0 ? 0 : 2;
}
