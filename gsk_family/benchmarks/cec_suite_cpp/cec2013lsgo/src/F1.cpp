#include "F1.h"

namespace gskcec::cec2013lsgo {

F1::F1(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -100;
    maxX = 100;
    ID = 1;
    anotherz.resize(static_cast<std::size_t>(dimension));
    Ovector = readOvector();
}

double F1::compute(const double* x) {
    double result;
    int i;

    for (i = dimension - 1; i >= 0; i--) {
        anotherz[i] = x[i] - Ovector[i];
    }

    result = elliptic(anotherz.data(), dimension);
    return result;
}

} // namespace gskcec::cec2013lsgo
