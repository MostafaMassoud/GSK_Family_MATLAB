#include "F3.h"

namespace gskcec::cec2013lsgo {

F3::F3(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -32;
    maxX = 32;
    ID = 3;
    anotherz.resize(static_cast<std::size_t>(dimension));
    Ovector = readOvector();
}

double F3::compute(const double* x) {
    int i;
    double result;

    for (i = dimension - 1; i >= 0; i--) {
        anotherz[i] = x[i] - Ovector[i];
    }

    result = ackley(anotherz.data(), dimension);
    return result;
}

} // namespace gskcec::cec2013lsgo
