#include "F7.h"

namespace gskcec::cec2013lsgo {

F7::F7(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -100;
    maxX = 100;
    ID = 7;
    s_size = 7;
    anotherz.resize(static_cast<std::size_t>(dimension));
    Ovector = readOvector();
    Pvector = readPermVector();
    r25 = readR(25);
    r50 = readR(50);
    r100 = readR(100);
    s = readS(s_size);
    w = readW(s_size);
}

double F7::compute(const double* x) {
    int i;
    double result = 0.0;

    for (i = 0; i < dimension; i++) {
        anotherz[i] = x[i] - Ovector[i];
    }

    // s_size non-separable parts with rotation
    int c = 0;
    for (i = 0; i < s_size; i++) {
        std::vector<double>& anotherz1 = rotateVector(i, c);
        result += w[i] * schwefel(anotherz1.data(), s[i]);
    }

    // one separable part without rotation
    std::vector<double> z(static_cast<std::size_t>(dimension - c));
    for (i = c; i < dimension; i++) {
        z[i - c] = anotherz[Pvector[i]];
    }

    result += sphere(z.data(), dimension - c);

    return result;
}

} // namespace gskcec::cec2013lsgo
