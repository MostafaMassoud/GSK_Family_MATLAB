// Tests for the experiment config parser, seed parsing, the reduced-protocol
// rule, and the helpers that load summaries, compare them with reference
// tables and give the post-run verification verdict.

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

int main(int argc, char** argv) {
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
        check(cfg.np_init == 0 && cfg.min_pop_size == 0, "default np_init/min_pop_size are 0 (optimizer defaults)");
    }
    // --- Population size keys ---------------------------------------------
    {
        const fs::path pop = tmp / "pop.yml";
        write_file(pop, "optimizers: [gsk]\nsuite: cec2017\nnp_init: 100\nmin_pop_size: 20\n");
        const auto cfg = gskcec::load_experiment_config(pop);
        check(cfg.np_init == 100 && cfg.min_pop_size == 20, "np_init/min_pop_size parsed");
        const fs::path pop0 = tmp / "pop0.yml";
        write_file(pop0, "optimizers: [gsk]\nsuite: cec2017\nnp_init: 0\nmin_pop_size: 0\n");
        const auto cfg0 = gskcec::load_experiment_config(pop0);
        check(cfg0.np_init == 0 && cfg0.min_pop_size == 0, "np_init/min_pop_size 0 = default accepted");
        for (const char* bad : {"np_init: 11", "np_init: -1", "np_init: 1.5", "np_init: all",
                                "min_pop_size: 10", "min_pop_size: -3", "min_pop_size: 12x"}) {
            const fs::path bad_pop = tmp / "bad_pop.yml";
            write_file(bad_pop, std::string("optimizers: [gsk]\nsuite: cec2017\n") + bad + "\n");
            check(throws([&] { gskcec::load_experiment_config(bad_pop); }),
                  std::string("config '") + bad + "' rejected");
        }
        check(gskcec::is_valid_np_init(0) && gskcec::is_valid_np_init(12) && !gskcec::is_valid_np_init(11),
              "is_valid_np_init floor 12");
        check(gskcec::is_valid_min_pop_size(0) && gskcec::is_valid_min_pop_size(11) &&
                  !gskcec::is_valid_min_pop_size(10),
              "is_valid_min_pop_size floor 11");
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

        // An empty list is not a synonym for `all`.
        const fs::path empty_funcs = tmp / "empty_funcs.yml";
        write_file(empty_funcs, "optimizers: [gsk]\nsuite: cec2017\nfunctions: []\ndimensions: [10]\n");
        check(throws([&] { gskcec::load_experiment_config(empty_funcs); }), "functions: [] rejected");
        const fs::path empty_dims = tmp / "empty_dims.yml";
        write_file(empty_dims, "optimizers: [gsk]\nsuite: cec2017\ndimensions: []\n");
        check(throws([&] { gskcec::load_experiment_config(empty_dims); }), "dimensions: [] rejected");

        // data_root is rejected: MATLAB has no such input, so it could never
        // take effect.
        const fs::path data_root = tmp / "data_root.yml";
        write_file(data_root, "optimizers: [gsk]\nsuite: cec2017\ndata_root: benchmarks/cec_suite_cpp\n");
        check(throws([&] { gskcec::load_experiment_config(data_root); }), "data_root rejected explicitly");

        // A leading UTF-8 BOM (PowerShell 5.1 -Encoding utf8) is tolerated; a
        // BOM anywhere else is still an error.
        const fs::path bom = tmp / "bom.yml";
        write_file(bom, "\xEF\xBB\xBFoptimizers: [gsk]\nsuite: cec2017\n");
        const auto bom_cfg = gskcec::load_experiment_config(bom);
        check(bom_cfg.optimizers == std::vector<std::string>({"gsk"}) && bom_cfg.suite == "cec2017",
              "leading UTF-8 BOM tolerated");
        const fs::path mid_bom = tmp / "mid_bom.yml";
        write_file(mid_bom, "optimizers: [gsk]\n\xEF\xBB\xBFsuite: cec2017\n");
        check(throws([&] { gskcec::load_experiment_config(mid_bom); }), "BOM after line 1 rejected");
    }

    // --- Seed parsing (config file and gsk_run --seed share it) ----------
    {
        check(gskcec::parse_seed_value("20240620") == 20240620ULL, "seed 20240620 parsed");
        check(gskcec::parse_seed_value("0") == 0ULL, "seed 0 accepted");
        check(gskcec::parse_seed_value("9007199254740992") == 9007199254740992ULL, "seed 2^53 accepted");
        for (const char* bad : {"-5", "+5", "", " 5", "12abc", "1.5", "9007199254740993",
                                "18446744073709551611", "99999999999999999999999"}) {
            check(throws([&] { gskcec::parse_seed_value(bad); }),
                  std::string("seed '") + bad + "' rejected");
        }
        const fs::path neg_seed = tmp / "neg_seed.yml";
        write_file(neg_seed, "optimizers: [gsk]\nsuite: cec2017\nseed: -5\n");
        check(throws([&] { gskcec::load_experiment_config(neg_seed); }),
              "config seed: -5 rejected (no wrap to 2^64-5)");
        const fs::path junk_seed = tmp / "junk_seed.yml";
        write_file(junk_seed, "optimizers: [gsk]\nsuite: cec2017\nseed: 12abc\n");
        check(throws([&] { gskcec::load_experiment_config(junk_seed); }), "config seed: 12abc rejected");
    }

    // --- Shared reduced-protocol rule (gsk_run and gsk_validate --verify) ---
    {
        check(!gskcec::is_reduced_protocol(25, 0), "25 runs, default budget -> full protocol");
        check(!gskcec::is_reduced_protocol(51, 0), "51 runs, default budget -> full protocol");
        check(gskcec::is_reduced_protocol(24, 0), "24 runs -> reduced");
        check(gskcec::is_reduced_protocol(51, 150000), "budget override -> reduced");
        check(gskcec::is_reduced_protocol(51, 0, true), "population override -> reduced");
        check(!gskcec::is_reduced_protocol(51, 0, false), "no population override -> full protocol");

        // run_experiment writes np_init/min_pop_size as [] when unset.
        const fs::path env_pop_unset = tmp / "env_pop_unset.json";
        write_file(env_pop_unset, "{\"runs\":51,\"max_nfes_override\":0,\"np_init\":[],\"min_pop_size\":[]}");
        const auto r_unset = gskcec::reduced_protocol_from_environment(env_pop_unset);
        check(r_unset.has_value() && !*r_unset, "environment.json with unset np_init/min_pop_size -> full");
        const fs::path env_np = tmp / "env_np.json";
        write_file(env_np, "{\"runs\":51,\"max_nfes_override\":0,\"np_init\":100,\"min_pop_size\":[]}");
        const auto r_np = gskcec::reduced_protocol_from_environment(env_np);
        check(r_np.has_value() && *r_np, "environment.json with np_init = 100 -> reduced");
        const fs::path env_min = tmp / "env_min.json";
        write_file(env_min, "{\"runs\":51,\"max_nfes_override\":0,\"np_init\":[],\"min_pop_size\":20}");
        const auto r_min = gskcec::reduced_protocol_from_environment(env_min);
        check(r_min.has_value() && *r_min, "environment.json with min_pop_size = 20 -> reduced");

        const fs::path env_pretty = tmp / "env_pretty.json";
        write_file(env_pretty, "{\n  \"optimizer\": \"gsk\",\n  \"dimensions_run\": [\n    10\n  ],\n"
                               "  \"runs\": 1,\n  \"base_seed\": 2.024062E+7,\n"
                               "  \"max_nfes_override\": 3000\n}\n");
        const auto r_pretty = gskcec::reduced_protocol_from_environment(env_pretty);
        check(r_pretty.has_value() && *r_pretty, "environment.json runs=1/override=3000 -> reduced");
        const fs::path env_full = tmp / "env_full.json";
        // MATLAB jsonencode writes some integers in E notation (1.0E+2 = 100).
        write_file(env_full, "{\"runs\":1.0E+2,\"max_nfes_override\":0}");
        const auto r_full = gskcec::reduced_protocol_from_environment(env_full);
        check(r_full.has_value() && !*r_full, "environment.json runs=1.0E+2/override=0 -> full");
        const fs::path env_partial = tmp / "env_partial.json";
        write_file(env_partial, "{\"runs\": 51}");
        check(!gskcec::reduced_protocol_from_environment(env_partial).has_value(),
              "environment.json without max_nfes_override -> no answer");
        check(!gskcec::reduced_protocol_from_environment(tmp / "no_env.json").has_value(),
              "missing environment.json -> no answer");
    }

    // --- Shipped configs (needs the project root as argv[1]) -------------
    if (argc > 1) {
        const fs::path configs = fs::path(argv[1]) / "configs";
        for (const char* name : {"smoke.yml", "all_cec2017.yml", "all_cec2011.yml", "agsk_cec2020.yml"}) {
            check(!throws([&] { gskcec::load_experiment_config(configs / name); }),
                  std::string("shipped config parses: ") + name);
        }
        // The full campaign configs must count as full protocol (a gross
        // deviation is then a hard failure); only smoke.yml is reduced.
        for (const char* name : {"all_cec2017.yml", "all_cec2011.yml", "agsk_cec2020.yml"}) {
            const auto cfg = gskcec::load_experiment_config(configs / name);
            check(!gskcec::is_reduced_protocol(cfg.runs, cfg.max_evaluations,
                                               cfg.np_init != 0 || cfg.min_pop_size != 0),
                  std::string("full-protocol config is not classified reduced: ") + name);
        }
        const auto smoke = gskcec::load_experiment_config(configs / "smoke.yml");
        check(gskcec::is_reduced_protocol(smoke.runs, smoke.max_evaluations), "smoke.yml is reduced");
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
        // Archived results (_overwrite_archive trees moved by overwrite=true,
        // summary/_archive copies from per-file refreshes) must not be loaded
        // as extra runs when scanning a results root.
        const std::string arch_table = "Function,Best,Median,Mean,Worst,SD\n9,9,9,9,9,9\n";
        write_file(tmp / "results" / "gsk" / "_overwrite_archive" / "cec2017_2026-06-27_17.49.03" /
                       "summary" / "gsk_cec2017_D10.csv",
                   arch_table);
        write_file(summary / "_archive" / "2026-06-27_17.49.03" / "summary" / "gsk_cec2017_D10.csv",
                   arch_table);
        const auto rows = gskcec::load_summaries(tmp / "results");
        check(rows.size() == 3, "summary rows loaded (rollup + per_run + archives ignored)");
        check(rows[0].optimizer == "gsk" && rows[0].suite == "cec2017" && rows[0].dimension == 10,
              "optimizer/suite/dimension parsed from the file name");
        // Pointing the loader directly at an archived tree still works.
        const auto archived = gskcec::load_summaries(tmp / "results" / "gsk" / "_overwrite_archive" /
                                                     "cec2017_2026-06-27_17.49.03");
        check(archived.size() == 1 && archived[0].function_id == 9 && archived[0].suite == "cec2017",
              "an archived tree loads when given as the root");

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

    // --- Post-run verification verdict ----------------------------------
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

        // Negative error on a suite with a known optimum -> DEVIATES (it beats
        // the optimum). The mean stays close to the 1e-7 reference, so only
        // the sign check fails, not the gross check.
        const fs::path negrun = tmp / "vneg";
        write_file(negrun / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "1,-5.0e+00,2.0e-08,3.0e-08,4.0e-08,1.0e-08\n");
        auto v_neg = gskcec::classify_run(gskcec::load_summaries(negrun), refs, false);
        check(v_neg.verdict == "DEVIATES", "negative best error -> DEVIATES");
        check(v_neg.checks.size() == 1 && !v_neg.checks[0].sign_ok &&
                  v_neg.checks[0].magnitude_ok && v_neg.checks[0].finite_ok,
              "negative best error fails the sign check alone");
        check(v_neg.checks.size() == 1 && v_neg.checks[0].failures.size() == 1 &&
                  v_neg.checks[0].failures[0].find("-1e-06") != std::string::npos,
              "sign-failure reason prints the floor legibly (-1e-06, not -0.000001)");

        // Gross deviation: hard failure at full protocol, informational when reduced.
        const fs::path grossrun = tmp / "vgross";
        write_file(grossrun / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "3,5.0e+02,6.0e+02,9.0e+12,9.0e+12,1.0e+02\n");
        auto v_full = gskcec::classify_run(gskcec::load_summaries(grossrun), refs, /*reduced=*/false);
        check(v_full.verdict == "DEVIATES", "gross deviation at full protocol -> DEVIATES");
        auto v_red = gskcec::classify_run(gskcec::load_summaries(grossrun), refs, /*reduced=*/true);
        check(v_red.verdict == "CONSISTENT", "same gross gap under reduced budget -> informational");

        // A small non-trivial reference must not print as 0.000000.
        const fs::path smallref = tmp / "vsmallref";
        write_file(smallref / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "1,1.0e-08,1.0e+00,1.0e+00,2.0e+00,1.0e+00\n");
        auto v_small = gskcec::classify_run(gskcec::load_summaries(smallref), refs, false);
        check(v_small.checks.size() == 1 && !v_small.checks[0].magnitude_ok &&
                  v_small.checks[0].failures.size() == 1 &&
                  v_small.checks[0].failures[0].find("reference 1e-07") != std::string::npos &&
                  v_small.checks[0].failures[0].find("0.000000") == std::string::npos,
              "gross-failure reason prints the 1e-07 reference legibly");

        // Non-standard output_dir (README demo layout results/demo/summary):
        // optimizer/suite come from the file name, so the cec2017 rules apply.
        const fs::path demo = tmp / "vdemo" / "results" / "demo";
        write_file(demo / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "1,-5.0e+00,1.0e+00,1.0e+00,2.0e+00,1.0e+00\n"
                         "3,5.0e+02,6.0e+02,9.0e+12,9.0e+12,1.0e+02\n");
        auto v_demo = gskcec::classify_run(gskcec::load_summaries(demo), refs, false);
        check(v_demo.optimizer == "gsk" && v_demo.suite == "cec2017", "demo layout: names from the file");
        check(v_demo.verdict == "DEVIATES" && v_demo.hard_failures == 2 && v_demo.missing_reference == 0,
              "demo layout: sign and gross checks both run");

        // Mixed directory: every row is judged under its own suite and
        // against its own (optimizer, suite, function, dimension) reference.
        const fs::path mixed = tmp / "vmixed";
        write_file(mixed / "gsk" / "cec2011" / "summary" / "gsk_cec2011_D6.csv",
                   hdr + "1,-9.0e+00,-4.0e+00,-4.0e+00,0.0e+00,3.0e+00\n");
        write_file(mixed / "gsk" / "cec2017" / "summary" / "gsk_cec2017_D10.csv",
                   hdr + "1,-5.0e+00,2.0e-08,3.0e-08,4.0e-08,1.0e-08\n"
                         "3,5.0e+02,6.0e+02,7.0e+02,8.0e+02,1.0e+02\n");
        // agsk has no reference table: its F3 must not be gross-checked
        // against gsk's F3 reference (same function and dimension), even
        // when the gsk rows come first.
        write_file(mixed / "agsk" / "cec2017" / "summary" / "agsk_cec2017_D10.csv",
                   hdr + "3,5.0e+02,6.0e+02,9.0e+12,9.0e+12,1.0e+02\n");
        auto mixed_rows = gskcec::load_summaries(mixed / "gsk");
        const auto agsk_rows = gskcec::load_summaries(mixed / "agsk");
        mixed_rows.insert(mixed_rows.end(), agsk_rows.begin(), agsk_rows.end());
        auto v_mixed = gskcec::classify_run(mixed_rows, refs, false);
        int sign_failures = 0;
        int gross_failures = 0;
        for (const auto& c : v_mixed.checks) {
            sign_failures += c.sign_ok ? 0 : 1;
            gross_failures += c.magnitude_ok ? 0 : 1;
        }
        check(v_mixed.checks.size() == 4 && sign_failures == 1 && gross_failures == 0,
              "mixed dir: only the cec2017 negative row fails; no cross-optimizer gross match");
        check(v_mixed.suite.find("cec2011") != std::string::npos &&
                  v_mixed.suite.find("cec2017") != std::string::npos &&
                  v_mixed.optimizer.find("agsk") != std::string::npos,
              "mixed dir: verdict names every optimizer and suite");

        // cec2011 has no known optimum: a negative raw objective is NOT a sign failure.
        // The summary file name has the native D (D6); the reference has no D.
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
