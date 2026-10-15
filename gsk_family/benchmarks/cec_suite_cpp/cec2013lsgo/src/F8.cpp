#include "F8.h"

namespace gskcec::cec2013lsgo {

F8::F8(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -100;
    maxX = 100;
    ID = 8;
    s_size = 20;
    anotherz.resize(static_cast<std::size_t>(dimension));
    Ovector = readOvector();
    Pvector = readPermVector();
    r25 = readR(25);
    r50 = readR(50);
    r100 = readR(100);
    s = readS(s_size);
    w = readW(s_size);
}

double F8::compute(const double* x) {
    int i;
    double result = 0.0;

    for (i = 0; i < dimension; i++) {
        anotherz[i] = x[i] - Ovector[i];
    }

    // s_size rotated, non-separable groups, weighted by w[i]
    int c = 0;
    for (i = 0; i < s_size; i++) {
        std::vector<double>& anotherz1 = rotateVector(i, c);
        result += w[i] * elliptic(anotherz1.data(), s[i]);
    }

    return result;
}

} // namespace gskcec::cec2013lsgo
