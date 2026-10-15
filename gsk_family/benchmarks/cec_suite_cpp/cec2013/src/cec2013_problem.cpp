// cec2013_problem.cpp -- standalone C++20 port of the standard CEC2013
// single-objective benchmark suite (28 functions).
//
// Ported from the CEC2013 R package:
//   historical source:
//     src/test_func.c   ("CEC13 Test Function Suite", Jane Jing Liang,
//                        last modified 27 Jan 2013 -- the 28 function
//                        implementations transcribed below)
//     src/cec2013.c     (R bridge; defines the calling convention, the
//                        data directory layout and the global buffers)
//     R/cec2013.R       (argument validation: function ids 1..28 and
//                        dimensions {2,5,10,20,30,40,50,60,70,80,90,100})
//
// R-isms (R.h, error(), R_CheckUserInterrupt(), lazily re-initialised
// globals) are replaced by C++ exceptions and per-instance RAII state.
// Numerics, constants, biases and transformation order are preserved
// verbatim, including reference quirks, which are deliberately NOT fixed:
//
//   * asyfunc(src, dst) assigns dst[i] only when src[i] > 0; non-positive
//     components keep whatever an EARLIER pipeline stage left in dst
//     (e.g. the pre-rotation shifted vector), bypassing the preceding
//     stage as well. Affects f3, f7, f8, f9, f12, f13, f20 and rotated
//     composition members.
//   * grie_rosen_func (f19, and component 0 of cf08/f28) computes the
//     rotation into z and then overwrites it with the UNROTATED y + 1
//     ("z[i]=y[i]+1" in the reference), so the rotation has no effect.
//   * dif_powers_func uses the integer-division exponent 2 + 4*i/(nx-1).
//   * schwefel_func scales by 1000/100 evaluated in integer arithmetic
//     (== 10) and its optimum constants leave a ~1e-12*D residual at the
//     shifted optimum.
//   * oszfunc keeps xx across loop iterations (xx = 0 initialised once);
//     only reachable multiplied by sx == 0, hence no observable effect.
//   * The x_bound global and the EPS macro of the reference are never
//     used by the computation and are dropped.
//
// Data files (loaded once in the constructor, mirroring test_func.c):
//   M_D<dim>.txt    : 10 rotation matrices, dim x dim, row-major, flat.
//   shift_data.txt  : flat prefix of 10*dim values (the file stores a
//                     10 x 100 table; the reference reads it flat).
//
// Thread safety: evaluate() reuses mutable per-instance scratch buffers
// (the y/z globals of the reference) and is therefore NOT thread-safe on
// a shared instance. Use one problem instance per thread.

#include "gskcec/benchmark/cec2013.hpp"

#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <filesystem>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace gskcec::cec2013 {

