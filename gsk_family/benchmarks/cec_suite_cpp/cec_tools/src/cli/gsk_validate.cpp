// gsk_validate: reference-table validation, suite smoke evaluation,
// CEC2013 saved-vector regression and generated-vs-reference comparison.

#include "gskcec/benchmark/data_loading.hpp"
#include "gskcec/benchmark/factory.hpp"
#include "gskcec/benchmark/reference_results.hpp"
#include "gskcec/core/timer.hpp"
#include "gskcec/experiment/comparison.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace {

namespace fs = std::filesystem;

void print_usage() {
    std::cout << "Usage:\n"
              << "  gsk_validate --references <cec_reference_results_root>\n"
              << "  gsk_validate --suite <name> --smoke [--root <project_root>]\n"
              << "  gsk_validate --suite cec2013 --against saved_vectors [--root <project_root>]\n"
              << "  gsk_validate --compare <results_root> <cec_reference_results_root> [--out <report.csv>]\n"
              << "  gsk_validate --verify <run_dir> <cec_reference_results_root> [--reduced|--full]\n"
              << "      (without --reduced/--full the protocol is read from the run's\n"
              << "       summary/environment.json runs/max_nfes_override; full if absent)\n";
}

fs::path noncolliding_path(const fs::path& path) {
    if (!fs::exists(path)) {
        return path;
    }
    const fs::path parent = path.parent_path();
    const std::string stem = path.stem().string();
    const std::string ext = path.extension().string();
    for (int i = 1;; ++i) {
        fs::path candidate = parent / (stem + "_" + std::to_string(i) + ext);
        if (!fs::exists(candidate)) {
            return candidate;
        }
    }
}

// Runs the post-run verdict (Mandate 1.1c): is this run consistent with the
// same optimizer's published reference table? Writes a non-colliding
// verification*.json file and prints CONSISTENT/DEVIATES. Returns the process
// exit code. Without an explicit --reduced/--full the protocol comes from the
// run's own environment.json, with the same rule gsk_run applies, so a
// standalone re-check agrees with gsk_run's automatic verdict.
int run_verify(const fs::path& run_dir, const fs::path& reference_root,
               std::optional<bool> reduced_flag) {
    const auto summaries = gskcec::load_summaries(run_dir);
    if (summaries.empty()) {
        std::cerr << "gsk_validate: no summary tables (summary/<opt>_<suite>_D<dim>.csv) found under "
                  << run_dir.string() << "\n";
        return 2;
    }
    bool reduced = false;
    std::string protocol_source = "--reduced/--full flag";
    if (reduced_flag) {
        reduced = *reduced_flag;
    } else {
        protocol_source = "default (no readable environment.json; pass --reduced or --full)";
        for (const auto& env : {run_dir / "summary" / "environment.json", run_dir / "environment.json"}) {
            if (const auto from_env = gskcec::reduced_protocol_from_environment(env)) {
                reduced = *from_env;
                protocol_source = env.generic_string();
                break;
            }
        }
    }
    const auto verification = gskcec::classify_run(summaries, reference_root, reduced);
    // Match gsk_run: keep the verdict next to the summaries when a summary/
    // subdir exists (the CEC-competition layout).
    const auto out_path = noncolliding_path(fs::exists(run_dir / "summary")
                                                ? run_dir / "summary" / "verification.json"
                                                : run_dir / "verification.json");
    gskcec::write_verification_json(verification, out_path);

    std::cout << "Verification: " << verification.optimizer << " on " << verification.suite
              << " -> " << verification.verdict
              << (verification.reduced_budget ? " (reduced budget)" : " (full protocol)") << "\n";
    std::cout << "  protocol from: " << protocol_source << "\n";
    std::cout << "  functions checked=" << verification.functions_checked
              << " hard_failures=" << verification.hard_failures
              << " win/tie/loss=" << verification.wins << "/" << verification.ties << "/"
              << verification.losses << " no_reference=" << verification.missing_reference << "\n";
    for (const auto& c : verification.checks) {
        for (const auto& reason : c.failures) {
            std::cout << "  f" << c.function_id << " D" << c.dimension << ": " << reason << "\n";
        }
    }
    std::cout << "  report: " << out_path.generic_string() << "\n";
    return verification.verdict == "CONSISTENT" ? 0 : 3;
}

/// Deterministic in-bounds probe: midpoint shifted per coordinate.
gskcec::Vector pattern_point(const gskcec::Bounds& bounds) {
    gskcec::Vector x(bounds.dimension());
    for (gskcec::Index j = 0; j < x.size(); ++j) {
        const double lo = bounds.lower()[j];
        const double hi = bounds.upper()[j];
        const double t = 0.25 + 0.5 * (static_cast<double>(j % 7) / 6.0);
        x[j] = lo + t * (hi - lo);
    }
    return x;
}

