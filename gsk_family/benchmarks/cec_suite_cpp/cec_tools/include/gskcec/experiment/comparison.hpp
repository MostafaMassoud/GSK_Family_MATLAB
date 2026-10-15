#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace gskcec {

/// One row of a generated per-dimension summary table
/// (results/<optimizer>/<suite>/summary/<optimizer>_<suite>_D<dim>.csv;
/// see docs/reference/result_schema.md).
struct SummaryRow {
    std::string optimizer;
    std::string suite;
    int function_id = 0;
    int dimension = 0;
    int runs = 0;
    Real best = 0.0;
    Real median = 0.0;
    Real mean = 0.0;
    Real worst = 0.0;
    Real sd = 0.0;
    std::filesystem::path source_file;
};

/// Loads every per-dimension summary table (summary/<opt>_<suite>_D<dim>.csv)
/// found below @p results_root (recursive); optimizer/suite come from the
/// path, the dimension from the filename. The dimensionless rollup and
/// per_run.csv are skipped.
/// @throws std::runtime_error naming file/line on schema problems.
std::vector<SummaryRow> load_summaries(const std::filesystem::path& results_root);

/// Comparison of one generated row against one imported reference row.
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

struct ComparisonReport {
    std::vector<ComparisonEntry> entries;
    int wins = 0;
    int ties = 0;
    int losses = 0;
    int missing_reference = 0;
};

/// Compares generated summaries against the imported reference tree.
///
/// Reference files are matched by (suite, algorithm, dimension) parsed
/// from their paths (e.g. cec2017/agsk/agsk_cec2017_D10.csv; CEC2011
/// files carry no dimension). Optimizer names are mapped to reference
/// algorithm folder names (`atmals-gsk`, `fdb-agsk`).
/// Win/tie/loss uses the mean statistic, lower is better, tie at
/// relative 1e-8.
ComparisonReport compare_with_references(const std::vector<SummaryRow>& generated,
                                         const std::filesystem::path& reference_root);

/// Writes the report as CSV (one entry per row) to @p out_path.
void write_comparison_csv(const ComparisonReport& report, const std::filesystem::path& out_path);

// --- Post-run verification (Mandate 1.1c / 3.1c) -----------------------------

/// Thresholds for the post-run verdict. Defaults match the prompt appendices.
struct VerificationThresholds {
    /// A best-error below this (known-optimum suites) means the optimizer
    /// "beat" the known optimum - impossible if implemented correctly.
    Real negative_error_floor = -1.0e-6;
    /// Generated mean above gross_factor x reference mean (when the reference
    /// is non-trivial) flags a gross implementation error. Applied as a hard
    /// failure only for full-protocol runs; informational under reduced budget.
    Real gross_factor = 1.0e6;
    /// Reference means with magnitude at/below this are treated as "trivial"
    /// (e.g. a converged 0), so the gross check is skipped for them.
    Real reference_trivial_floor = 1.0e-8;
};

/// Per-function outcome of the verification checks.
struct FunctionCheck {
    int function_id = 0;
    int dimension = 0;
    bool finite_ok = true;          ///< all generated statistics finite
    bool sign_ok = true;            ///< no impossible negative error
    bool magnitude_ok = true;       ///< not grossly worse than reference (full protocol only)
    std::vector<std::string> failures; ///< human-readable reasons when a check fails
};

/// Whole-run verdict produced after an optimizer/suite run.
struct RunVerification {
    std::string optimizer;
    std::string suite;
    std::string verdict;            ///< "CONSISTENT" or "DEVIATES"
    /// Win/tie/loss is always informational (never a hard failure). This flag
    /// only downgrades the gross-deviation check to informational, since a
    /// reduced-budget run is legitimately worse than the published table.
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

/// True for suites that have known optima (errors meaningful, sign check applies).
bool suite_has_known_optimum(const std::string& suite);

/// Classifies one run's summaries against the imported references.
///
/// @param generated     summary rows for a single optimizer/suite run.
/// @param reference_root imported reference table tree.
/// @param reduced_budget whether the run used a reduced (non-reference) budget;
///                       when true the gross-deviation check and win/tie/loss
///                       are informational rather than hard failures.
RunVerification classify_run(const std::vector<SummaryRow>& generated,
                             const std::filesystem::path& reference_root,
                             bool reduced_budget,
                             const VerificationThresholds& thresholds = {});

/// Writes the verdict as JSON to @p out_path (e.g. <run_dir>/verification.json).
void write_verification_json(const RunVerification& verification,
                             const std::filesystem::path& out_path);

} // namespace gskcec