namespace {

constexpr double kInf = 1.0e99;                              // INF in test_func.c
constexpr double kE = 2.7182818284590452353602874713526625;  // E in test_func.c
constexpr double kPi = 3.1415926535897932384626433832795029; // PI in test_func.c

// cf_num in the loader section of test_func.c: number of rotation matrices
// read from M_D<dim>.txt and of shift rows read from shift_data.txt.
constexpr int kTableCount = 10;

// Function biases added by the test_func() dispatcher (f1..f14 use
// -1400..-100, f15..f28 use 100..1400). kBias[function_id - 1].
constexpr double kBias[28] = {
    -1400.0, -1300.0, -1200.0, -1100.0, -1000.0, -900.0, -800.0,
    -700.0,  -600.0,  -500.0,  -400.0,  -300.0,  -200.0, -100.0,
    100.0,   200.0,   300.0,   400.0,   500.0,   600.0,  700.0,
    800.0,   900.0,   1000.0,  1100.0,  1200.0,  1300.0, 1400.0};

// Replacement for the y/z/tmpx work arrays of the reference (y and z are
// globals there; tmpx is malloc'd per call inside bi_rastrigin_func).
struct Scratch {
    double* y;
    double* z;
    double* tmpx;
};

/* ------------------------------------------------------------------ */
/* Transformation helpers (verbatim ports of test_func.c)              */
/* ------------------------------------------------------------------ */

void shiftfunc(const double* x, double* xshift, int nx, const double* Os) {
    for (int i = 0; i < nx; i++) {
        xshift[i] = x[i] - Os[i];
    }
}

void rotatefunc(const double* x, double* xrot, int nx, const double* Mr) {
    for (int i = 0; i < nx; i++) {
        xrot[i] = 0;
        for (int j = 0; j < nx; j++) {
            xrot[i] = xrot[i] + x[j] * Mr[i * nx + j];
        }
    }
}

// Reference quirk preserved: entries with x[i] <= 0 are NOT assigned, so
// xasy keeps the stale content left by an earlier pipeline stage.
void asyfunc(const double* x, double* xasy, int nx, double beta) {
    for (int i = 0; i < nx; i++) {
        if (x[i] > 0)
            xasy[i] = std::pow(x[i], 1.0 + beta * i / (nx - 1) * std::pow(x[i], 0.5));
    }
}

void oszfunc(const double* x, double* xosz, int nx) {
    int sx;
    double c1, c2, xx = 0; // xx persists across iterations, as in the reference
    for (int i = 0; i < nx; i++) {
        if (i == 0 || i == nx - 1) {
            if (x[i] != 0)
                xx = std::log(std::fabs(x[i]));
            if (x[i] > 0) {
                c1 = 10;
                c2 = 7.9;
            } else {
                c1 = 5.5;
                c2 = 3.1;
            }
            if (x[i] > 0)
                sx = 1;
            else if (x[i] == 0)
                sx = 0;
            else
                sx = -1;
            xosz[i] = sx * std::exp(xx + 0.049 * (std::sin(c1 * xx) + std::sin(c2 * xx)));
        } else
            xosz[i] = x[i];
    }
}

/* ------------------------------------------------------------------ */
/* Basic functions (verbatim ports of test_func.c)                     */
/* ------------------------------------------------------------------ */

void sphere_func(const double* x, double* f, int nx, const double* Os,
                 const double* Mr, int r_flag, const Scratch& s) { /* Sphere */
    double* y = s.y;
    double* z = s.z;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    f[0] = 0.0;
    for (int i = 0; i < nx; i++) {
        f[0] += z[i] * z[i];
    }
}

// Returns the per-i ellipsoidal coefficients std::pow(10.0, 6.0*i/(nx-1)),
// cached per distinct nx. Pure function of (i, nx) -> the cached values are
// the exact std::pow results, so callers stay bit-identical to the reference.
// thread_local: one cache per thread, matching the per-thread instance model.
const double* ellips_coef(int nx) {
    thread_local std::vector<std::vector<double>> cache;
    const auto n = static_cast<std::size_t>(nx);
    if (cache.size() <= n) {
        cache.resize(n + 1);
    }
    std::vector<double>& c = cache[n];
    if (c.size() != n) {
        c.resize(n);
        for (int i = 0; i < nx; i++) {
            c[static_cast<std::size_t>(i)] = std::pow(10.0, 6.0 * i / (nx - 1));
        }
    }
    return c.data();
}

void ellips_func(const double* x, double* f, int nx, const double* Os,
                 const double* Mr, int r_flag, const Scratch& s) { /* Ellipsoidal */
    double* y = s.y;
    double* z = s.z;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    oszfunc(z, y, nx);
    f[0] = 0.0;
    // The coefficient std::pow(10.0, 6.0*i/(nx-1)) is a pure function of i and
    // nx; cache it per distinct nx (the function is also reused at hybrid/
    // composition sub-dimensions). Bit-identical: the same std::pow values are
    // stored once instead of recomputed each evaluation. thread_local matches
    // the documented "one problem instance per thread" contract.
    const double* coef = ellips_coef(nx);
    for (int i = 0; i < nx; i++) {
        f[0] += coef[i] * y[i] * y[i];
    }
}

void bent_cigar_func(const double* x, double* f, int nx, const double* Os,
                     const double* Mr, int r_flag, const Scratch& s) { /* Bent_Cigar */
    double* y = s.y;
    double* z = s.z;
    const double beta = 0.5;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    asyfunc(z, y, nx, beta); // y still holds the shift output (reference quirk)
    if (r_flag == 1)
        rotatefunc(y, z, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    // std::pow(10.0, 6.0) is loop-invariant; hoist it (== 1000000.0 exactly,
    // so the per-dimension products are bit-identical to the reference).
    const double c6 = std::pow(10.0, 6.0);
    f[0] = z[0] * z[0];
    for (int i = 1; i < nx; i++) {
        f[0] += c6 * z[i] * z[i];
    }
}

void discus_func(const double* x, double* f, int nx, const double* Os,
                 const double* Mr, int r_flag, const Scratch& s) { /* Discus */
    double* y = s.y;
    double* z = s.z;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    oszfunc(z, y, nx);

    // std::pow(10.0, 6.0) == 1000000.0 exactly; compute once (bit-identical).
    const double c6 = std::pow(10.0, 6.0);
    f[0] = c6 * y[0] * y[0];
    for (int i = 1; i < nx; i++) {
        f[0] += y[i] * y[i];
    }
}

void dif_powers_func(const double* x, double* f, int nx, const double* Os,
                     const double* Mr, int r_flag, const Scratch& s) { /* Different Powers */
    double* y = s.y;
    double* z = s.z;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    f[0] = 0.0;
    for (int i = 0; i < nx; i++) {
        // Reference quirk preserved: 2 + 4*i/(nx-1) is INTEGER division.
        const int exponent = 2 + 4 * i / (nx - 1);
        f[0] += std::pow(std::fabs(z[i]), static_cast<double>(exponent));
    }
    f[0] = std::pow(f[0], 0.5);
}

void rosenbrock_func(const double* x, double* f, int nx, const double* Os,
                     const double* Mr, int r_flag, const Scratch& s) { /* Rosenbrock's */
    double* y = s.y;
    double* z = s.z;
    double tmp1, tmp2;
    shiftfunc(x, y, nx, Os); // shift
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] = y[i] * 2.048 / 100;
    }
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr); // rotate
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    for (int i = 0; i < nx; i++) { // shift to origin
        z[i] = z[i] + 1;
    }

    f[0] = 0.0;
    for (int i = 0; i < nx - 1; i++) {
        tmp1 = z[i] * z[i] - z[i + 1];
        tmp2 = z[i] - 1.0;
        f[0] += 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
    }
}

