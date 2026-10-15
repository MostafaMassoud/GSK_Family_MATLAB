#include "gskcec/benchmark/data_loading.hpp"
#include "gskcec/core/bounds.hpp"
#include "gskcec/core/random.hpp"
#include "gskcec/core/statistics.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {

int failures = 0;

// Always-on check (unlike <cassert>, which NDEBUG disables in Release builds,
// turning assert-based tests into silent no-ops).
void check(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        ++failures;
    }
}

} // namespace

int main() {
    using namespace gskcec;

    {
        Bounds b = Bounds::uniform(2, -100.0, 100.0);
        Vector candidate{-200.0, 250.0};
        Vector parent{0.0, 50.0};
        b.repair_midpoint(candidate, parent);
        check(candidate[0] == -50.0, "midpoint repair below lower bound");
        check(candidate[1] == 75.0, "midpoint repair above upper bound");
    }

    {
        Vector values{3.0, 1.0, 2.0, 5.0};
        const auto s = summarize(values);
        check(s.best == 1.0, "summary best");
        check(s.worst == 5.0, "summary worst");
        check(s.median == 2.5, "summary median");
        check(std::abs(s.mean - 2.75) < 1.0e-12, "summary mean");
        // Sum of squared deviations is 8.75: sample SD divides by N-1 = 3
        // (MATLAB std), population SD would divide by 4.
        check(std::abs(s.sd - std::sqrt(8.75 / 3.0)) < 1.0e-12,
              "summary sd is the sample (N-1) sd, matching MATLAB std");
    }

    {
        const Seed a = make_run_seed(42, 10, 3, 4);
        const Seed b = make_run_seed(42, 10, 3, 4);
        const Seed c = make_run_seed(43, 10, 3, 4);
        check(a == b, "run seed is deterministic");
        check(a != c, "base seed changes run seed");
        RandomEngine rng1(a);
        RandomEngine rng2(b);
        check(rng1.uniform_index(0, 100) == rng2.uniform_index(0, 100),
              "same seed yields the same RNG draw");

        // Golden values from the get_cec_seed.m contract
        // mod(base + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1,
        // so a stride/modulus/+1 drift cannot pass.
        check(a == 17000320ULL, "run seed matches get_cec_seed(42,10,3,4)");
        // Pinned in src/tests/test_seed_policy.m and docs/reference/seed_policy.md.
        check(make_run_seed(20240620, 30, 7, 12) == 69241386ULL,
              "run seed matches get_cec_seed(20240620,30,7,12)");
        check(make_run_seed(2147483645ULL, 0, 0, 0) == 2147483646ULL, "run seed upper bound (mod + 1)");
        check(make_run_seed(2147483646ULL, 0, 0, 0) == 1ULL, "run seed wraps the modulus to 1");
        check(make_run_seed(2147483645ULL, 1, 1, 1) == 3000073ULL,
              "run seed wraps at 2147483646 like get_cec_seed");
    }

    {
        // load_values_file(path, n): fewer than n values is an error; extra
        // values are ignored (the reference CEC readers fscanf only n).
        const std::filesystem::path tmp = std::filesystem::temp_directory_path() / "gskcec_core_tests_values.txt";
        {
            std::ofstream out(tmp);
            out << "1.5 2.5\n3.5 4.5 5.5\n";
        }
        const Vector first3 = load_values_file(tmp, 3);
        check(first3 == Vector({1.5, 2.5, 3.5}), "load_values_file(path, n) returns the first n values");
        check(load_values_file(tmp, 5).size() == 5, "load_values_file(path, n) accepts an exact count");
        bool threw = false;
        try {
            static_cast<void>(load_values_file(tmp, 6));
        } catch (const std::runtime_error&) {
            threw = true;
        }
        check(threw, "load_values_file(path, n) throws when the file holds fewer than n values");
        std::filesystem::remove(tmp);
    }

    if (failures == 0) {
        std::cout << "core_tests passed\n";
        return 0;
    }
    std::cerr << failures << " failure(s)\n";
    return EXIT_FAILURE;
}
