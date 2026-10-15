#include "F2.h"

namespace gskcec::cec2013lsgo {

F2::F2(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -5;
    maxX = 5;
    ID = 2;
    anotherz.resize(static_cast<std::size_t>(dimension));
    Ovector = readOvector();
}

double F2::compute(const double* x) {
    int i;
    double result;

    for (i = 0; i < dimension; i++) {
        anotherz[i] = x[i] - Ovector[i];
    }

    result = rastrigin(anotherz.data(), dimension);
    return result;
}

} // namespace gskcec::cec2013lsgo