void schaffer_F7_func(const double* x, double* f, int nx, const double* Os,
                      const double* Mr, int r_flag, const Scratch& s) { /* Schaffer's F7 */
    double* y = s.y;
    double* z = s.z;
    double tmp;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];
    asyfunc(z, y, nx, 0.5); // y still holds the shift output (reference quirk)
    for (int i = 0; i < nx; i++)
        z[i] = y[i] * std::pow(10.0, 1.0 * i / (nx - 1) / 2.0);
    if (r_flag == 1)
        rotatefunc(z, y, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    for (int i = 0; i < nx - 1; i++)
        z[i] = std::pow(y[i] * y[i] + y[i + 1] * y[i + 1], 0.5);
    f[0] = 0.0;
    for (int i = 0; i < nx - 1; i++) {
        tmp = std::sin(50.0 * std::pow(z[i], 0.2));
        f[0] += std::pow(z[i], 0.5) + std::pow(z[i], 0.5) * tmp * tmp;
    }
    f[0] = f[0] * f[0] / (nx - 1) / (nx - 1);
}

void ackley_func(const double* x, double* f, int nx, const double* Os,
                 const double* Mr, int r_flag, const Scratch& s) { /* Ackley's */
    double* y = s.y;
    double* z = s.z;
    double sum1, sum2;

    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    asyfunc(z, y, nx, 0.5); // y still holds the shift output (reference quirk)
    for (int i = 0; i < nx; i++)
        z[i] = y[i] * std::pow(10.0, 1.0 * i / (nx - 1) / 2.0);
    if (r_flag == 1)
        rotatefunc(z, y, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    sum1 = 0.0;
    sum2 = 0.0;
    for (int i = 0; i < nx; i++) {
        sum1 += y[i] * y[i];
        sum2 += std::cos(2.0 * kPi * y[i]);
    }
    sum1 = -0.2 * std::sqrt(sum1 / nx);
    sum2 /= nx;
    f[0] = kE - 20.0 * std::exp(sum1) - std::exp(sum2) + 20.0;
}

void weierstrass_func(const double* x, double* f, int nx, const double* Os,
                      const double* Mr, int r_flag, const Scratch& s) { /* Weierstrass's */
    double* y = s.y;
    double* z = s.z;
    int k_max;
    double sum, sum2 = 0.0, a, b;

    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] = y[i] * 0.5 / 100;
    }
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    asyfunc(z, y, nx, 0.5); // y still holds the shrunk shift output (reference quirk)
    for (int i = 0; i < nx; i++)
        z[i] = y[i] * std::pow(10.0, 1.0 * i / (nx - 1) / 2.0);
    if (r_flag == 1)
        rotatefunc(z, y, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    a = 0.5;
    b = 3.0;
    k_max = 20;
    // std::pow(a,j) and std::pow(b,j) depend only on j; precompute once instead
    // of nx*(k_max+1) times. Bit-identical: the cached values are the exact
    // std::pow results and the summation order of sum/sum2 is unchanged
    // (mirrors the cec2017 weierstrass hoist).
    double aj[21];
    double bj[21];
    for (int j = 0; j <= k_max; j++) {
        aj[j] = std::pow(a, static_cast<double>(j));
        bj[j] = std::pow(b, static_cast<double>(j));
    }
    f[0] = 0.0;
    for (int i = 0; i < nx; i++) {
        sum = 0.0;
        sum2 = 0.0;
        for (int j = 0; j <= k_max; j++) {
            sum += aj[j] * std::cos(2.0 * kPi * bj[j] * (y[i] + 0.5));
            sum2 += aj[j] * std::cos(2.0 * kPi * bj[j] * 0.5);
        }
        f[0] += sum;
    }
    f[0] -= nx * sum2;
}

