#include "gskcec/core/bounds.hpp"
#include "gskcec/core/random.hpp"
#include "gskcec/core/statistics.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

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
    }

    if (failures == 0) {
        std::cout << "core_tests passed\n";
        return 0;
    }
    std::cerr << failures << " failure(s)\n";
    return EXIT_FAILURE;
}
