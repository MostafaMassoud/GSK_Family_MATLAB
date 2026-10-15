#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace gskcec {

/// One row of a per-dimension summary table written by a run
/// (results/<optimizer>/<suite>/summary/<optimizer>_<suite>_D<dim>.csv;
/// see docs/reference/result_schema.md).
struct SummaryRow {
    std::string optimizer;
    std::string suite;
    int function_id = 0;
    int dimension = 0;
    int runs = 0; ///< Not stored in the summary file; load_summaries leaves it 0.
    Real best = 0.0;
    Real median = 0.0;
    Real mean = 0.0;
    Real worst = 0.0;
    Real sd = 0.0;
    std::filesystem::path source_file;
};

/// Loads every per-dimension summary table (summary/<opt>_<suite>_D<dim>.csv)
/// below @p results_root, searching subfolders. Optimizer, suite and
/// dimension come from the file name, not the folder names. The rollup
/// table without a dimension and per_run.csv are skipped, and the runner's
/// archive folders (`_overwrite_archive/`, `_archive/`) below
/// @p results_root are not searched.
/// @throws std::runtime_error when @p results_root does not exist, or
///         naming the file and line on a schema problem.
std::vector<SummaryRow> load_summaries(const std::filesystem::path& results_root);

/// Comparison of one generated row with one imported reference row.
struct ComparisonEntry {
    std::string optimizer;
    std::string suite;
    int function_id = 0;
    int dimension = 0;
    Real generated_mean = 0.0;
    std::optional<Real> reference_mean;
    std::optional<Real> abs_diff;
    std::optional<Real> rel_diff;   ///< abs_diff / max(1, |reference|).
    std::string verdict;            ///< "win" | "tie" | "loss" | "no_reference".
};

/// All comparison entries plus their win/tie/loss and missing-reference
/// counts.
struct ComparisonReport {
    std::vector<ComparisonEntry> entries;
    int wins = 0;
    int ties = 0;
    int losses = 0;
    int missing_reference = 0;
};

/// Compares generated summaries with the imported reference tables.
///
/// Reference files are matched by (suite, algorithm, dimension) taken from
/// their paths (e.g. cec2017/agsk/agsk_cec2017_D10.csv). A file without a
/// _D<dim> tag (e.g. CEC2011) serves any dimension with no exact match.
/// The generated optimizer name is used as-is: summary file names carry
/// run_experiment's hyphenated slug (`atmals-gsk`, `fdb-agsk`), which is
/// also the reference folder name. Returns exactly one entry per generated
/// row, in input order. The verdict compares means (lower is better); a
/// relative difference <= 1e-8 is a tie.
ComparisonReport compare_with_references(const std::vector<SummaryRow>& generated,
                                         const std::filesystem::path& reference_root);

/// Writes the report to @p out_path as CSV, one row per entry.
void write_comparison_csv(const ComparisonReport& report, const std::filesystem::path& out_path);

// --- Post-run verification ---------------------------------------------------

/// Thresholds for the post-run verdict.
struct VerificationThresholds {
    /// A best error below this (suites with a known optimum) means the
    /// optimizer "beat" the known optimum, which a correct one cannot do.
    Real negative_error_floor = -1.0e-6;
    /// A generated mean above gross_factor x |reference mean| (non-trivial
    /// references only) flags a gross implementation error. Hard failure
    /// only for full-protocol runs; informational under a reduced budget.
    Real gross_factor = 1.0e6;
    /// Reference means with magnitude <= this count as trivial (e.g. a
    /// converged 0); the gross check skips them.
    Real reference_trivial_floor = 1.0e-8;
};

/// Per-function result of the verification checks.
struct FunctionCheck {
    int function_id = 0;
    int dimension = 0;
    bool finite_ok = true;          ///< all generated statistics are finite
    bool sign_ok = true;            ///< no impossible negative error
    bool magnitude_ok = true;       ///< not grossly worse than reference (full protocol only)
    std::vector<std::string> failures; ///< reasons for failed checks, plus informational notes
};

/// Verdict for a whole optimizer/suite run.
struct RunVerification {
    std::string optimizer;          ///< comma-joined if the input mixes several
    std::string suite;              ///< comma-joined if the input mixes several
    std::string verdict;            ///< "CONSISTENT", or "DEVIATES" when hard_failures > 0
    /// Win/tie/loss never causes a hard failure. This flag only makes the
    /// gross-deviation check informational, because a reduced-budget run
    /// is expected to be worse than the published table.
    bool reduced_budget = false;
    int functions_checked = 0;
    int hard_failures = 0;
    int wins = 0;
    int ties = 0;
    int losses = 0;
    int missing_reference = 0;
    VerificationThresholds thresholds;
    std::vector<FunctionCheck> checks;
};

/// True for suites with known optima (cec2013, cec2017, cec2020), where
/// errors are meaningful and the sign check applies. False for cec2011 and
/// cec2013lsgo, whose reference tables report raw objective values.
bool suite_has_known_optimum(const std::string& suite);

/// Reduced-protocol rule shared by gsk_run and gsk_validate --verify: a run
/// is reduced when its budget was overridden (@p max_nfes_override != 0) or
/// it has fewer than 25 runs.
bool is_reduced_protocol(long long runs, long long max_nfes_override);

/// Reads `runs` and `max_nfes_override` from a run's environment.json
/// (written by run_experiment.m) and applies is_reduced_protocol. Returns
/// std::nullopt when the file cannot be read or lacks either field.
std::optional<bool> reduced_protocol_from_environment(const std::filesystem::path& environment_json);

/// Checks one run's summaries against the imported references.
///
/// @param generated      summary rows, normally from one optimizer/suite run;
///                       each row is judged by its own suite's rules and
///                       against its own reference row.
/// @param reference_root imported reference table tree.
/// @param reduced_budget true when the run used a reduced (non-reference)
///                       budget; the gross-deviation check is then
///                       informational. Win/tie/loss is always informational.
RunVerification classify_run(const std::vector<SummaryRow>& generated,
                             const std::filesystem::path& reference_root,
                             bool reduced_budget,
                             const VerificationThresholds& thresholds = {});

/// Writes the verdict as JSON to @p out_path (e.g. <run_dir>/verification.json).
void write_verification_json(const RunVerification& verification,
                             const std::filesystem::path& out_path);

} // namespace gskcec