void griewank_func(const double* x, double* f, int nx, const double* Os,
                   const double* Mr, int r_flag, const Scratch& s) { /* Griewank's */
    double* y = s.y;
    double* z = s.z;
    double sp, p;

    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] = y[i] * 600.0 / 100.0;
    }
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    for (int i = 0; i < nx; i++)
        z[i] = z[i] * std::pow(100.0, 1.0 * i / (nx - 1) / 2.0);

    sp = 0.0;
    p = 1.0;
    for (int i = 0; i < nx; i++) {
        sp += z[i] * z[i];
        p *= std::cos(z[i] / std::sqrt(1.0 + i));
    }
    f[0] = 1.0 + sp / 4000.0 - p;
}

void rastrigin_func(const double* x, double* f, int nx, const double* Os,
                    const double* Mr, int r_flag, const Scratch& s) { /* Rastrigin's */
    double* y = s.y;
    double* z = s.z;
    const double alpha = 10.0, beta = 0.2;
    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] = y[i] * 5.12 / 100;
    }

    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    oszfunc(z, y, nx);
    asyfunc(y, z, nx, beta); // z still holds the first-rotation output (reference quirk)

    if (r_flag == 1)
        rotatefunc(z, y, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    for (int i = 0; i < nx; i++) {
        y[i] *= std::pow(alpha, 1.0 * i / (nx - 1) / 2);
    }

    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    f[0] = 0.0;
    for (int i = 0; i < nx; i++) {
        f[0] += (z[i] * z[i] - 10.0 * std::cos(2.0 * kPi * z[i]) + 10.0);
    }
}

void step_rastrigin_func(const double* x, double* f, int nx, const double* Os,
                         const double* Mr, int r_flag, const Scratch& s) { /* Noncontinuous Rastrigin's */
    double* y = s.y;
    double* z = s.z;
    const double alpha = 10.0, beta = 0.2;
    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] = y[i] * 5.12 / 100;
    }

    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    for (int i = 0; i < nx; i++) {
        if (std::fabs(z[i]) > 0.5)
            z[i] = std::floor(2 * z[i] + 0.5) / 2;
    }

    oszfunc(z, y, nx);
    asyfunc(y, z, nx, beta); // z still holds the rounded values (reference quirk)

    if (r_flag == 1)
        rotatefunc(z, y, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    for (int i = 0; i < nx; i++) {
        y[i] *= std::pow(alpha, 1.0 * i / (nx - 1) / 2);
    }

    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    f[0] = 0.0;
    for (int i = 0; i < nx; i++) {
        f[0] += (z[i] * z[i] - 10.0 * std::cos(2.0 * kPi * z[i]) + 10.0);
    }
}

