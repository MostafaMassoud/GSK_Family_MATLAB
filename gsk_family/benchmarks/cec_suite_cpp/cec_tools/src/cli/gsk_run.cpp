// gsk_run: runs an experiment given on the command line or in a config file.
//
// The GSK-family optimizers are MATLAB code under src/ (by project rule they
// are not ported to C++). gsk_run checks the requested cells against the C++
// benchmark factory, then calls src/runners/run_experiment.m through
// "matlab -batch", once per optimizer, and verifies each run against its
// reference table (unless --no-verify). Results go under the output root in
// the documented result schema.
// Exit code: 0 ok, 1 usage error, 2 other error (e.g. bad config file or
// verification could not run), 3 DEVIATES or no summary to verify. A failed
// MATLAB call passes on MATLAB's exit code (3 if it is above 255).

#include "gskcec/benchmark/factory.hpp"
#include "gskcec/experiment/comparison.hpp"
#include "gskcec/experiment/config.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

namespace fs = std::filesystem;

const std::vector<std::string> kOptimizers = {"gsk", "agsk", "apgsk", "atmals-gsk", "egsk", "fdb-agsk", "dt-gsk"};

void print_usage() {
    std::cout
        << "Usage:\n"
        << "  gsk_run --config <configs/file.yml> [options]\n"
        << "  gsk_run --optimizer <name> --suite <name> [--function N]... [--dimension D]...\n"
        << "          [--runs R] [--seed S] [--max-evaluations M] [options]\n"
        << "  Each numeric flag takes one whole integer; repeat --function/--dimension\n"
        << "  for several values. --seed is in [0, 2^53]; --max-evaluations >= 0 (0 = suite default).\n"
        << "Options:\n"
        << "  --root <dir>      project root (default .); relative output_root/reference_root\n"
        << "                    in a config resolve under it\n"
        << "  --output <dir>    output root (default <root>/results; relative to the working directory)\n"
        << "  --matlab <exe>    MATLAB executable (default: GSKCEC_MATLAB env var, then 'matlab' on PATH)\n"
        << "  --seed-policy <p> MATLAB seed policy: reference, native, unified, derived (default reference)\n"
        << "  --rand-generator <g> MATLAB RNG family: threefry, twister, seed, state (default threefry)\n"
        << "  --np-init <n>     initial population size for every optimizer (>= 12; 0 = each\n"
        << "                    optimizer's default: 100, or 5*D for dt-gsk)\n"
        << "  --min-pop-size <m> final population size of agsk, apgsk, fdb-agsk and dt-gsk\n"
        << "                    (>= 11; 0 = each one's default); gsk, egsk, atmals-gsk ignore it.\n"
        << "                    Either override makes verification informational (reduced protocol)\n"
        << "  --overwrite       archive the previous output tree and start a clean run\n"
        << "  --reference <dir> imported reference tables (default <root>/benchmarks/cec_reference_results;\n"
        << "                    relative to the working directory)\n"
        << "  --no-verify       skip the automatic post-run reference comparison (opt-out)\n"
        << "  --dry-run         print the MATLAB invocations without running them\n"
        << "A multi-optimizer config runs every optimizer, then exits with the first\n"
        << "nonzero code (1 MATLAB/usage failure, 2 verification error, 3 DEVIATES).\n";
}

std::string forward_slashes(const fs::path& p) {
    return p.generic_string();
}

// Escapes a value for a single-quoted MATLAB char literal (' -> ''), so a
// path like C:/Users/O'Brien/... does not break the -batch command.
std::string matlab_quote(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 2);
    for (const char c : s) {
        out += c;
        if (c == '\'') {
            out += '\'';
        }
    }
    return out;
}

// Relative roots in a config file resolve under --root, so a config behaves
// the same from any working directory. Explicit --output/--reference flags
// still resolve against the working directory.
fs::path rooted(const fs::path& root, const std::string& value) {
    const fs::path p(value);
    return p.is_absolute() ? p : root / p;
}

// Strict integer flag parsing, as in config.cpp: the whole token must be an
// integer, so '--function 1,3' or '--runs 2.9' fail with a clear message
// instead of being silently cut to 1 or 2. cli_ll does the same for long long.
int cli_int(const std::string& flag, const std::string& value) {
    std::size_t consumed = 0;
    int v = 0;
    try {
        v = std::stoi(value, &consumed);
    } catch (const std::exception&) {
        consumed = 0;
    }
    if (value.empty() || consumed != value.size()) {
        throw std::runtime_error(flag + " expects one integer, got '" + value + "'");
    }
    return v;
}

long long cli_ll(const std::string& flag, const std::string& value) {
    std::size_t consumed = 0;
    long long v = 0;
    try {
        v = std::stoll(value, &consumed);
    } catch (const std::exception&) {
        consumed = 0;
    }
    if (value.empty() || consumed != value.size()) {
        throw std::runtime_error(flag + " expects one integer, got '" + value + "'");
    }
    return v;
}

// Returns @p path if it is free, else the first free <stem>_1<ext>,
// <stem>_2<ext>, ... so an earlier file is never overwritten.
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

