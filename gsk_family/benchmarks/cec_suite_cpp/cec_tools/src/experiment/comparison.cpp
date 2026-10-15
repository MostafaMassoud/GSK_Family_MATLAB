#include "gskcec/experiment/comparison.hpp"

#include "gskcec/benchmark/reference_results.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <map>
#include <sstream>
#include <stdexcept>

namespace gskcec {

namespace {

std::vector<std::string> split_csv_line(const std::string& line) {
    std::vector<std::string> fields;
    std::stringstream ss(line);
    std::string field;
    while (std::getline(ss, field, ',')) {
        fields.push_back(field);
    }
    return fields;
}

Real parse_real(const std::filesystem::path& file, std::size_t line_no, const std::string& token) {
    try {
        std::size_t consumed = 0;
        const Real v = std::stod(token, &consumed);
        if (consumed != token.size()) {
            throw std::invalid_argument(token);
        }
        return v;
    } catch (const std::exception&) {
        throw std::runtime_error("Bad numeric field '" + token + "' at " + file.string() + ":" +
                                 std::to_string(line_no));
    }
}

/// Optimizer name -> reference algorithm folder/file token.
std::string reference_algorithm_name(const std::string& optimizer) {
    if (optimizer == "atmals-gsk") {
        return "atmals-gsk";
    }
    if (optimizer == "fdb-agsk") {
        return "fdb-agsk";
    }
    return optimizer;
}

struct ReferenceKey {
    std::string suite;
    std::string algorithm;
    int dimension = 0; // 0 = file without a dimension tag (cec2011, cec2013lsgo)

