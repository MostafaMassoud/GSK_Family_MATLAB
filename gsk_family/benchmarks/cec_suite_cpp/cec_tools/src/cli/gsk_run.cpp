// gsk_run: experiment orchestrator.
//
// All GSK-family optimizers are MATLAB implementations under src/ (the
// project contract forbids porting them to C++), so gsk_run validates the
// requested experiment against the C++ benchmark factory and then drives
// MATLAB's src/runners/run_experiment.m in -batch mode, one invocation per
// optimizer. Results land under the output root in the documented schema.

#include "gskcec/benchmark/factory.hpp"
#include "gskcec/experiment/comparison.hpp"
#include "gskcec/experiment/config.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

namespace fs = std::filesystem;

const std::vector<std::string> kOptimizers = {"gsk", "agsk", "apgsk", "atmals-gsk", "egsk", "fdb-agsk"};

void print_usage() {
    std::cout
        << "Usage:\n"
        << "  gsk_run --config <configs/file.yml> [options]\n"
        << "  gsk_run --optimizer <name> --suite <name> [--function N ...] [--dimension D ...]\n"
        << "          [--runs R] [--seed S] [--max-evaluations M] [options]\n"
        << "Options:\n"
        << "  --root <dir>      project root (default .)\n"
        << "  --output <dir>    output root (default <root>/results)\n"
        << "  --matlab <exe>    MATLAB executable (default: GSKCEC_MATLAB env var, then 'matlab' on PATH)\n"
        << "  --seed-policy <p> MATLAB seed policy: reference, native, unified, derived (default reference)\n"
        << "  --rand-generator <g> MATLAB RNG family: threefry, twister, seed, state (default threefry)\n"
        << "  --overwrite       archive the previous output tree and start a clean run\n"
        << "  --reference <dir> imported reference tables (default <root>/benchmarks/cec_reference_results)\n"
        << "  --no-verify       skip the automatic post-run reference comparison (opt-out)\n"
        << "  --dry-run         print the MATLAB invocations without running them\n";
}