int run_suite_smoke(const std::string& suite, const fs::path& project_root) {
    const auto info = gskcec::suite_info(suite);
    const auto data_root = gskcec::default_data_root(suite, project_root);
    std::vector<int> dimensions = info.dimensions;
    if (dimensions.empty()) {
        dimensions = {0}; // native per function
    }
    int evaluated = 0;
    int skipped = 0;
    gskcec::Stopwatch watch;
    for (const int function_id : info.functions) {
        for (const int dimension : dimensions) {
            std::unique_ptr<gskcec::BenchmarkProblem> problem;
            try {
                problem = gskcec::make_problem(suite, function_id, dimension, data_root);
            } catch (const std::runtime_error& ex) {
                // Data-driven unavailability (e.g. cec2020 f1/f8 at D=5/15 in
                // the reference data). Reported explicitly, never silent.
                std::cout << "SKIP " << suite << " f" << function_id << " D" << dimension
                          << ": " << ex.what() << "\n";
                ++skipped;
                continue;
            }
            const auto bounds = problem->bounds();
            gskcec::Vector mid(bounds.dimension());
            for (gskcec::Index j = 0; j < mid.size(); ++j) {
                mid[j] = (bounds.lower()[j] + bounds.upper()[j]) / 2.0;
            }
            const double f_mid = problem->evaluate(mid);
            const double f_pat = problem->evaluate(pattern_point(bounds));
            // The CEC2011 reference NaN->0 rule means NaN must never escape;
            // +/-Inf is legitimate there (documented). Other suites must be
            // strictly finite at in-bounds points.
            const bool mid_ok = suite == "cec2011" ? !std::isnan(f_mid) : std::isfinite(f_mid);
            const bool pat_ok = suite == "cec2011" ? !std::isnan(f_pat) : std::isfinite(f_pat);
            if (!mid_ok || !pat_ok) {
                std::cerr << "FAIL " << suite << " f" << function_id << " D" << problem->dimension()
                          << ": non-finite smoke value (mid=" << f_mid << ", pattern=" << f_pat << ")\n";
                return 3;
            }
            ++evaluated;
        }
    }
    std::cout << "Suite " << suite << " smoke passed: " << evaluated << " (function,dimension) cells evaluated";
    if (skipped > 0) {
        std::cout << ", " << skipped << " skipped for missing reference data (listed above)";
    }
    std::cout << " in " << watch.elapsed_seconds() << " s.\n";
    return 0;
}

