#include "gskcec/benchmark/factory.hpp"

#include "gskcec/benchmark/cec2011.hpp"
#include "gskcec/benchmark/cec2013.hpp"
#include "gskcec/benchmark/cec2013lsgo.hpp"
#include "gskcec/benchmark/cec2017.hpp"
#include "gskcec/benchmark/cec2020.hpp"

#include <stdexcept>

namespace gskcec {

std::vector<std::string> list_suites() {
    return {"cec2011", "cec2013", "cec2013lsgo", "cec2017", "cec2020"};
}

SuiteInfo suite_info(const std::string& suite) {
    if (suite == "cec2011") {
        return {suite, cec2011::supported_functions(), {}};
    }
    if (suite == "cec2013") {
        return {suite, cec2013::supported_functions(), cec2013::supported_dimensions()};
    }
    if (suite == "cec2013lsgo") {
        return {suite, cec2013lsgo::supported_functions(), {}};
    }
    if (suite == "cec2017") {
        return {suite, cec2017::supported_functions(), cec2017::supported_dimensions()};
    }
    if (suite == "cec2020") {
        return {suite, cec2020::supported_functions(), cec2020::supported_dimensions()};
    }
    throw std::invalid_argument("Unknown benchmark suite '" + suite +
                                "'. Known suites: cec2011, cec2013, cec2013lsgo, cec2017, cec2020.");
}

std::unique_ptr<BenchmarkProblem> make_problem(const std::string& suite,
                                               int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root) {
    if (suite == "cec2011") {
        const int native = cec2011::native_dimension(function_id);
        if (dimension != 0 && dimension != native) {
            throw std::invalid_argument("cec2011 function " + std::to_string(function_id) +
                                        " has fixed dimension " + std::to_string(native) +
                                        "; pass 0 or the native dimension, got " +
                                        std::to_string(dimension) + ".");
        }
        return cec2011::make_problem(function_id, data_root);
    }
    if (suite == "cec2013") {
        return cec2013::make_problem(function_id, dimension, data_root);
    }
    if (suite == "cec2013lsgo") {
        const int native = cec2013lsgo::native_dimension(function_id);
        if (dimension != 0 && dimension != native) {
            throw std::invalid_argument("cec2013lsgo function " + std::to_string(function_id) +
                                        " has fixed dimension " + std::to_string(native) +
                                        "; pass 0 or the native dimension, got " +
                                        std::to_string(dimension) + ".");
        }
        return cec2013lsgo::make_problem(function_id, data_root);
    }
    if (suite == "cec2017") {
        return cec2017::make_problem(function_id, dimension, data_root);
    }
    if (suite == "cec2020") {
        return cec2020::make_problem(function_id, dimension, data_root);
    }
    throw std::invalid_argument("Unknown benchmark suite '" + suite +
                                "'. Known suites: cec2011, cec2013, cec2013lsgo, cec2017, cec2020.");
}

std::filesystem::path default_data_root(const std::string& suite,
                                        const std::filesystem::path& project_root) {
    suite_info(suite); // throws std::invalid_argument for an unknown suite
    return project_root / "benchmarks" / "cec_suite_cpp" / suite / "input_data";
}

} // namespace gskcec