std::string forward_slashes(const fs::path& p) {
    return p.generic_string();
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

std::string int_list_matlab(const std::vector<int>& v) {
    std::ostringstream out;
    out << "[";
    for (std::size_t i = 0; i < v.size(); ++i) {
        out << (i == 0 ? "" : " ") << v[i];
    }
    out << "]";
    return out.str();
}

struct CliOptions {
    fs::path project_root = ".";
    fs::path output_root;
    fs::path reference_root; // empty => <project_root>/benchmarks/cec_reference_results
    std::string matlab;
    std::string seed_policy_override;
    std::string rand_generator_override;
    bool overwrite = false;
    bool dry_run = false;
    bool verify = true; // Mandate 1.1c: verify each run by default; --no-verify opts out
};

// Mandate 1.1c: a run used a reduced (non-reference) protocol when its budget
// was overridden or its run count is below a full-study threshold. Reduced
// runs are legitimately worse than the published tables, so the gross-deviation
// check and win/tie/loss become informational rather than hard failures.
bool is_reduced_protocol(const gskcec::ExperimentConfig& cfg) {
    return cfg.max_evaluations != 0 || cfg.runs < 25;
}

std::string locate_matlab(const CliOptions& opts) {
    if (!opts.matlab.empty()) {
        return opts.matlab;
    }
    if (const char* env = std::getenv("GSKCEC_MATLAB"); env != nullptr && *env != '\0') {
        return env;
    }
    return "matlab"; // resolved through PATH by the shell
}

int run_one(const gskcec::ExperimentConfig& cfg,
            const std::string& optimizer,
            const CliOptions& opts,
            const std::string& label) {
    // Validate the experiment against the benchmark factory before any
    // MATLAB startup cost.
    const auto info = gskcec::suite_info(cfg.suite);
    std::vector<int> functions = cfg.functions.empty() ? info.functions : cfg.functions;
    for (const int f : functions) {
        if (std::find(info.functions.begin(), info.functions.end(), f) == info.functions.end()) {
            std::cerr << "gsk_run: function " << f << " is not part of suite " << cfg.suite << ".\n";
            return 1;
        }
    }
    std::vector<int> dimensions = cfg.dimensions;
    if (info.dimensions.empty()) {
        // Fixed native dimension per function: 0 tells the MATLAB runner to
        // use the native dimension.
        for (const int d : dimensions) {
            if (d != 0) {
                std::cerr << "gsk_run: suite " << cfg.suite
                          << " has fixed per-function dimensions; omit dimensions or use 0.\n";
                return 1;
            }
        }
        dimensions = {0};
    } else if (dimensions.empty()) {
        dimensions = info.dimensions;
    } else {
        for (const int d : dimensions) {
            if (std::find(info.dimensions.begin(), info.dimensions.end(), d) == info.dimensions.end()) {
                std::cerr << "gsk_run: dimension " << d << " is not part of suite " << cfg.suite << ".\n";
                return 1;
            }
        }
    }

    const fs::path out_root = !opts.output_root.empty()
                                  ? opts.output_root
                                  : (!cfg.output_root.empty() ? fs::path(cfg.output_root)
                                                              : opts.project_root / "results");
    // CEC-competition layout: results/<optimizer>/<suite>/{summary,curves,gen_logs}
    const fs::path out_dir = out_root / optimizer / cfg.suite;

    std::ostringstream batch;
    batch << "cd('" << forward_slashes(opts.project_root / "src" / "runners") << "'); "
          << "run_experiment("
          << "'optimizer','" << optimizer << "',"
          << "'suite','" << cfg.suite << "',"
          << "'functions'," << int_list_matlab(functions) << ","
          << "'dimensions'," << int_list_matlab(dimensions) << ","
          << "'runs'," << cfg.runs << ","
          << "'base_seed'," << cfg.seed << ","
          << "'max_nfes'," << cfg.max_evaluations << ","
          << "'project_root','" << forward_slashes(fs::absolute(opts.project_root)) << "',"
          << "'output_dir','" << forward_slashes(fs::absolute(out_dir)) << "',"
          << "'overwrite'," << ((opts.overwrite || cfg.overwrite) ? "true" : "false")
          << ",'seed_policy','" << cfg.seed_policy << "'"
          << ",'rand_generator','" << cfg.rand_generator << "'"
          << ",'use_parallel',false"
          << ");";

    const std::string matlab = locate_matlab(opts);
    const std::string inner = "\"" + matlab + "\" -batch \"" + batch.str() + "\"";

    std::cout << "gsk_run: [" << label << "] " << optimizer << " on " << cfg.suite << " -> "
              << forward_slashes(out_dir) << "\n";
    if (opts.dry_run) {
        std::cout << "DRY-RUN: " << inner << "\n";
        return 0;
    }
    // Extra outer quotes keep cmd.exe from eating the quoted executable path.
    const int rc = std::system(("\"" + inner + "\"").c_str());
    if (rc != 0) {
        std::cerr << "gsk_run: MATLAB invocation failed with exit code " << rc
                  << " for optimizer " << optimizer << ".\n";
        return rc > 255 ? 3 : rc;
    }

    // Mandate 1.1c: every run is automatically checked against the same
    // optimizer's published reference table before it counts as done.
    if (opts.verify) {
        const fs::path reference_root =
            !opts.reference_root.empty()
                ? opts.reference_root
                : (!cfg.reference_root.empty()
                       ? fs::path(cfg.reference_root)
                       : opts.project_root / "benchmarks" / "cec_reference_results");
        try {
            const auto summaries = gskcec::load_summaries(out_dir);
            if (summaries.empty()) {
                std::cerr << "gsk_run: no summary produced under " << out_dir.string()
                          << "/summary; cannot verify.\n";
                return 3;
            }
            const auto verification =
                gskcec::classify_run(summaries, reference_root, is_reduced_protocol(cfg));
            const fs::path verification_path =
                noncolliding_path(out_dir / "summary" / "verification.json");
            gskcec::write_verification_json(verification, verification_path);
            std::cout << "gsk_run: verify " << optimizer << " on " << cfg.suite << " -> "
                      << verification.verdict
                      << (verification.reduced_budget ? " (reduced budget)" : " (full protocol)")
                      << "; win/tie/loss=" << verification.wins << "/" << verification.ties << "/"
                      << verification.losses << ", hard_failures=" << verification.hard_failures << "\n";
            for (const auto& c : verification.checks) {
                for (const auto& reason : c.failures) {
                    std::cout << "  f" << c.function_id << " D" << c.dimension << ": " << reason << "\n";
                }
            }
            if (verification.verdict != "CONSISTENT") {
                std::cerr << "gsk_run: " << optimizer << " on " << cfg.suite
                          << " DEVIATES from the reference (see "
                          << forward_slashes(verification_path) << ").\n";
                return 3;
            }
        } catch (const std::exception& ex) {
            std::cerr << "gsk_run: verification failed: " << ex.what() << "\n";
            return 2;
        }
    }
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    std::vector<std::string> args(argv + 1, argv + argc);
    if (args.empty()) {
        print_usage();
        return 1;
    }

    CliOptions opts;
    gskcec::ExperimentConfig cfg;
    bool have_config = false;
    std::string label = "cli";

    try {
        for (std::size_t i = 0; i < args.size(); ++i) {
            const std::string& a = args[i];
            auto next = [&](const char* what) -> std::string {
                if (i + 1 >= args.size()) {
                    throw std::runtime_error(std::string("missing value for ") + what);
                }
                return args[++i];
            };
            if (a == "--config") {
                const fs::path config_path = next("--config");
                cfg = gskcec::load_experiment_config(config_path);
                label = config_path.stem().string();
                have_config = true;
            } else if (a == "--optimizer") {
                cfg.optimizers = {next("--optimizer")};
            } else if (a == "--suite") {
                cfg.suite = next("--suite");
            } else if (a == "--function") {
                cfg.functions.push_back(std::stoi(next("--function")));
            } else if (a == "--dimension") {
                cfg.dimensions.push_back(std::stoi(next("--dimension")));
            } else if (a == "--runs") {
                cfg.runs = std::stoi(next("--runs"));
            } else if (a == "--seed") {
                cfg.seed = static_cast<gskcec::Seed>(std::stoull(next("--seed")));
            } else if (a == "--max-evaluations") {
                cfg.max_evaluations = std::stoll(next("--max-evaluations"));
            } else if (a == "--root") {
                opts.project_root = next("--root");
            } else if (a == "--output") {
                opts.output_root = next("--output");
            } else if (a == "--matlab") {
                opts.matlab = next("--matlab");
            } else if (a == "--seed-policy") {
                opts.seed_policy_override = next("--seed-policy");
                if (!gskcec::is_valid_seed_policy(opts.seed_policy_override)) {
                    throw std::runtime_error("--seed-policy must be reference, native, unified, or derived");
                }
            } else if (a == "--rand-generator") {
                opts.rand_generator_override = next("--rand-generator");
                if (!gskcec::is_valid_rand_generator(opts.rand_generator_override)) {
                    throw std::runtime_error("--rand-generator must be threefry, twister, seed, or state");
                }
            } else if (a == "--reference") {
                opts.reference_root = next("--reference");
            } else if (a == "--overwrite") {
                opts.overwrite = true;
            } else if (a == "--no-verify") {
                opts.verify = false;
            } else if (a == "--dry-run") {
                opts.dry_run = true;
            } else if (a == "--help" || a == "-h") {
                print_usage();
                return 0;
            } else {
                std::cerr << "gsk_run: unknown argument '" << a << "'\n";
                print_usage();
                return 1;
            }
        }

        if (!opts.seed_policy_override.empty()) {
            cfg.seed_policy = opts.seed_policy_override;
        }
        if (!opts.rand_generator_override.empty()) {
            cfg.rand_generator = opts.rand_generator_override;
        }

        if (!have_config) {
            if (cfg.optimizers.empty() || cfg.suite.empty()) {
                std::cerr << "gsk_run: --optimizer and --suite are required without --config.\n";
                print_usage();
                return 1;
            }
            if (cfg.runs < 1) {
                std::cerr << "gsk_run: runs must be >= 1.\n";
                return 1;
            }
        }

        for (const auto& optimizer : cfg.optimizers) {
            if (std::find(kOptimizers.begin(), kOptimizers.end(), optimizer) == kOptimizers.end()) {
                std::cerr << "gsk_run: unknown optimizer '" << optimizer
                          << "'. Known: gsk, agsk, apgsk, atmals-gsk, egsk, fdb-agsk.\n";
                return 1;
            }
        }

        for (const auto& optimizer : cfg.optimizers) {
            const int rc = run_one(cfg, optimizer, opts, label);
            if (rc != 0) {
                return rc;
            }
        }
        return 0;
    } catch (const std::exception& ex) {
        std::cerr << "gsk_run: " << ex.what() << "\n";
        return 2;
    }
}