// Formats {1, 2, 3} as the MATLAB row vector "[1 2 3]".
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
    fs::path reference_root; // empty = config value or the default (see run_one)
    std::string matlab;
    std::string seed_policy_override;
    std::string rand_generator_override;
    bool overwrite = false;
    bool dry_run = false;
    bool verify = true; // verify each run by default; --no-verify turns it off
};

// A run uses a reduced (non-reference) protocol when its budget is overridden,
// it has fewer than 25 runs (a full study), or a population size is
// overridden. Reduced runs can differ from the published tables, so the
// gross-deviation check and win/tie/loss are informational, not hard
// failures. The rule is shared with gsk_validate --verify (comparison.hpp).
bool is_reduced_protocol(const gskcec::ExperimentConfig& cfg) {
    return gskcec::is_reduced_protocol(cfg.runs, cfg.max_evaluations,
                                       cfg.np_init != 0 || cfg.min_pop_size != 0);
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

// Checks the requested functions and dimensions against the benchmark
// factory before MATLAB starts, and fills in the suite defaults when none are
// given. It does not depend on the optimizer, so main() calls it once.
// Returns 0, or 1 after printing the reason. An unknown suite throws.
int resolve_cells(const gskcec::ExperimentConfig& cfg,
                  std::vector<int>& functions,
                  std::vector<int>& dimensions) {
    const auto info = gskcec::suite_info(cfg.suite);
    functions = cfg.functions.empty() ? info.functions : cfg.functions;
    for (const int f : functions) {
        if (std::find(info.functions.begin(), info.functions.end(), f) == info.functions.end()) {
            std::cerr << "gsk_run: function " << f << " is not part of suite " << cfg.suite << ".\n";
            return 1;
        }
    }
    dimensions = cfg.dimensions;
    if (info.dimensions.empty()) {
        // Each function has a fixed native dimension; 0 tells the MATLAB
        // runner to use it.
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
    return 0;
}

// Runs one optimizer in MATLAB, then verifies it. Returns the exit code and
// sets @p status to a short outcome label for the multi-optimizer summary.
int run_one(const gskcec::ExperimentConfig& cfg,
            const std::string& optimizer,
            const std::vector<int>& functions,
            const std::vector<int>& dimensions,
            const CliOptions& opts,
            const std::string& label,
            std::string& status) {
    status = "ok";
    const fs::path out_root = !opts.output_root.empty()
                                  ? opts.output_root
                                  : (!cfg.output_root.empty() ? rooted(opts.project_root, cfg.output_root)
                                                              : opts.project_root / "results");
    // CEC competition layout: results/<optimizer>/<suite>/{summary,curves,gen_logs}
    const fs::path out_dir = out_root / optimizer / cfg.suite;

    std::ostringstream batch;
    batch << "cd('" << matlab_quote(forward_slashes(opts.project_root / "src" / "runners")) << "'); "
          << "run_experiment("
          << "'optimizer','" << matlab_quote(optimizer) << "',"
          << "'suite','" << matlab_quote(cfg.suite) << "',"
          << "'functions'," << int_list_matlab(functions) << ","
          << "'dimensions'," << int_list_matlab(dimensions) << ","
          << "'runs'," << cfg.runs << ","
          << "'base_seed'," << cfg.seed << ","
          << "'max_nfes'," << cfg.max_evaluations << ","
          << "'project_root','" << matlab_quote(forward_slashes(fs::absolute(opts.project_root))) << "',"
          << "'output_dir','" << matlab_quote(forward_slashes(fs::absolute(out_dir))) << "',"
          << "'overwrite'," << ((opts.overwrite || cfg.overwrite) ? "true" : "false")
          << ",'seed_policy','" << matlab_quote(cfg.seed_policy) << "'"
          << ",'rand_generator','" << matlab_quote(cfg.rand_generator) << "'";
    // Passed only when set, so a default call is unchanged.
    if (cfg.np_init != 0) {
        batch << ",'np_init'," << cfg.np_init;
    }
    if (cfg.min_pop_size != 0) {
        batch << ",'min_pop_size'," << cfg.min_pop_size;
    }
    batch << ",'use_parallel',false"
          << ");";

    const std::string matlab = locate_matlab(opts);
    const std::string inner = "\"" + matlab + "\" -batch \"" + batch.str() + "\"";

    std::cout << "gsk_run: [" << label << "] " << optimizer << " on " << cfg.suite << " -> "
              << forward_slashes(out_dir) << "\n";
    if (opts.dry_run) {
        std::cout << "DRY-RUN: " << inner << "\n";
        status = "dry-run";
        return 0;
    }
    // Extra outer quotes stop cmd.exe from stripping the quoted exe path.
    const int rc = std::system(("\"" + inner + "\"").c_str());
    if (rc != 0) {
        std::cerr << "gsk_run: MATLAB invocation failed with exit code " << rc
                  << " for optimizer " << optimizer << ".\n";
        status = "MATLAB failed";
        return rc > 255 ? 3 : rc;
    }
    if (!opts.verify) {
        status = "ok (not verified)";
    }

    // Post-run check (Mandate 1.1c): compare the run with the same
    // optimizer's published reference table before it counts as done.
    if (opts.verify) {
        const fs::path reference_root =
            !opts.reference_root.empty()
                ? opts.reference_root
                : (!cfg.reference_root.empty()
                       ? rooted(opts.project_root, cfg.reference_root)
                       : opts.project_root / "benchmarks" / "cec_reference_results");
        try {
            const auto summaries = gskcec::load_summaries(out_dir);
            if (summaries.empty()) {
                std::cerr << "gsk_run: no summary produced under " << out_dir.string()
                          << "/summary; cannot verify.\n";
                status = "no summary";
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
                status = "DEVIATES";
                return 3;
            }
            status = "CONSISTENT";
        } catch (const std::exception& ex) {
            std::cerr << "gsk_run: verification failed: " << ex.what() << "\n";
            status = "verification error";
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
                cfg.functions.push_back(cli_int("--function", next("--function")));
            } else if (a == "--dimension") {
                cfg.dimensions.push_back(cli_int("--dimension", next("--dimension")));
            } else if (a == "--runs") {
                cfg.runs = cli_int("--runs", next("--runs"));
            } else if (a == "--seed") {
                const std::string value = next("--seed");
                try {
                    cfg.seed = gskcec::parse_seed_value(value);
                } catch (const std::exception& ex) {
                    throw std::runtime_error(std::string("--seed ") + ex.what());
                }
            } else if (a == "--max-evaluations") {
                cfg.max_evaluations = cli_ll("--max-evaluations", next("--max-evaluations"));
                if (cfg.max_evaluations < 0) {
                    throw std::runtime_error("--max-evaluations must be >= 0 (0 = suite default budget)");
                }
            } else if (a == "--np-init") {
                const long long v = cli_ll("--np-init", next("--np-init"));
                if (!gskcec::is_valid_np_init(v)) {
                    throw std::runtime_error("--np-init must be 0 (optimizer default) or an integer >= 12");
                }
                cfg.np_init = static_cast<int>(v);
            } else if (a == "--min-pop-size") {
                const long long v = cli_ll("--min-pop-size", next("--min-pop-size"));
                if (!gskcec::is_valid_min_pop_size(v)) {
                    throw std::runtime_error("--min-pop-size must be 0 (optimizer default) or an integer >= 11");
                }
                cfg.min_pop_size = static_cast<int>(v);
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
        }
        // Checked after all flags are read, so a --runs override of a
        // config is checked too.
        if (cfg.runs < 1) {
            std::cerr << "gsk_run: runs must be >= 1.\n";
            return 1;
        }

        for (const auto& optimizer : cfg.optimizers) {
            if (std::find(kOptimizers.begin(), kOptimizers.end(), optimizer) == kOptimizers.end()) {
                std::cerr << "gsk_run: unknown optimizer '" << optimizer
                          << "'. Known: gsk, agsk, apgsk, atmals-gsk, egsk, fdb-agsk, dt-gsk.\n";
                return 1;
            }
        }

        std::vector<int> functions;
        std::vector<int> dimensions;
        if (const int rc = resolve_cells(cfg, functions, dimensions); rc != 0) {
            return rc;
        }

        // Run and verify every optimizer even if an earlier one fails or
        // DEVIATES, so one failure does not stop a multi-optimizer campaign.
        // Return the first nonzero code (see the file header).
        struct Outcome {
            std::string optimizer;
            int rc = 0;
            std::string status;
        };
        int overall_rc = 0;
        std::vector<Outcome> outcomes;
        for (const auto& optimizer : cfg.optimizers) {
            Outcome o{optimizer, 0, ""};
            try {
                o.rc = run_one(cfg, optimizer, functions, dimensions, opts, label, o.status);
            } catch (const std::exception& ex) {
                std::cerr << "gsk_run: " << optimizer << " on " << cfg.suite << ": " << ex.what() << "\n";
                o.rc = 2;
                o.status = "error";
            }
            if (o.rc != 0 && overall_rc == 0) {
                overall_rc = o.rc;
            }
            outcomes.push_back(std::move(o));
        }
        if (outcomes.size() > 1) {
            std::cout << "gsk_run: [" << label << "] summary:\n";
            for (const auto& o : outcomes) {
                std::cout << "  " << o.optimizer << " on " << cfg.suite << ": " << o.status
                          << " (exit " << o.rc << ")\n";
            }
        }
        if (overall_rc != 0) {
            std::string failed;
            for (const auto& o : outcomes) {
                if (o.rc != 0) {
                    failed += (failed.empty() ? "" : ", ") + o.optimizer + " (" + o.status + ")";
                }
            }
            std::cerr << "gsk_run: [" << label << "] not clean: " << failed << ".\n";
        }
        return overall_rc;
    } catch (const std::exception& ex) {
        std::cerr << "gsk_run: " << ex.what() << "\n";
        return 2;
    }
}