int run_cec2013_saved_vectors(const fs::path& project_root) {
    const fs::path csv = project_root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data" / "cec2013_regression.csv";
    const fs::path data_root = gskcec::default_data_root("cec2013", project_root);
    std::ifstream in(csv);
    if (!in) {
        std::cerr << "gsk_validate: cannot open " << csv.generic_string() << "\n";
        return 2;
    }
    std::string line;
    int checked = 0;
    double max_rel = 0.0;
    std::unique_ptr<gskcec::BenchmarkProblem> problem;
    int cur_f = -1;
    int cur_d = -1;
    gskcec::Vector points; // 5 x D probe matrix, row-major
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#' || line.rfind("function", 0) == 0) {
            continue;
        }
        std::stringstream ss(line);
        std::string tok;
        std::vector<std::string> f;
        while (std::getline(ss, tok, ',')) {
            f.push_back(tok);
        }
        if (f.size() != 4) {
            std::cerr << "gsk_validate: bad row in " << csv.generic_string() << ": " << line << "\n";
            return 2;
        }
        const int function_id = std::stoi(f[0]);
        const int dimension = std::stoi(f[1]);
        const int point_id = std::stoi(f[2]);
        const double expected = std::stod(f[3]);
        if (function_id != cur_f || dimension != cur_d) {
            problem = gskcec::make_problem("cec2013", function_id, dimension, data_root);
            cur_f = function_id;
            cur_d = dimension;
            points = gskcec::load_values_file(project_root / "benchmarks" / "cec_suite_cpp" / "cec_tools" / "tests" / "data" /
                                              ("points_D" + std::to_string(dimension) + ".txt"));
        }
        // Guard the slice: a regression CSV row whose point id exceeds the
        // points file would otherwise form an out-of-range iterator pair.
        if (point_id < 1 ||
            static_cast<std::size_t>(point_id) * static_cast<std::size_t>(dimension) > points.size()) {
            std::cerr << "gsk_validate: cec2013 regression row f" << function_id << " D" << dimension
                      << " p" << point_id << " is out of range for points_D" << dimension << ".txt\n";
            return 2;
        }
        gskcec::Vector x(points.begin() + static_cast<long long>((point_id - 1) * dimension),
                         points.begin() + static_cast<long long>(point_id * dimension));
        const double got = problem->evaluate(x);
        const double rel = std::abs(got - expected) / std::max(1.0, std::abs(expected));
        max_rel = std::max(max_rel, rel);
        if (rel > 1.0e-12) {
            std::cerr << "FAIL cec2013 f" << function_id << " D" << dimension << " p" << point_id
                      << ": got " << got << ", expected " << expected << " (rel " << rel << ")\n";
            return 3;
        }
        ++checked;
    }
    std::cout << "cec2013 saved-vector validation passed: " << checked
              << " rows, max relative deviation " << max_rel << ".\n";
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    std::vector<std::string> args(argv + 1, argv + argc);
    if (args.empty()) {
        print_usage();
        return 1;
    }

    // Boolean flags (no value): --reduced / --full select the verification
    // protocol context. Without either, --verify reads it from the run's
    // environment.json (strict full protocol when that is absent).
    std::optional<bool> reduced;
    for (std::size_t i = 0; i < args.size();) {
        if (args[i] == "--reduced") {
            reduced = true;
            args.erase(args.begin() + static_cast<long long>(i));
        } else if (args[i] == "--full") {
            reduced = false;
            args.erase(args.begin() + static_cast<long long>(i));
        } else {
            ++i;
        }
    }

    // Value flags.
    fs::path project_root = ".";
    fs::path out_csv;
    for (std::size_t i = 0; i + 1 < args.size();) {
        if (args[i] == "--root") {
            project_root = args[i + 1];
            args.erase(args.begin() + static_cast<long long>(i), args.begin() + static_cast<long long>(i) + 2);
        } else if (args[i] == "--out") {
            out_csv = args[i + 1];
            args.erase(args.begin() + static_cast<long long>(i), args.begin() + static_cast<long long>(i) + 2);
        } else {
            ++i;
        }
    }
    // The flags above may have consumed every argument (e.g. `gsk_validate --full`).
    if (args.empty()) {
        print_usage();
        return 1;
    }

    try {
        if (args[0] == "--references") {
            if (args.size() < 2) {
                print_usage();
                return 1;
            }
            const auto files = gskcec::load_reference_tree(args[1]);
            std::size_t rows = 0;
            for (const auto& file : files) {
                rows += file.rows.size();
            }
            std::cout << "Reference validation passed.\n"
                      << "files=" << files.size() << "\n"
                      << "rows=" << rows << "\n";
            return 0;
        }

        if (args[0] == "--suite") {
            if (args.size() < 3) {
                print_usage();
                return 1;
            }
            const std::string suite = args[1];
            if (args[2] == "--smoke") {
                return run_suite_smoke(suite, project_root);
            }
            if (args[2] == "--against" && args.size() >= 4 && args[3] == "saved_vectors") {
                if (suite != "cec2013") {
                    std::cerr << "gsk_validate: saved_vectors validation is defined for cec2013 only.\n";
                    return 1;
                }
                return run_cec2013_saved_vectors(project_root);
            }
            print_usage();
            return 1;
        }

        if (args[0] == "--verify") {
            if (args.size() < 3) {
                print_usage();
                return 1;
            }
            return run_verify(args[1], args[2], reduced);
        }

        if (args[0] == "--compare") {
            if (args.size() < 3) {
                print_usage();
                return 1;
            }
            const auto summaries = gskcec::load_summaries(args[1]);
            if (summaries.empty()) {
                std::cerr << "gsk_validate: no summary tables found under " << args[1] << "\n";
                return 2;
            }
            const auto report = gskcec::compare_with_references(summaries, args[2]);
            for (const auto& e : report.entries) {
                std::cout << e.optimizer << " " << e.suite << " f" << e.function_id << " D" << e.dimension
                          << " mean=" << e.generated_mean;
                if (e.reference_mean) {
                    std::cout << " ref_mean=" << *e.reference_mean << " rel_diff=" << *e.rel_diff;
                }
                std::cout << " -> " << e.verdict << "\n";
            }
            std::cout << "compared=" << report.entries.size() << " win=" << report.wins
                      << " tie=" << report.ties << " loss=" << report.losses
                      << " no_reference=" << report.missing_reference << "\n";
            if (!out_csv.empty()) {
                gskcec::write_comparison_csv(report, out_csv);
                std::cout << "report written to " << out_csv.generic_string() << "\n";
            }
            return 0;
        }
    } catch (const std::exception& ex) {
        std::cerr << "gsk_validate: " << ex.what() << "\n";
        return 2;
    }

    print_usage();
    return 1;
}
