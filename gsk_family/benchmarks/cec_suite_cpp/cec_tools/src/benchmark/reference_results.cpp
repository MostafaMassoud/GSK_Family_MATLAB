#include "gskcec/benchmark/reference_results.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace gskcec {
namespace {

std::string trim(std::string value) {
    auto not_space = [](unsigned char c) { return !std::isspace(c); };
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), not_space));
    value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(), value.end());
    if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
        value = value.substr(1, value.size() - 2);
    }
    return value;
}

std::string lower_ascii(std::string value) {
    for (char& c : value) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return value;
}

std::vector<std::string> split_line(const std::string& line) {
    std::vector<std::string> cells;
    if (line.find(',') != std::string::npos) {
        std::stringstream ss(line);
        std::string cell;
        while (std::getline(ss, cell, ',')) {
            cells.push_back(trim(cell));
        }
    } else {
        std::stringstream ss(line);
        std::string cell;
        while (ss >> cell) {
            cells.push_back(trim(cell));
        }
    }
    return cells;
}

std::optional<Real> optional_real(const std::vector<std::string>& cells, Index index) {
    if (index >= cells.size()) {
        return std::nullopt;
    }
    const std::string cell = trim(cells[index]);
    // Markers for a missing statistic in the imported reference tables: an
    // empty cell, "-", NaN, N/A or NA (any case). The AGSK CEC2020 D=5 table
    // uses N/A for functions its source paper did not evaluate.
    const std::string lowered = lower_ascii(cell);
    if (cell.empty() || cell == "-" || lowered == "nan" || lowered == "n/a" || lowered == "na") {
        return std::nullopt;
    }
    try {
        return std::stod(cell);
    } catch (const std::exception&) {
        throw std::runtime_error("Invalid numeric reference value: '" + cell + "'.");
    }
}

std::optional<Index> column_index(const std::map<std::string, Index>& columns, const std::string& name) {
    const auto it = columns.find(name);
    if (it == columns.end()) {
        return std::nullopt;
    }
    return it->second;
}

bool is_reference_summary_path(const std::filesystem::path& path) {
    // Summary tables sit directly in cec*/<optimizer>/. Deeper CSV/TXT files
    // (e.g. curves/Figure_*.csv) are extra data without the
    // Function/Best/Median/Mean/Worst/SD columns, so they are skipped.
    const auto optimizer_dir = path.parent_path();
    const auto suite_dir = optimizer_dir.parent_path();
    const std::string suite = lower_ascii(suite_dir.filename().string());
    return !optimizer_dir.filename().empty() && suite.rfind("cec", 0) == 0;
}

} // namespace

int normalize_function_id(std::string label) {
    label = trim(label);
    if (label.empty()) {
        throw std::runtime_error("Empty function identifier in reference row.");
    }
    if (label.front() == 'F' || label.front() == 'f') {
        label.erase(label.begin());
    }
    try {
        std::size_t consumed = 0;
        const int value = std::stoi(label, &consumed);
        if (consumed != label.size() || value <= 0) {
            throw std::runtime_error("Invalid function identifier.");
        }
        return value;
    } catch (const std::exception&) {
        throw std::runtime_error("Invalid function identifier in reference row: '" + label + "'.");
    }
}

std::vector<ReferenceResultRow> load_reference_file(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("Cannot open reference file: " + path.string());
    }

    std::string line;
    std::map<std::string, Index> columns;
    std::vector<ReferenceResultRow> rows;
    int line_number = 0;

    while (std::getline(in, line)) {
        ++line_number;
        if (trim(line).empty()) {
            continue;
        }

        const auto cells = split_line(line);
        if (columns.empty()) {
            for (Index i = 0; i < cells.size(); ++i) {
                columns[lower_ascii(trim(cells[i]))] = i;
            }
            if (!column_index(columns, "function")) {
                throw std::runtime_error("Reference file missing Function column: " + path.string());
            }
            continue;
        }

        try {
            const Index function_col = *column_index(columns, "function");
            if (function_col >= cells.size() || trim(cells[function_col]).empty()) {
                continue;
            }

            ReferenceResultRow row;
            row.function_id = normalize_function_id(cells[function_col]);
            row.source_file = path;

            if (auto col = column_index(columns, "best")) {
                row.best = optional_real(cells, *col);
            }
            if (auto col = column_index(columns, "median")) {
                row.median = optional_real(cells, *col);
            }
            if (auto col = column_index(columns, "mean")) {
                row.mean = optional_real(cells, *col);
            }
            if (auto col = column_index(columns, "worst")) {
                row.worst = optional_real(cells, *col);
            }
            if (auto col = column_index(columns, "sd")) {
                row.sd = optional_real(cells, *col);
            }

            rows.push_back(std::move(row));
        } catch (const std::exception& ex) {
            throw std::runtime_error(path.string() + ":" + std::to_string(line_number) + ": " + ex.what());
        }
    }

    return rows;
}

std::vector<ReferenceFile> load_reference_tree(const std::filesystem::path& root) {
    if (!std::filesystem::exists(root)) {
        throw std::runtime_error("Reference root does not exist: " + root.string());
    }

    std::vector<ReferenceFile> files;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root)) {
        if (!entry.is_regular_file()) {
            continue;
        }
        const auto ext = lower_ascii(entry.path().extension().string());
        if (ext != ".csv" && ext != ".txt") {
            continue;
        }
        if (!is_reference_summary_path(entry.path())) {
            continue;
        }

        ReferenceFile file;
        file.path = entry.path();
        file.rows = load_reference_file(entry.path());
        files.push_back(std::move(file));
    }
    std::sort(files.begin(), files.end(), [](const ReferenceFile& a, const ReferenceFile& b) {
        return a.path.string() < b.path.string();
    });
    return files;
}

} // namespace gskcec