void schwefel_func(const double* x, double* f, int nx, const double* Os,
                   const double* Mr, int r_flag, const Scratch& s) { /* Schwefel's */
    double* y = s.y;
    double* z = s.z;
    double tmp;
    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] *= 10.0; // "y[i]*=1000/100" in the reference: integer division == 10
    }
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    for (int i = 0; i < nx; i++)
        y[i] = z[i] * std::pow(10.0, 1.0 * i / (nx - 1) / 2.0);

    for (int i = 0; i < nx; i++)
        z[i] = y[i] + 4.209687462275036e+002;

    f[0] = 0;
    for (int i = 0; i < nx; i++) {
        if (z[i] > 500) {
            f[0] -= (500.0 - std::fmod(z[i], 500)) * std::sin(std::pow(500.0 - std::fmod(z[i], 500), 0.5));
            tmp = (z[i] - 500.0) / 100;
            f[0] += tmp * tmp / nx;
        } else if (z[i] < -500) {
            f[0] -= (-500.0 + std::fmod(std::fabs(z[i]), 500)) * std::sin(std::pow(500.0 - std::fmod(std::fabs(z[i]), 500), 0.5));
            tmp = (z[i] + 500.0) / 100;
            f[0] += tmp * tmp / nx;
        } else
            f[0] -= z[i] * std::sin(std::pow(std::fabs(z[i]), 0.5));
    }
    f[0] = 4.189828872724338e+002 * nx + f[0];
}

void katsuura_func(const double* x, double* f, int nx, const double* Os,
                   const double* Mr, int r_flag, const Scratch& s) { /* Katsuura */
    double* y = s.y;
    double* z = s.z;
    double temp, tmp1, tmp2, tmp3;
    tmp3 = std::pow(1.0 * nx, 1.2);
    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] *= 5.0 / 100.0;
    }
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    for (int i = 0; i < nx; i++)
        z[i] *= std::pow(100.0, 1.0 * i / (nx - 1) / 2.0);

    if (r_flag == 1)
        rotatefunc(z, y, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    // std::pow(2.0, j) depends only on j; precompute once instead of nx*32
    // times. Bit-identical: the same std::pow(2.0, j) values, just not
    // recomputed (mirrors the cec2017 katsuura hoist).
    double pow2[33];
    for (int j = 1; j <= 32; j++) {
        pow2[j] = std::pow(2.0, static_cast<double>(j));
    }
    f[0] = 1.0;
    for (int i = 0; i < nx; i++) {
        temp = 0.0;
        for (int j = 1; j <= 32; j++) {
            tmp1 = pow2[j];
            tmp2 = tmp1 * y[i];
            temp += std::fabs(tmp2 - std::floor(tmp2 + 0.5)) / tmp1;
        }
        f[0] *= std::pow(1.0 + (i + 1) * temp, 10.0 / tmp3);
    }
    tmp1 = 10.0 / nx / nx;
    f[0] = f[0] * tmp1 - tmp1;
}

void bi_rastrigin_func(const double* x, double* f, int nx, const double* Os,
                       const double* Mr, int r_flag, const Scratch& s) { /* Lunacek Bi_rastrigin */
    double* y = s.y;
    double* z = s.z;
    double* tmpx = s.tmpx; // malloc'd per call in the reference
    const double mu0 = 2.5, d = 1.0;
    double sc, mu1, tmp, tmp1, tmp2;
    sc = 1.0 - 1.0 / (2.0 * std::pow(nx + 20.0, 0.5) - 8.2);
    mu1 = -std::pow((mu0 * mu0 - d) / sc, 0.5);

    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] *= 10.0 / 100.0;
    }

    for (int i = 0; i < nx; i++) {
        tmpx[i] = 2 * y[i];
        if (Os[i] < 0.)
            tmpx[i] *= -1.;
    }

    for (int i = 0; i < nx; i++) {
        z[i] = tmpx[i];
        tmpx[i] += mu0;
    }
    if (r_flag == 1)
        rotatefunc(z, y, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            y[i] = z[i];

    for (int i = 0; i < nx; i++)
        y[i] *= std::pow(100.0, 1.0 * i / (nx - 1) / 2.0);
    if (r_flag == 1)
        rotatefunc(y, z, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    tmp1 = 0.0;
    tmp2 = 0.0;
    for (int i = 0; i < nx; i++) {
        tmp = tmpx[i] - mu0;
        tmp1 += tmp * tmp;
        tmp = tmpx[i] - mu1;
        tmp2 += tmp * tmp;
    }
    tmp2 *= sc;
    tmp2 += d * nx;
    tmp = 0;
    for (int i = 0; i < nx; i++) {
        tmp += std::cos(2.0 * kPi * z[i]);
    }

    if (tmp1 < tmp2)
        f[0] = tmp1;
    else
        f[0] = tmp2;
    f[0] += 10.0 * (nx - tmp);
}

void grie_rosen_func(const double* x, double* f, int nx, const double* Os,
                     const double* Mr, int r_flag, const Scratch& s) { /* Griewank-Rosenbrock */
    double* y = s.y;
    double* z = s.z;
    double temp, tmp1, tmp2;

    shiftfunc(x, y, nx, Os);
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] = y[i] * 5.0 / 100;
    }
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    // Reference quirk preserved: "z[i]=y[i]+1" overwrites the rotation
    // result with the UNROTATED vector, so the rotation above is dead.
    for (int i = 0; i < nx; i++) { // shift to origin
        z[i] = y[i] + 1;
    }

    f[0] = 0.0;
    for (int i = 0; i < nx - 1; i++) {
        tmp1 = z[i] * z[i] - z[i + 1];
        tmp2 = z[i] - 1.0;
        temp = 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
        f[0] += (temp * temp) / 4000.0 - std::cos(temp) + 1.0;
    }
    tmp1 = z[nx - 1] * z[nx - 1] - z[0];
    tmp2 = z[nx - 1] - 1.0;
    temp = 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
    f[0] += (temp * temp) / 4000.0 - std::cos(temp) + 1.0;
}

