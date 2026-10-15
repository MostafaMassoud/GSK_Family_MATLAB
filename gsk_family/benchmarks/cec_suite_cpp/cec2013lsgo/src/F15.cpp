#include "F15.h"

namespace gskcec::cec2013lsgo {

F15::F15(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -100;
    maxX = 100;
    ID = 15;
    anotherz.resize(static_cast<std::size_t>(dimension));
    Ovector = readOvector();
}

double F15::compute(const double* x) {
    int i;
    double result = 0.0;

    for (i = 0; i < dimension; i++) {
        anotherz[i] = x[i] - Ovector[i];
    }

    result = schwefel(anotherz.data(), dimension);
    return result;
}

} // namespace gskcec::cec2013lsgo
