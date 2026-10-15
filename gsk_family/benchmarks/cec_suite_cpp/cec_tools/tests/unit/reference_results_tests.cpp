#include "gskcec/benchmark/reference_results.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>

namespace {

namespace fs = std::filesystem;

int failures = 0;

// Always-on check; <cassert> would be a no-op under NDEBUG (Release).
#define CHECK(x)                                                  \
    do {                                                          \
        if (!(x)) {                                               \
            std::cerr << "FAIL: " #x "\n";                        \
            ++failures;                                           \
        }                                                         \
    } while (0)

void test_normalize_function_id() {
    CHECK(gskcec::normalize_function_id("1") == 1);
    CHECK(gskcec::normalize_function_id("F1") == 1);
    CHECK(gskcec::normalize_function_id("f30") == 30);
}

void write_file(const fs::path& path, const std::string& content) {
    std::ofstream out(path);
    out << content;
}

// Missing statistics appear in the imported tables as empty cells, dashes,
// NaN and N/A (the AGSK CEC2020 D=5 table). All must load as absent values,
// never as a parse error.
void test_missing_statistic_markers() {
    const fs::path tmp = fs::temp_directory_path() / "gskcec_refresult_tests";
    fs::remove_all(tmp);
    fs::create_directories(tmp);

    const fs::path path = tmp / "sample.csv";
    write_file(path,
               "Function,Best,Median,Mean,Worst,SD\n"
               "1,0.000e+00,0.000e+00,0.000e+00,0.000e+00,0.000e+00\n"
               "6,N/A,N/A,N/A,N/A,N/A\n"
               "F7,,,3.330e+01,,\n"
               "8,-,nan,1.0e+00,-,na\n");

    const auto rows = gskcec::load_reference_file(path);
    CHECK(rows.size() == 4);

    CHECK(rows[0].function_id == 1 && rows[0].mean.has_value() && *rows[0].mean == 0.0);

    CHECK(rows[1].function_id == 6);
    CHECK(!rows[1].best && !rows[1].median && !rows[1].mean && !rows[1].worst && !rows[1].sd);

    CHECK(rows[2].function_id == 7); // "F7" normalized
    CHECK(!rows[2].best && rows[2].mean.has_value() && *rows[2].mean == 33.3);

    CHECK(rows[3].function_id == 8);
    CHECK(!rows[3].best && !rows[3].median && rows[3].mean.has_value() && !rows[3].worst && !rows[3].sd);

    fs::remove_all(tmp);
}

} // namespace

int main() {
    test_normalize_function_id();
    test_missing_statistic_markers();
    if (failures == 0) {
        std::cout << "reference_results_tests passed\n";
        return 0;
    }
    std::cerr << failures << " failure(s)\n";
    return EXIT_FAILURE;
}
