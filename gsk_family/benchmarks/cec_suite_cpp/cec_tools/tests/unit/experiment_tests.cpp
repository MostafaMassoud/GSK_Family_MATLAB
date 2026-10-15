// Tests for the experiment config parser and the results-vs-reference
// comparison helpers.

#include "gskcec/experiment/comparison.hpp"
#include "gskcec/experiment/config.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace {

namespace fs = std::filesystem;
int failures = 0;

void check(bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        ++failures;
    }
}

void write_file(const fs::path& path, const std::string& content) {
    fs::create_directories(path.parent_path());
    std::ofstream out(path);
    out << content;
}

template <typename Fn>
bool throws(Fn&& fn) {
    try {
        fn();
        return false;
    } catch (const std::exception&) {
        return true;
    }
}

} // namespace

int main() {
    const fs::path tmp = fs::temp_directory_path() / "gskcec_experiment_tests";
    fs::remove_all(tmp);
    fs::create_directories(tmp);

    // --- Config parsing -------------------------------------------------
    {
        const fs::path cfg_path = tmp / "good.yml";
        write_file(cfg_path,
                   "# comment line\n"
                   "optimizers: [gsk, agsk]\n"
                   "suite: cec2017\n"
                   "functions: [1, 3, 5] # trailing comment\n"
                   "dimensions: [10]\n"
                   "runs: 3\n"
                   "seed: 999\n"
                   "seed_policy: native\n"
                   "rand_generator: state\n"
                   "max_evaluations: 5000\n"
                   "overwrite: true\n");
        const auto cfg = gskcec::load_experiment_config(cfg_path);
        check(cfg.optimizers.size() == 2 && cfg.optimizers[0] == "gsk" && cfg.optimizers[1] == "agsk",
              "config optimizers parsed");
        check(cfg.suite == "cec2017", "config suite parsed");
        check(cfg.functions == std::vector<int>({1, 3, 5}), "config functions parsed");
        check(cfg.dimensions == std::vector<int>({10}), "config dimensions parsed");
        check(cfg.runs == 3 && cfg.seed == 999 && cfg.max_evaluations == 5000, "config scalars parsed");
        check(cfg.seed_policy == "native", "config seed_policy parsed");
        check(cfg.rand_generator == "state", "config rand_generator parsed");
        check(cfg.overwrite, "config overwrite parsed");
    }
    {
        const fs::path cfg_path = tmp / "all.yml";
        write_file(cfg_path,
                   "optimizers: [gsk]\n"
                   "suite: cec2011\n"
                   "functions: all\n"
                   "runs: 1\n");
        const auto cfg = gskcec::load_experiment_config(cfg_path);
        check(cfg.functions.empty(), "functions: all -> empty list (suite default)");
        check(cfg.dimensions.empty(), "absent dimensions -> empty list");
        check(cfg.seed_policy == "reference", "default seed_policy is reference");
        check(cfg.rand_generator == "threefry", "default rand_generator is threefry");
    }
    {
        check(throws([&] { gskcec::load_experiment_config(tmp / "missing.yml"); }),
              "missing config throws");
        const fs::path bad_key = tmp / "bad_key.yml";
        write_file(bad_key, "optimizers: [gsk]\nsuite: cec2017\nbudget: 5\n");
        check(throws([&] { gskcec::load_experiment_config(bad_key); }), "unknown key throws");
        const fs::path bad_runs = tmp / "bad_runs.yml";
        write_file(bad_runs, "optimizers: [gsk]\nsuite: cec2017\nruns: 0\n");
        check(throws([&] { gskcec::load_experiment_config(bad_runs); }), "runs < 1 throws");
        const fs::path bad_seed_policy = tmp / "bad_seed_policy.yml";
        write_file(bad_seed_policy, "optimizers: [gsk]\nsuite: cec2017\nseed_policy: clock\n");
        check(throws([&] { gskcec::load_experiment_config(bad_seed_policy); }),
              "invalid seed_policy throws");
        const fs::path bad_rand_generator = tmp / "bad_rand_generator.yml";
        write_file(bad_rand_generator, "optimizers: [gsk]\nsuite: cec2017\nrand_generator: random_device\n");
        check(throws([&] { gskcec::load_experiment_config(bad_rand_generator); }),
              "invalid rand_generator throws");
        const fs::path clock_rand_generator = tmp / "clock_rand_generator.yml";
        write_file(clock_rand_generator, "optimizers: [gsk]\nsuite: cec2017\nrand_generator: clock\n");
        check(throws([&] { gskcec::load_experiment_config(clock_rand_generator); }),
              "clock rand_generator rejected");
        const fs::path no_suite = tmp / "no_suite.yml";
        write_file(no_suite, "optimizers: [gsk]\nruns: 2\n");
        check(throws([&] { gskcec::load_experiment_config(no_suite); }), "missing suite throws");
        const fs::path bad_list = tmp / "bad_list.yml";
        write_file(bad_list, "optimizers: [gsk\nsuite: cec2017\n");
        check(throws([&] { gskcec::load_experiment_config(bad_list); }), "unterminated list throws");
        const fs::path par_true = tmp / "par_true.yml";
        write_file(par_true, "optimizers: [gsk]\nsuite: cec2017\nparallel: true\n");
        check(throws([&] { gskcec::load_experiment_config(par_true); }),
              "parallel: true rejected explicitly");
        const fs::path par_false = tmp / "par_false.yml";
        write_file(par_false, "optimizers: [gsk]\nsuite: cec2017\nparallel: false\n");
        check(!gskcec::load_experiment_config(par_false).parallel, "parallel: false accepted");
    }

    // --- Summary loading and comparison ---------------------------------
    // CEC-competition layout: results/<optimizer>/<suite>/summary/<opt>_<suite>_D<dim>.csv
    {
        const fs::path summary = tmp / "results" / "gsk" / "cec2017" / "summary";
        write_file(summary / "gsk_cec2017_D10.csv",
                   "Function,Best,Median,Mean,Worst,SD\n"
                   "1,1.0e-08,2.0e-08,3.0e-08,4.0e-08,1.0e-08\n"
                   "3,5.0e+02,6.0e+02,7.0e+02,8.0e+02,1.0e+02\n"
                   "4,1.0e+00,1.0e+00,1.0e+00,1.0e+00,0.0e+00\n");
        // The dimensionless rollup and per_run.csv must be ignored by the loader.
        write_file(summary / "gsk_cec2017.csv", "Function,Best,Median,Mean,Worst,SD\n1,1,1,1,1,1\n");
        write_file(summary / "per_run.csv", "optimizer,suite,function\ngsk,cec2017,1\n");
        const auto rows = gskcec::load_summaries(tmp / "results");
        check(rows.size() == 3, "summary rows loaded (rollup + per_run ignored)");
        check(rows[0].optimizer == "gsk" && rows[0].suite == "cec2017" && rows[0].dimension == 10,
              "optimizer/suite/dimension parsed from path");

        const fs::path refs = tmp / "refs";
        write_file(refs / "cec2017" / "gsk" / "gsk_cec2017_D10.csv",
                   "Function,Best,Median,Mean,Worst,SD\n"
                   "F1,0.00E+00,0.00E+00,1.00E-07,0.00E+00,0.00E+00\n"
                   "F3,,,7.00E+02,,\n");
        const auto report = gskcec::compare_with_references(rows, refs);
        check(report.entries.size() == 3, "comparison entries");
        check(report.wins == 1, "f1 mean 3e-8 beats reference 1e-7 -> win");
        check(report.ties == 1, "f3 equal means -> tie");
        check(report.missing_reference == 1, "f4 missing -> no_reference");

        const fs::path out_csv = tmp / "report.csv";
        gskcec::write_comparison_csv(report, out_csv);
        check(fs::exists(out_csv), "comparison csv written");
    }

    // --- Post-run verification verdict (Mandate 1.1c) -------------------
    {
        const fs::path refs = tmp / "vrefs";
        write_file(refs / "cec2017" / "gsk" / "gsk_cec2017_D10.csv",
                   "Function,Best,Median,Mean,Worst,SD\n"
                   "F1,0.00E+00,0.00E+00,1.00E-07,0.00E+00,0.00E+00\n"
                   "F3,5.0e+02,6.0e+02,7.0e+02,8.0e+02,1.0e+02\n");

        // Each run uses the CEC layout <dir>/<opt>/<suite>/summary/<opt>_<suite>_D<dim>.csv.
        const std::string hdr = "Function,Best,Median,Mean,Worst,SD\n";

        // Clean full-protocol run: finite, non-negative errors, near reference.
        const fs::path good = tmp / "vgood";
        write_file(good / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr +
                   "1,1.0e-08,2.0e-08,3.0e-08,4.0e-08,1.0e-08\n"
                   "3,5.0e+02,6.0e+02,7.0e+02,8.0e+02,1.0e+02\n");
        auto v_good = gskcec::classify_run(gskcec::load_summaries(good), refs, /*reduced=*/false);
        check(v_good.verdict == "CONSISTENT", "clean run -> CONSISTENT");
        check(v_good.hard_failures == 0, "clean run has no hard failures");

        // Non-finite statistic -> DEVIATES.
        const fs::path nanrun = tmp / "vnan";
        write_file(nanrun / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "1,1.0e-08,2.0e-08,nan,4.0e-08,1.0e-08\n");
        auto v_nan = gskcec::classify_run(gskcec::load_summaries(nanrun), refs, false);
        check(v_nan.verdict == "DEVIATES", "non-finite mean -> DEVIATES");

        // Negative error on a known-optimum suite -> DEVIATES (beat optimum).
        const fs::path negrun = tmp / "vneg";
        write_file(negrun / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "1,-5.0e+00,1.0e+00,1.0e+00,2.0e+00,1.0e+00\n");
        auto v_neg = gskcec::classify_run(gskcec::load_summaries(negrun), refs, false);
        check(v_neg.verdict == "DEVIATES", "negative best error -> DEVIATES");

        // Gross deviation: hard failure at full protocol, informational when reduced.
        const fs::path grossrun = tmp / "vgross";
        write_file(grossrun / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "3,5.0e+02,6.0e+02,9.0e+12,9.0e+12,1.0e+02\n");
        auto v_full = gskcec::classify_run(gskcec::load_summaries(grossrun), refs, /*reduced=*/false);
        check(v_full.verdict == "DEVIATES", "gross deviation at full protocol -> DEVIATES");
        auto v_red = gskcec::classify_run(gskcec::load_summaries(grossrun), refs, /*reduced=*/true);
        check(v_red.verdict == "CONSISTENT", "same gross gap under reduced budget -> informational");

        // cec2011 has no known optimum: a negative raw objective is NOT a sign failure.
        // Native dim in the filename (D6); the reference is dimensionless.
        write_file(refs / "cec2011" / "gsk" / "gsk_cec2011.csv",
                   hdr + "1,-1.0e+01,-5.0e+00,-5.0e+00,0.0e+00,3.0e+00\n");
        const fs::path c11 = tmp / "vc11";
        write_file(c11 / "gsk" / "cec2011" / "summary" / "gsk_cec2011_D6.csv",
                   hdr + "1,-9.0e+00,-4.0e+00,-4.0e+00,0.0e+00,3.0e+00\n");
        auto v_c11 = gskcec::classify_run(gskcec::load_summaries(c11), refs, false);
        check(v_c11.verdict == "CONSISTENT", "cec2011 negative objective is not a sign failure");

        const fs::path vjson = tmp / "verification.json";
        gskcec::write_verification_json(v_good, vjson);
        check(fs::exists(vjson), "verification.json written");
    }

    fs::remove_all(tmp);
    if (failures == 0) {
        std::cout << "experiment_tests passed\n";
        return 0;
    }
    std::cerr << failures << " failure(s)\n";
    return 1;
}
