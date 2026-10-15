#pragma once

#include "gskcec/core/types.hpp"

#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace gskcec {

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

int normalize_function_id(std::string label);
std::vector<ReferenceResultRow> load_reference_file(const std::filesystem::path& path);
/// Loads imported summary tables under cec*/<optimizer>/ and skips auxiliary
/// nested artifacts such as curves and generation logs.
std::vector<ReferenceFile> load_reference_tree(const std::filesystem::path& root);

} // namespace gskcec
