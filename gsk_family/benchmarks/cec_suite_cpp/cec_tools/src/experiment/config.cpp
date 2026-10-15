#include "gskcec/experiment/config.hpp"

#include <cctype>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace gskcec {

namespace {

[[noreturn]] void fail(const std::filesystem::path& path, std::size_t line_no, const std::string& message) {
    throw std::runtime_error("Config error " + path.string() + ":" + std::to_string(line_no) + ": " + message);
}

std::string trim(const std::string& s) {
    const auto begin = s.find_first_not_of(" \t\r");
    if (begin == std::string::npos) {
        return "";
    }
    const auto end = s.find_last_not_of(" \t\r");
    return s.substr(begin, end - begin + 1);
}

std::vector<std::string> split_list(const std::filesystem::path& path, std::size_t line_no, std::string value) {
    // Accepts "[a, b, c]" or a bare scalar "a".
    value = trim(value);
    std::vector<std::string> items;
    if (!value.empty() && value.front() == '[') {
        if (value.back() != ']') {
            fail(path, line_no, "list value must end with ']'");
        }
        value = value.substr(1, value.size() - 2);
        std::stringstream ss(value);
        std::string item;
        while (std::getline(ss, item, ',')) {
            item = trim(item);
            if (item.empty()) {
                fail(path, line_no, "empty list element");
            }
            items.push_back(item);
        }
    } else if (!value.empty()) {
        items.push_back(value);
    }
    return items;
}

int parse_int(const std::filesystem::path& path, std::size_t line_no, const std::string& token) {
    try {
        std::size_t consumed = 0;
        const int v = std::stoi(token, &consumed);
        if (consumed != token.size()) {
            throw std::invalid_argument(token);
        }
        return v;
    } catch (const std::exception&) {
        fail(path, line_no, "expected an integer, got '" + token + "'");
    }
}

long long parse_ll(const std::filesystem::path& path, std::size_t line_no, const std::string& token) {
    try {
        std::size_t consumed = 0;
        const long long v = std::stoll(token, &consumed);
        if (consumed != token.size()) {
            throw std::invalid_argument(token);
        }
        return v;
    } catch (const std::exception&) {
        fail(path, line_no, "expected an integer, got '" + token + "'");
    }
}

std::vector<int> parse_int_list_or_all(const std::filesystem::path& path, std::size_t line_no, const std::string& value) {
    if (trim(value) == "all") {
        return {};
    }
    const auto tokens = split_list(path, line_no, value);
    if (tokens.empty()) {
        // An empty list would otherwise be indistinguishable from `all`.
        fail(path, line_no, "empty list; use 'all' for the suite defaults");
    }
    std::vector<int> out;
    for (const auto& token : tokens) {
        out.push_back(parse_int(path, line_no, token));
    }
    return out;
}

} // namespace

Seed parse_seed_value(const std::string& token) {
    // 2^53: every accepted value survives exactly as a MATLAB double, and the
    // uint64 sums in get_cec_seed.m cannot saturate.
    constexpr unsigned long long kMaxSeed = 9007199254740992ULL;
    const auto bad = [&token]() {
        return std::invalid_argument("must be an integer in [0, 2^53 = 9007199254740992], got '" +
                                     token + "'");
    };
    // A leading digit rules out '-' (stoull would wrap it to 2^64-k), '+'
    // and leading whitespace.
    if (token.empty() || std::isdigit(static_cast<unsigned char>(token.front())) == 0) {
        throw bad();
    }
    std::size_t consumed = 0;
    unsigned long long v = 0;
    try {
        v = std::stoull(token, &consumed);
    } catch (const std::exception&) {
        throw bad();
    }
    if (consumed != token.size() || v > kMaxSeed) {
        throw bad();
    }
    return static_cast<Seed>(v);
}

bool is_valid_seed_policy(const std::string& value) {
    return value == "reference" || value == "native" ||
           value == "unified" || value == "derived";
}

bool is_valid_rand_generator(const std::string& value) {
    return value == "threefry" || value == "twister" || value == "seed" ||
           value == "state";
}

