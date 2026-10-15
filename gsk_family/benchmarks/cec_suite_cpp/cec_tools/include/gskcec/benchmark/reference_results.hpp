#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace gskcec {

/// One row of an imported reference table. A missing statistic is
/// std::nullopt.
struct ReferenceResultRow {
    int function_id = 0;
    std::optional<Real> best;
    std::optional<Real> median;
    std::optional<Real> mean;
    std::optional<Real> worst;
    std::optional<Real> sd;
    std::filesystem::path source_file;
    std::string provenance = "imported_reference";
};

struct ReferenceFile {
    std::filesystem::path path;
    std::vector<ReferenceResultRow> rows;
};

/// Parses a function label such as "F3", "f3" or "3" into a positive id.
/// @throws std::runtime_error for an empty or invalid label.
int normalize_function_id(std::string label);
/// Reads one reference table: the first non-blank line is the header and
/// must have a Function column (any case); then comma- or
/// whitespace-separated rows. Rows with an empty Function cell are skipped.
/// Empty, "-", NaN, N/A and NA cells (any case) become std::nullopt.
/// @throws std::runtime_error when the file cannot be opened, has no
///         Function column, or has a bad row (naming the file and line).
std::vector<ReferenceResultRow> load_reference_file(const std::filesystem::path& path);
/// Loads the .csv/.txt summary tables directly under cec*/<optimizer>/
/// below @p root, sorted by path. Deeper files, such as curves and
/// generation logs, are skipped.
/// @throws std::runtime_error when @p root does not exist.
std::vector<ReferenceFile> load_reference_tree(const std::filesystem::path& root);

} // namespace gskcec
