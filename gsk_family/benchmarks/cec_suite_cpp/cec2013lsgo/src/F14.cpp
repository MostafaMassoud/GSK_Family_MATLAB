#include "F14.h"

namespace gskcec::cec2013lsgo {

F14::F14(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -100;
    maxX = 100;
    ID = 14;
    s_size = 20;
    dimension = 905; // because of overlapping
    overlap = 5;
    // Same load order as the reference: s first, then the grouped shift
    // vector (readOvectorVec needs s).
    s = readS(s_size);
    OvectorVec = readOvectorVec();
    Pvector = readPermVector();
    r25 = readR(25);
    r50 = readR(50);
    r100 = readR(100);
    w = readW(s_size);
}

double F14::compute(const double* x) {
    int i;
    double result = 0.0;

    // s_size non-separable parts with conflicting overlapping rotation
    int c = 0;
    for (i = 0; i < s_size; i++) {
        std::vector<double>& anotherz1 = rotateVectorConflict(i, c, x);
        result += w[i] * schwefel(anotherz1.data(), s[i]);
    }

    return result;
}

} // namespace gskcec::cec2013lsgo