void escaffer6_func(const double* x, double* f, int nx, const double* Os,
                    const double* Mr, int r_flag, const Scratch& s) { /* Expanded Schaffer's F6 */
    double* y = s.y;
    double* z = s.z;
    double temp1, temp2;
    shiftfunc(x, y, nx, Os);
    if (r_flag == 1)
        rotatefunc(y, z, nx, Mr);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    asyfunc(z, y, nx, 0.5); // y still holds the shift output (reference quirk)
    if (r_flag == 1)
        rotatefunc(y, z, nx, &Mr[nx * nx]);
    else
        for (int i = 0; i < nx; i++)
            z[i] = y[i];

    f[0] = 0.0;
    for (int i = 0; i < nx - 1; i++) {
        temp1 = std::sin(std::sqrt(z[i] * z[i] + z[i + 1] * z[i + 1]));
        temp1 = temp1 * temp1;
        temp2 = 1.0 + 0.001 * (z[i] * z[i] + z[i + 1] * z[i + 1]);
        f[0] += 0.5 + (temp1 - 0.5) / (temp2 * temp2);
    }
    temp1 = std::sin(std::sqrt(z[nx - 1] * z[nx - 1] + z[0] * z[0]));
    temp1 = temp1 * temp1;
    temp2 = 1.0 + 0.001 * (z[nx - 1] * z[nx - 1] + z[0] * z[0]);
    f[0] += 0.5 + (temp1 - 0.5) / (temp2 * temp2);
}

/* ------------------------------------------------------------------ */
/* Composition machinery (verbatim ports of test_func.c)               */
/* ------------------------------------------------------------------ */

void cf_cal(const double* x, double* f, int nx, const double* Os,
            const double* delta, const double* bias, double* fit, int cf_num) {
    double w[5]; // cf_num <= 5 for every composition in this suite
    double w_max = 0, w_sum = 0;
    for (int i = 0; i < cf_num; i++) {
        fit[i] += bias[i];
        w[i] = 0;
        for (int j = 0; j < nx; j++) {
            // pow(diff, 2.0) -> diff*diff (GROUP B, <=1 ULP). Per-term rewrite;
            // the accumulation order of w[i] is unchanged.
            const double diff = x[j] - Os[i * nx + j];
            w[i] += diff * diff;
        }
        if (w[i] != 0)
            // pow(1/w,0.5) -> sqrt(1/w); pow(delta,2.0) -> delta*delta (GROUP B).
            w[i] = std::sqrt(1.0 / w[i]) * std::exp(-w[i] / 2.0 / nx / (delta[i] * delta[i]));
        else
            w[i] = kInf;
        if (w[i] > w_max)
            w_max = w[i];
    }

    for (int i = 0; i < cf_num; i++) {
        w_sum = w_sum + w[i];
    }
    if (w_max == 0) {
        for (int i = 0; i < cf_num; i++)
            w[i] = 1;
        w_sum = cf_num;
    }
    f[0] = 0.0;
    for (int i = 0; i < cf_num; i++) {
        f[0] = f[0] + w[i] / w_sum * fit[i];
    }
}

