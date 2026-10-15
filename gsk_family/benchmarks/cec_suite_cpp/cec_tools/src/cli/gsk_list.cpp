// gsk_list: enumerate benchmark suites, optimizers and imported references.

#include "gskcec/benchmark/factory.hpp"
#include "gskcec/benchmark/reference_results.hpp"

#include <filesystem>
#include <iostream>
#include <string>

namespace {

void print_usage() {
    std::cout << "Usage:\n"
              << "  gsk_list --benchmarks            list CEC suites with functions/dimensions\n"
              << "  gsk_list --optimizers            list MATLAB GSK-family optimizers\n"
              << "  gsk_list --references [root]     summarize imported reference tables\n"
              << "                                   (default root: benchmarks/cec_reference_results)\n";
}

void print_int_list(const std::vector<int>& values) {
    for (std::size_t i = 0; i < values.size(); ++i) {
        std::cout << (i == 0 ? "" : ",") << values[i];
    }
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    const std::string arg = argv[1];
    try {
        if (arg == "--benchmarks") {
            for (const auto& suite : gskcec::list_suites()) {
                const auto info = gskcec::suite_info(suite);
                std::cout << suite << "  functions=";
                print_int_list(info.functions);
                if (info.dimensions.empty()) {
                    std::cout << "  dimensions=native-per-function";
                } else {
                    std::cout << "  dimensions=";
                    print_int_list(info.dimensions);
                }
                std::cout << "\n";
            }
            return 0;
        }
        if (arg == "--optimizers") {
            std::cout << "gsk\nagsk\napgsk\natmals-gsk\negsk\nfdb-agsk\n";
            return 0;
        }
        if (arg == "--references") {
            const std::filesystem::path root = argc >= 3 ? argv[2] : "benchmarks/cec_reference_results";
            const auto files = gskcec::load_reference_tree(root);
            std::size_t rows = 0;
            for (const auto& file : files) {
                rows += file.rows.size();
                std::cout << file.path.generic_string() << "  rows=" << file.rows.size() << "\n";
            }
            std::cout << "reference_root=" << root.generic_string() << "\n";
            std::cout << "files=" << files.size() << "\n";
            std::cout << "rows=" << rows << "\n";
            return 0;
        }
    } catch (const std::exception& ex) {
        std::cerr << "gsk_list: " << ex.what() << "\n";
        return 2;
    }

    print_usage();
    return 1;
}
