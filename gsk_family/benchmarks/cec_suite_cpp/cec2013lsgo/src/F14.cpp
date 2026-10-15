#include "F14.h"

namespace gskcec::cec2013lsgo {

F14::F14(const std::filesystem::path& dataDir) : Benchmarks(dataDir) {
    minX = -100;
    maxX = 100;
    ID = 14;
    s_size = 20;
    dimension = 905; // group sizes sum to 1000; 19 overlaps of 5 leave 905
    overlap = 5;
    // Load order as in the reference: s first, because readOvectorVec()
    // needs the group sizes.
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

    // s_size rotated, overlapping groups with their own shifts (conflicting)
    int c = 0;
    for (i = 0; i < s_size; i++) {
        std::vector<double>& anotherz1 = rotateVectorConflict(i, c, x);
        result += w[i] * schwefel(anotherz1.data(), s[i]);
    }

    return result;
}

} // namespace gskcec::cec2013lsgo