void cf01(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 1 */
    int i;
    const int cf_num = 5;
    double fit[5];
    const double delta[5] = {10, 20, 30, 40, 50};
    const double bias[5] = {0, 100, 200, 300, 400};

    i = 0;
    rosenbrock_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 1e+4;
    i = 1;
    dif_powers_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 1e+10;
    i = 2;
    bent_cigar_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 1e+30;
    i = 3;
    discus_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 1e+10;
    i = 4;
    sphere_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], 0, s);
    fit[i] = 10000 * fit[i] / 1e+5;
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf02(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 2 */
    const int cf_num = 3;
    double fit[3];
    const double delta[3] = {20, 20, 20};
    const double bias[3] = {0, 100, 200};
    for (int i = 0; i < cf_num; i++) {
        schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    }
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf03(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 3 */
    const int cf_num = 3;
    double fit[3];
    const double delta[3] = {20, 20, 20};
    const double bias[3] = {0, 100, 200};
    for (int i = 0; i < cf_num; i++) {
        schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    }
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf04(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 4 */
    int i;
    const int cf_num = 3;
    double fit[3];
    const double delta[3] = {20, 20, 20};
    const double bias[3] = {0, 100, 200};
    i = 0;
    schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 4e+3;
    i = 1;
    rastrigin_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 1e+3;
    i = 2;
    weierstrass_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 400;
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf05(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 5 */
    int i;
    const int cf_num = 3;
    double fit[3];
    const double delta[3] = {10, 30, 50};
    const double bias[3] = {0, 100, 200};
    i = 0;
    schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 4e+3;
    i = 1;
    rastrigin_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 1e+3;
    i = 2;
    weierstrass_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 400;
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf06(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 6 */
    int i;
    const int cf_num = 5;
    double fit[5];
    const double delta[5] = {10, 10, 10, 10, 10};
    const double bias[5] = {0, 100, 200, 300, 400};
    i = 0;
    schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 4e+3;
    i = 1;
    rastrigin_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 1e+3;
    i = 2;
    ellips_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 1e+10;
    i = 3;
    weierstrass_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 400;
    i = 4;
    griewank_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 1000 * fit[i] / 100;
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf07(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 7 */
    int i;
    const int cf_num = 5;
    double fit[5];
    const double delta[5] = {10, 10, 10, 20, 20};
    const double bias[5] = {0, 100, 200, 300, 400};
    i = 0;
    griewank_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 100;
    i = 1;
    rastrigin_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 1e+3;
    i = 2;
    schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 4e+3;
    i = 3;
    weierstrass_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 400;
    i = 4;
    sphere_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], 0, s);
    fit[i] = 10000 * fit[i] / 1e+5;
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

void cf08(const double* x, double* f, int nx, const double* Os,
          const double* Mr, int r_flag, const Scratch& s) { /* Composition Function 8 */
    int i;
    const int cf_num = 5;
    double fit[5];
    const double delta[5] = {10, 20, 30, 40, 50};
    const double bias[5] = {0, 100, 200, 300, 400};
    i = 0;
    grie_rosen_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 4e+3;
    i = 1;
    schaffer_F7_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 4e+6;
    i = 2;
    schwefel_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 4e+3;
    i = 3;
    escaffer6_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], r_flag, s);
    fit[i] = 10000 * fit[i] / 2e+7;
    i = 4;
    sphere_func(x, &fit[i], nx, &Os[i * nx], &Mr[i * nx * nx], 0, s);
    fit[i] = 10000 * fit[i] / 1e+5;
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

/* ------------------------------------------------------------------ */
/* Problem wrapper                                                     */
/* ------------------------------------------------------------------ */

class Cec2013Problem final : public BenchmarkProblem {
public:
    Cec2013Problem(int function_id, int dimension, const std::filesystem::path& data_root)
        : function_id_(function_id), nx_(dimension) {
        const std::vector<int>& functions = supported_functions();
        if (std::find(functions.begin(), functions.end(), function_id) == functions.end()) {
            throw std::invalid_argument("cec2013: function_id must be an integer in 1..28, got " +
                                        std::to_string(function_id) + ".");
        }
        const std::vector<int>& dimensions = supported_dimensions();
        if (std::find(dimensions.begin(), dimensions.end(), dimension) == dimensions.end()) {
            throw std::invalid_argument(
                "cec2013: unsupported dimension " + std::to_string(dimension) +
                " (allowed: 2, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100).");
        }

        // test_func.c reads exactly cf_num*nx*nx values from M_D<nx>.txt and
        // cf_num*nx values from shift_data.txt (cf_num == 10), ignoring any
        // surplus. shift_data.txt is read FLAT: for nx < 100 the composition
        // shift rows are consecutive nx-value slices of the flattened
        // 10 x 100 table, not per-line prefixes (reference behaviour).
        const auto n = static_cast<std::size_t>(nx_);
        const auto tables = static_cast<std::size_t>(kTableCount);
        rotations_ = load_values_file(data_root / ("M_D" + std::to_string(nx_) + ".txt"),
                                      tables * n * n);
        shifts_ = load_values_file(data_root / "shift_data.txt", tables * n);

        y_.resize(n);
        z_.resize(n);
        tmpx_.resize(n);
    }

    std::string suite_name() const override { return "cec2013"; }

    int function_id() const override { return function_id_; }

    int dimension() const override { return nx_; }

    Bounds bounds() const override {
        return Bounds::uniform(static_cast<Index>(nx_), -100.0, 100.0);
    }

    Real optimum() const override { return kBias[function_id_ - 1]; }

    // NOT thread-safe: reuses the per-instance scratch buffers below.
    Real evaluate(std::span<const Real> x) const override {
        if (x.size() != static_cast<std::size_t>(nx_)) {
            throw std::invalid_argument("cec2013: expected a vector of dimension " +
                                        std::to_string(nx_) + ", got " +
                                        std::to_string(x.size()) + ".");
        }
        const Scratch s{y_.data(), z_.data(), tmpx_.data()};
        const double* xs = x.data();
        const double* Os = shifts_.data();
        const double* Mr = rotations_.data();
        const int nx = nx_;
        double f = 0.0;

        // Dispatch and r_flag values transcribed from test_func() in
        // test_func.c; the per-case bias addition is applied after the
        // switch via kBias (same literals, same final operation).
        switch (function_id_) {
        case 1:
            sphere_func(xs, &f, nx, Os, Mr, 0, s);
            break;
        case 2:
            ellips_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 3:
            bent_cigar_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 4:
            discus_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 5:
            dif_powers_func(xs, &f, nx, Os, Mr, 0, s);
            break;
        case 6:
            rosenbrock_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 7:
            schaffer_F7_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 8:
            ackley_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 9:
            weierstrass_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 10:
            griewank_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 11:
            rastrigin_func(xs, &f, nx, Os, Mr, 0, s);
            break;
        case 12:
            rastrigin_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 13:
            step_rastrigin_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 14:
            schwefel_func(xs, &f, nx, Os, Mr, 0, s);
            break;
        case 15:
            schwefel_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 16:
            katsuura_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 17:
            bi_rastrigin_func(xs, &f, nx, Os, Mr, 0, s);
            break;
        case 18:
            bi_rastrigin_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 19:
            grie_rosen_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 20:
            escaffer6_func(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 21:
            cf01(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 22:
            cf02(xs, &f, nx, Os, Mr, 0, s);
            break;
        case 23:
            cf03(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 24:
            cf04(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 25:
            cf05(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 26:
            cf06(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 27:
            cf07(xs, &f, nx, Os, Mr, 1, s);
            break;
        case 28:
            cf08(xs, &f, nx, Os, Mr, 1, s);
            break;
        default:
            throw std::invalid_argument("cec2013: function_id must be in 1..28.");
        }
        return f + kBias[function_id_ - 1];
    }

private:
    int function_id_ = 0;
    int nx_ = 0;
    Vector rotations_;     // M: kTableCount row-major nx*nx matrices, flat
    Vector shifts_;        // OShift: flat kTableCount*nx prefix of shift_data.txt
    mutable Vector y_;     // scratch (global y in the reference)
    mutable Vector z_;     // scratch (global z in the reference)
    mutable Vector tmpx_;  // scratch (bi_rastrigin_func tmpx in the reference)
};

} // namespace

std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root) {
    return std::make_unique<Cec2013Problem>(function_id, dimension, data_root);
}

const std::vector<int>& supported_functions() {
    static const std::vector<int> functions = [] {
        std::vector<int> ids(28);
        for (int i = 0; i < 28; ++i) {
            ids[static_cast<std::size_t>(i)] = i + 1;
        }
        return ids;
    }();
    return functions;
}

const std::vector<int>& supported_dimensions() {
    // Dimension whitelist of the reference R wrapper (R/cec2013.R).
    static const std::vector<int> dimensions = {2, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100};
    return dimensions;
}

} // namespace gskcec::cec2013