    bool operator<(const ReferenceKey& other) const {
        return std::tie(suite, algorithm, dimension) <
               std::tie(other.suite, other.algorithm, other.dimension);
    }
};

/// Parses suite/algorithm/dimension from an imported reference file path,
/// e.g. .../cec2017/agsk/agsk_cec2017_D10.csv or .../cec2011/gsk/gsk_cec2011.csv.
std::optional<ReferenceKey> parse_reference_path(const std::filesystem::path& path) {
    const auto parent = path.parent_path();
    const auto algorithm = parent.filename().string();
    const auto suite = parent.parent_path().filename().string();
    if (suite.rfind("cec", 0) != 0) {
        return std::nullopt;
    }
    ReferenceKey key{suite, algorithm, 0};
    const std::string stem = path.stem().string();
    const auto dpos = stem.rfind("_D");
    if (dpos != std::string::npos) {
        try {
            key.dimension = std::stoi(stem.substr(dpos + 2));
        } catch (const std::exception&) {
            key.dimension = 0;
        }
    }
    return key;
}

} // namespace

namespace {

// Lower-cases an ASCII string (header matching only).
std::string lower(std::string s) {
    for (char& c : s) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

// A per-dimension summary file is <optimizer>_<suite>_D<dim>.csv inside a
// folder named "summary" within results/<optimizer>/<suite>/. Returns false
// for the dimensionless rollup, per_run.csv, environment.json, etc.
bool parse_summary_path(const std::filesystem::path& path, std::string& optimizer,
                        std::string& suite, int& dimension) {
    if (path.extension() != ".csv") {
        return false;
    }
    if (path.parent_path().filename() != "summary") {
        return false;
    }
    const std::string stem = path.stem().string();
    const auto dpos = stem.rfind("_D");
    if (dpos == std::string::npos) {
        return false; // rollup / per_run / other
    }
    try {
        std::size_t consumed = 0;
        dimension = std::stoi(stem.substr(dpos + 2), &consumed);
        if (consumed != stem.size() - dpos - 2) {
            return false;
        }
    } catch (const std::exception&) {
        return false;
    }
    // .../<optimizer>/<suite>/summary/<file>
    const auto suite_dir = path.parent_path().parent_path();
    const auto optimizer_dir = suite_dir.parent_path();
    suite = suite_dir.filename().string();
    optimizer = optimizer_dir.filename().string();
    return !suite.empty() && !optimizer.empty();
}

} // namespace

std::vector<SummaryRow> load_summaries(const std::filesystem::path& results_root) {
    if (!std::filesystem::exists(results_root)) {
        throw std::runtime_error("Results root does not exist: " + results_root.string());
    }
    std::vector<SummaryRow> rows;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(results_root)) {
        if (!entry.is_regular_file()) {
            continue;
        }
        std::string optimizer;
        std::string suite;
        int dimension = 0;
        if (!parse_summary_path(entry.path(), optimizer, suite, dimension)) {
            continue;
        }
        std::ifstream in(entry.path());
        if (!in) {
            throw std::runtime_error("Cannot open " + entry.path().string());
        }
        // Header: Function,Best,Median,Mean,Worst,SD (case-insensitive); locate
        // each statistic column so column order is not assumed.
        std::string line;
        std::size_t line_no = 0;
        std::size_t c_func = 0, c_best = 1, c_median = 2, c_mean = 3, c_worst = 4, c_sd = 5;
        bool have_header = false;
        while (std::getline(in, line)) {
            ++line_no;
            if (line.empty() || line[0] == '#') {
                continue;
            }
            const auto f = split_csv_line(line);
            if (!have_header) {
                for (std::size_t i = 0; i < f.size(); ++i) {
                    const std::string h = lower(f[i]);
                    if (h == "function") c_func = i;
                    else if (h == "best") c_best = i;
                    else if (h == "median") c_median = i;
                    else if (h == "mean") c_mean = i;
                    else if (h == "worst") c_worst = i;
                    else if (h == "sd") c_sd = i;
                }
                have_header = true;
                continue;
            }
            if (f.size() <= std::max({c_func, c_best, c_median, c_mean, c_worst, c_sd})) {
                throw std::runtime_error("summary row has " + std::to_string(f.size()) +
                                         " fields at " + entry.path().string() + ":" +
                                         std::to_string(line_no));
            }
            SummaryRow row;
            row.optimizer = optimizer;
            row.suite = suite;
            row.function_id = normalize_function_id(f[c_func]);
            row.dimension = dimension;
            row.runs = 0; // not stored in the CEC-style summary; see summary/per_run.csv
            row.best = parse_real(entry.path(), line_no, f[c_best]);
            row.median = parse_real(entry.path(), line_no, f[c_median]);
            row.mean = parse_real(entry.path(), line_no, f[c_mean]);
            row.worst = parse_real(entry.path(), line_no, f[c_worst]);
            row.sd = parse_real(entry.path(), line_no, f[c_sd]);
            row.source_file = entry.path();
            rows.push_back(std::move(row));
        }
    }
    return rows;
}

ComparisonReport compare_with_references(const std::vector<SummaryRow>& generated,
                                         const std::filesystem::path& reference_root) {
    const auto files = load_reference_tree(reference_root);
    std::map<ReferenceKey, const ReferenceFile*> by_key;
    for (const auto& file : files) {
        if (const auto key = parse_reference_path(file.path)) {
            by_key[*key] = &file;
        }
    }

    ComparisonReport report;
    for (const auto& g : generated) {
        ComparisonEntry entry;
        entry.optimizer = g.optimizer;
        entry.suite = g.suite;
        entry.function_id = g.function_id;
        entry.dimension = g.dimension;
        entry.generated_mean = g.mean;

        const ReferenceFile* ref = nullptr;
        for (const int dim : {g.dimension, 0}) {
            const auto it = by_key.find(ReferenceKey{g.suite, reference_algorithm_name(g.optimizer), dim});
            if (it != by_key.end()) {
                ref = it->second;
                break;
            }
        }
        const ReferenceResultRow* ref_row = nullptr;
        if (ref != nullptr) {
            for (const auto& row : ref->rows) {
                if (row.function_id == g.function_id) {
                    ref_row = &row;
                    break;
                }
            }
        }
        if (ref_row == nullptr || !ref_row->mean.has_value()) {
            entry.verdict = "no_reference";
            ++report.missing_reference;
        } else {
            const Real ref_mean = *ref_row->mean;
            entry.reference_mean = ref_mean;
            entry.abs_diff = std::abs(g.mean - ref_mean);
            entry.rel_diff = *entry.abs_diff / std::max<Real>(1.0, std::abs(ref_mean));
            if (*entry.rel_diff <= 1.0e-8) {
                entry.verdict = "tie";
                ++report.ties;
            } else if (g.mean < ref_mean) {
                entry.verdict = "win";
                ++report.wins;
            } else {
                entry.verdict = "loss";
                ++report.losses;
            }
        }
        report.entries.push_back(std::move(entry));
    }
    return report;
}

void write_comparison_csv(const ComparisonReport& report, const std::filesystem::path& out_path) {
    std::ofstream out(out_path);
    if (!out) {
        throw std::runtime_error("Cannot open comparison output file: " + out_path.string());
    }
    out << "optimizer,suite,function,dimension,generated_mean,reference_mean,abs_diff,rel_diff,verdict\n";
    out.precision(10);
    out << std::scientific;
    for (const auto& e : report.entries) {
        out << e.optimizer << ',' << e.suite << ',' << e.function_id << ',' << e.dimension << ','
            << e.generated_mean << ',';
        if (e.reference_mean) {
            out << *e.reference_mean;
        }
        out << ',';
        if (e.abs_diff) {
            out << *e.abs_diff;
        }
        out << ',';
        if (e.rel_diff) {
            out << *e.rel_diff;
        }
        out << ',' << e.verdict << '\n';
    }
}

bool suite_has_known_optimum(const std::string& suite) {
    // cec2011 reports raw objectives (no published optima); cec2013lsgo optima
    // are 0 by construction but the imported DECC-G/MOS tables report raw
    // objectives, so the sign check is not meaningful there either.
    return suite == "cec2017" || suite == "cec2020" || suite == "cec2013";
}

RunVerification classify_run(const std::vector<SummaryRow>& generated,
                             const std::filesystem::path& reference_root,
                             bool reduced_budget,
                             const VerificationThresholds& thresholds) {
    RunVerification v;
    v.reduced_budget = reduced_budget;
    v.thresholds = thresholds;
    if (!generated.empty()) {
        v.optimizer = generated.front().optimizer;
        v.suite = generated.front().suite;
    }

    // Reuse the existing reference alignment for win/tie/loss and ref means.
    const ComparisonReport report = compare_with_references(generated, reference_root);
    v.wins = report.wins;
    v.ties = report.ties;
    v.losses = report.losses;
    v.missing_reference = report.missing_reference;

    const bool known_optimum = suite_has_known_optimum(v.suite);

    for (std::size_t i = 0; i < generated.size(); ++i) {
        const SummaryRow& row = generated[i];
        FunctionCheck check;
        check.function_id = row.function_id;
        check.dimension = row.dimension;

        // (1) Finiteness: every reported statistic must be a real number.
        const std::pair<const char*, Real> stats[] = {
            {"best", row.best}, {"median", row.median}, {"mean", row.mean},
            {"worst", row.worst}, {"sd", row.sd}};
        for (const auto& [label, value] : stats) {
            if (!std::isfinite(value)) {
                check.finite_ok = false;
                check.failures.push_back(std::string("non-finite ") + label);
            }
        }

        // (2) Sign: a best error below the floor means the optimizer beat the
        // known optimum, which a correct implementation cannot do.
        if (known_optimum && row.best < thresholds.negative_error_floor) {
            check.sign_ok = false;
            check.failures.push_back("best error " + std::to_string(row.best) +
                                     " below floor " + std::to_string(thresholds.negative_error_floor) +
                                     " (beats the known optimum)");
        }

        // (3) Gross deviation vs a non-trivial reference mean. A hard failure
        // only at full protocol; under a reduced budget a large gap is the
        // expected consequence of fewer evaluations, so it is informational.
        const ComparisonEntry* entry = nullptr;
        for (const auto& e : report.entries) {
            if (e.function_id == row.function_id && e.dimension == row.dimension) {
                entry = &e;
                break;
            }
        }
        if (entry != nullptr && entry->reference_mean.has_value()) {
            const Real ref_mean = *entry->reference_mean;
            if (std::abs(ref_mean) > thresholds.reference_trivial_floor &&
                row.mean > thresholds.gross_factor * std::abs(ref_mean)) {
                if (reduced_budget) {
                    check.failures.push_back("mean " + std::to_string(row.mean) + " >> reference " +
                                             std::to_string(ref_mean) +
                                             " (informational: reduced budget)");
                } else {
                    check.magnitude_ok = false;
                    check.failures.push_back("mean " + std::to_string(row.mean) + " exceeds " +
                                             std::to_string(thresholds.gross_factor) +
                                             "x reference " + std::to_string(ref_mean));
                }
            }
        }

        const bool hard_fail = !check.finite_ok || !check.sign_ok || !check.magnitude_ok;
        if (hard_fail) {
            ++v.hard_failures;
        }
        ++v.functions_checked;
        v.checks.push_back(std::move(check));
    }

    v.verdict = (v.hard_failures == 0) ? "CONSISTENT" : "DEVIATES";
    return v;
}

void write_verification_json(const RunVerification& v, const std::filesystem::path& out_path) {
    std::ofstream out(out_path);
    if (!out) {
        throw std::runtime_error("Cannot open verification output file: " + out_path.string());
    }
    out.precision(10);
    out << std::scientific;
    out << "{\n";
    out << "  \"optimizer\": \"" << v.optimizer << "\",\n";
    out << "  \"suite\": \"" << v.suite << "\",\n";
    out << "  \"verdict\": \"" << v.verdict << "\",\n";
    out << "  \"reduced_budget\": " << (v.reduced_budget ? "true" : "false") << ",\n";
    out << "  \"functions_checked\": " << v.functions_checked << ",\n";
    out << "  \"hard_failures\": " << v.hard_failures << ",\n";
    out << "  \"win_tie_loss\": [" << v.wins << ", " << v.ties << ", " << v.losses << "],\n";
    out << "  \"missing_reference\": " << v.missing_reference << ",\n";
    out << "  \"thresholds\": {\"negative_error_floor\": " << v.thresholds.negative_error_floor
        << ", \"gross_factor\": " << v.thresholds.gross_factor
        << ", \"reference_trivial_floor\": " << v.thresholds.reference_trivial_floor << "},\n";
    out << "  \"failures\": [";
    bool first = true;
    for (const auto& c : v.checks) {
        for (const auto& reason : c.failures) {
            // Only hard failures count toward the verdict; list them all here
            // (informational notes are suffixed in the reason text).
            if (!first) {
                out << ", ";
            }
            first = false;
            out << "\n    {\"function\": " << c.function_id << ", \"dimension\": " << c.dimension
                << ", \"reason\": \"" << reason << "\"}";
        }
    }
    out << (first ? "" : "\n  ") << "]\n";
    out << "}\n";
}

} // namespace gskcec