ExperimentConfig load_experiment_config(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("Cannot open config file: " + path.string());
    }
    ExperimentConfig cfg;
    cfg.source_path = path;
    std::string raw;
    std::size_t line_no = 0;
    bool saw_suite = false;
    while (std::getline(in, raw)) {
        ++line_no;
        if (line_no == 1 && raw.compare(0, 3, "\xEF\xBB\xBF") == 0) {
            // Tolerate a leading UTF-8 BOM (Windows PowerShell 5.1
            // Set-Content/Out-File -Encoding utf8, some editors). A BOM
            // anywhere else is still an error.
            raw.erase(0, 3);
        }
        const auto hash = raw.find('#');
        std::string line = trim(hash == std::string::npos ? raw : raw.substr(0, hash));
        if (line.empty()) {
            continue;
        }
        const auto colon = line.find(':');
        if (colon == std::string::npos) {
            fail(path, line_no, "expected 'key: value'");
        }
        const std::string key = trim(line.substr(0, colon));
        const std::string value = trim(line.substr(colon + 1));
        if (value.empty()) {
            fail(path, line_no, "missing value for key '" + key + "'");
        }

        if (key == "optimizers" || key == "optimizer") {
            cfg.optimizers = split_list(path, line_no, value);
            if (cfg.optimizers.empty()) {
                fail(path, line_no, "optimizers list is empty");
            }
        } else if (key == "suite") {
            cfg.suite = value;
            saw_suite = true;
        } else if (key == "functions") {
            cfg.functions = parse_int_list_or_all(path, line_no, value);
        } else if (key == "dimensions") {
            cfg.dimensions = parse_int_list_or_all(path, line_no, value);
        } else if (key == "runs") {
            cfg.runs = parse_int(path, line_no, value);
            if (cfg.runs < 1) {
                fail(path, line_no, "runs must be >= 1");
            }
        } else if (key == "seed") {
            try {
                cfg.seed = parse_seed_value(value);
            } catch (const std::exception& ex) {
                fail(path, line_no, std::string("seed ") + ex.what());
            }
        } else if (key == "seed_policy") {
            if (!is_valid_seed_policy(value)) {
                fail(path, line_no, "seed_policy must be reference, native, unified, or derived");
            }
            cfg.seed_policy = value;
        } else if (key == "rand_generator") {
            if (!is_valid_rand_generator(value)) {
                fail(path, line_no, "rand_generator must be threefry, twister, seed, or state");
            }
            cfg.rand_generator = value;
        } else if (key == "max_evaluations") {
            cfg.max_evaluations = parse_ll(path, line_no, value);
            if (cfg.max_evaluations < 0) {
                fail(path, line_no, "max_evaluations must be >= 0");
            }
        } else if (key == "output_root") {
            cfg.output_root = value;
        } else if (key == "data_root") {
            // Rejected explicitly rather than silently ignored: the MATLAB
            // runner has no data_root input, so the value could never take
            // effect.
            fail(path, line_no,
                 "data_root is not supported: benchmark data always loads from "
                 "<project_root>/benchmarks/cec_suite_cpp/<suite>/input_data; remove this key");
        } else if (key == "reference_root") {
            cfg.reference_root = value;
        } else if (key == "overwrite") {
            if (value == "true") {
                cfg.overwrite = true;
            } else if (value == "false") {
                cfg.overwrite = false;
            } else {
                fail(path, line_no, "overwrite must be true or false");
            }
        } else if (key == "parallel") {
            if (value == "false") {
                cfg.parallel = false;
            } else if (value == "true") {
                fail(path, line_no,
                     "parallel execution is not implemented in this version; runs are sequential "
                     "(and per-run seeds make sequential execution fully reproducible)");
            } else {
                fail(path, line_no, "parallel must be true or false");
            }
        } else {
            fail(path, line_no, "unknown key '" + key + "'");
        }
    }
    if (cfg.optimizers.empty()) {
        throw std::runtime_error("Config error " + path.string() + ": no optimizers given.");
    }
    if (!saw_suite || cfg.suite.empty()) {
        throw std::runtime_error("Config error " + path.string() + ": no suite given.");
    }
    return cfg;
}

} // namespace gskcec
