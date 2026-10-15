// Standalone C++20 port of the CEC2020 single-objective bound-constrained
// benchmark suite (10 public functions, D in {5, 10, 15, 20}).
//
// Reference (sole source of behavioral truth):
//   historical source: CEC2020 competition cec20_func.cpp
//   (MATLAB MEX evaluator; an identical staged copy lives
//   next to this file as cec20_func.cpp and is never compiled).
//
// Port notes
//   * Public function ids 1..10 map to internal data-file ids via
//     Func_num[] = {1, 2, 3, 7, 4, 16, 6, 22, 24, 25} exactly as in the
//     reference. Data files are named by the INTERNAL id.
//   * Only the code reachable through those 10 internal ids is ported
//     (basic functions, hf01/hf05/hf06, cf02/cf04/cf05, cf_cal and the
//     shift/rotate helpers). The remaining MEX cases are dead code here.
//   * Numerics, loop order and the reference quirks are preserved:
//       - public F4 (internal 7) evaluates grie_rosen with s_flag = 0 and
//         r_flag = 0, i.e. the loaded shift/rotation data is NOT applied;
//       - public F7 (internal 6, hf05) at D = 5 partitions into
//         G_nx = {0, 1, 1, 1, 2}; the zero-width escaffer6 slice reads
//         z[nx-1] == z[-1] in the MEX (out-of-bounds heap read). The port
//         reproduces the recorded MEX behavior with a guard slot holding
//         0.0 immediately before the z scratch buffer (see z_storage_);
//       - composition shift files are consumed line-wise (first nx values
//         of each of the 10 rows, remainder of the row skipped).
//   * Per-instance RAII state, loaded once in the constructor. Mutable
//     scratch buffers mirror the MEX globals y/z, therefore evaluate() is
//     NOT thread-safe on a shared instance; use one instance per thread.
//   * std::invalid_argument for bad ids/dimensions, std::runtime_error
//     (naming the file) for missing/bad data.

#include "gskcec/benchmark/cec2020.hpp"

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

namespace gskcec::cec2020 {
namespace {

using std::ceil;
using std::cos;
using std::exp;
using std::fabs;
using std::floor;
using std::fmod;
using std::pow;
using std::sin;
using std::sqrt;

constexpr double kInf = 1.0e99; // INF in the reference
constexpr double kE = 2.7182818284590452353602874713526625;
constexpr double kPi = 3.1415926535897932384626433832795029;

// Reference: int Func_num[] = {1,2,3,7,4,16,6,22,24,25}; (cec20_test_func)
constexpr int kInternalId[10] = {1, 2, 3, 7, 4, 16, 6, 22, 24, 25};

// AGSK reference optimum vector (Adaptive_GSK_ALI.m, line 39). Verified to
// equal the per-case bias the MEX adds for each reachable internal id.
constexpr double kOptimum[10] = {100.0,  1100.0, 700.0,  1900.0, 1700.0,
                                 1600.0, 2100.0, 2200.0, 2400.0, 2500.0};

// The MEX loader always reads 10 shift rows / 10 rotation blocks for
// composition functions (int cf_num = 10 in cec20_test_func).
constexpr int kLoaderCfNum = 10;

// Scratch buffers standing in for the MEX globals y and z (and the local
// tmpx malloc in bi_rastrigin). z points one past a guard slot that holds
// 0.0 so that the reference's z[-1] read (hf05 at D=5, see header comment)
// stays in-bounds and deterministic.
struct Scratch {
    double* y;
    double* z;
    double* tmpx;
};

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

/* shift and rotate (uses sc.y as the intermediate buffer like the global y) */
void sr_func(const double* x, double* sr_x, int nx, const double* Os, const double* Mr,
             double sh_rate, int s_flag, int r_flag, Scratch& sc) {
    double* y = sc.y;
    if (s_flag == 1) {
        if (r_flag == 1) {
            shiftfunc(x, y, nx, Os);
            for (int i = 0; i < nx; i++) {
                y[i] = y[i] * sh_rate;
            }
            rotatefunc(y, sr_x, nx, Mr);
        } else {
            shiftfunc(x, sr_x, nx, Os);
            for (int i = 0; i < nx; i++) {
                sr_x[i] = sr_x[i] * sh_rate;
            }
        }
    } else {
        if (r_flag == 1) {
            for (int i = 0; i < nx; i++) {
                y[i] = x[i] * sh_rate;
            }
            rotatefunc(y, sr_x, nx, Mr);
        } else {
            for (int i = 0; i < nx; i++) {
                sr_x[i] = x[i] * sh_rate;
            }
        }
    }
}

/* Bent_Cigar */
void bent_cigar_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                     int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);
    // pow(10.0, 6.0) is loop-invariant; hoist it (== 1000000.0 exactly, so the
    // per-dimension products stay bit-identical to the reference).
    const double c6 = pow(10.0, 6.0);
    f[0] = z[0] * z[0];
    for (int i = 1; i < nx; i++) {
        f[0] += c6 * z[i] * z[i];
    }
}

/* Discus */
void discus_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                 int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);
    // pow(10.0, 6.0) == 1000000.0 exactly; compute once (bit-identical).
    const double c6 = pow(10.0, 6.0);
    f[0] = c6 * z[0] * z[0];
    for (int i = 1; i < nx; i++) {
        f[0] += z[i] * z[i];
    }
}

// Returns the per-i ellipsoidal coefficients pow(10.0, 6.0*i/(nx-1)), cached
// per distinct nx. ellips_func is reused at hybrid/composition sub-dimensions
// (hf01, hf05, cf04), so distinct nx values occur. Bit-identical: the cached
// values are the exact pow results. thread_local matches the documented
// "one problem instance per thread" contract.
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
            c[static_cast<std::size_t>(i)] = pow(10.0, 6.0 * i / (nx - 1));
        }
    }
    return c.data();
}

/* Ellipsoidal */
void ellips_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                 int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    f[0] = 0.0;
    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);
    const double* coef = ellips_coef(nx);
    for (int i = 0; i < nx; i++) {
        f[0] += coef[i] * z[i] * z[i];
    }
}

/* Rosenbrock's */
void rosenbrock_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                     int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    double tmp1, tmp2;
    f[0] = 0.0;
    sr_func(x, z, nx, Os, Mr, 2.048 / 100.0, s_flag, r_flag, sc);
    z[0] += 1.0; // shift to origin
    for (int i = 0; i < nx - 1; i++) {
        z[i + 1] += 1.0; // shift to origin
        tmp1 = z[i] * z[i] - z[i + 1];
        tmp2 = z[i] - 1.0;
        f[0] += 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
    }
}

/* Ackley's */
void ackley_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                 int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    double sum1 = 0.0;
    double sum2 = 0.0;
    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);
    for (int i = 0; i < nx; i++) {
        sum1 += z[i] * z[i];
        sum2 += cos(2.0 * kPi * z[i]);
    }
    sum1 = -0.2 * sqrt(sum1 / nx);
    sum2 /= nx;
    f[0] = kE - 20.0 * exp(sum1) - exp(sum2) + 20.0;
}

/* Griewank's */
void griewank_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                   int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    double s = 0.0;
    double p = 1.0;
    sr_func(x, z, nx, Os, Mr, 600.0 / 100.0, s_flag, r_flag, sc);
    for (int i = 0; i < nx; i++) {
        s += z[i] * z[i];
        p *= cos(z[i] / sqrt(1.0 + i));
    }
    f[0] = 1.0 + s / 4000.0 - p;
}

/* Rastrigin's */
void rastrigin_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                    int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    f[0] = 0.0;
    sr_func(x, z, nx, Os, Mr, 5.12 / 100.0, s_flag, r_flag, sc);
    for (int i = 0; i < nx; i++) {
        f[0] += (z[i] * z[i] - 10.0 * cos(2.0 * kPi * z[i]) + 10.0);
    }
}

/* Schwefel's */
void schwefel_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                   int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    double tmp;
    f[0] = 0.0;
    sr_func(x, z, nx, Os, Mr, 1000.0 / 100.0, s_flag, r_flag, sc);
    for (int i = 0; i < nx; i++) {
        z[i] += 4.209687462275036e+002;
        if (z[i] > 500) {
            f[0] -= (500.0 - fmod(z[i], 500)) * sin(pow(500.0 - fmod(z[i], 500), 0.5));
            tmp = (z[i] - 500.0) / 100;
            f[0] += tmp * tmp / nx;
        } else if (z[i] < -500) {
            f[0] -= (-500.0 + fmod(fabs(z[i]), 500)) * sin(pow(500.0 - fmod(fabs(z[i]), 500), 0.5));
            tmp = (z[i] + 500.0) / 100;
            f[0] += tmp * tmp / nx;
        } else {
            f[0] -= z[i] * sin(pow(fabs(z[i]), 0.5));
        }
    }
    f[0] += 4.189828872724338e+002 * nx;
}

/* Lunacek Bi_rastrigin Function */
void bi_rastrigin_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                       int s_flag, int r_flag, Scratch& sc) {
    double* y = sc.y;
    double* z = sc.z;
    double* tmpx = sc.tmpx;
    const double mu0 = 2.5, d = 1.0;
    double tmp, tmp1, tmp2;
    const double s = 1.0 - 1.0 / (2.0 * pow(nx + 20.0, 0.5) - 8.2);
    const double mu1 = -pow((mu0 * mu0 - d) / s, 0.5);

    if (s_flag == 1) {
        shiftfunc(x, y, nx, Os);
    } else {
        for (int i = 0; i < nx; i++) {
            y[i] = x[i];
        }
    }
    for (int i = 0; i < nx; i++) { // shrink to the original search range
        y[i] *= 10.0 / 100.0;
    }

    for (int i = 0; i < nx; i++) {
        tmpx[i] = 2 * y[i];
        if (Os[i] < 0.0) {
            tmpx[i] *= -1.;
        }
    }
    for (int i = 0; i < nx; i++) {
        z[i] = tmpx[i];
        tmpx[i] += mu0;
    }
    tmp1 = 0.0;
    tmp2 = 0.0;
    for (int i = 0; i < nx; i++) {
        tmp = tmpx[i] - mu0;
        tmp1 += tmp * tmp;
        tmp = tmpx[i] - mu1;
        tmp2 += tmp * tmp;
    }
    tmp2 *= s;
    tmp2 += d * nx;
    tmp = 0.0;

    if (r_flag == 1) {
        rotatefunc(z, y, nx, Mr);
        for (int i = 0; i < nx; i++) {
            tmp += cos(2.0 * kPi * y[i]);
        }
        if (tmp1 < tmp2) {
            f[0] = tmp1;
        } else {
            f[0] = tmp2;
        }
        f[0] += 10.0 * (nx - tmp);
    } else {
        for (int i = 0; i < nx; i++) {
            tmp += cos(2.0 * kPi * z[i]);
        }
        if (tmp1 < tmp2) {
            f[0] = tmp1;
        } else {
            f[0] = tmp2;
        }
        f[0] += 10.0 * (nx - tmp);
    }
}

/* Griewank-Rosenbrock */
void grie_rosen_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                     int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    double temp, tmp1, tmp2;
    f[0] = 0.0;
    sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag, sc);
    z[0] += 1.0; // shift to origin
    for (int i = 0; i < nx - 1; i++) {
        z[i + 1] += 1.0; // shift to origin
        tmp1 = z[i] * z[i] - z[i + 1];
        tmp2 = z[i] - 1.0;
        temp = 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
        f[0] += (temp * temp) / 4000.0 - cos(temp) + 1.0;
    }
    tmp1 = z[nx - 1] * z[nx - 1] - z[0];
    tmp2 = z[nx - 1] - 1.0;
    temp = 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
    f[0] += (temp * temp) / 4000.0 - cos(temp) + 1.0;
}

/* Expanded Schaffer's F6.
   When nx == 0 (hf05 zero-width slice at D=5) the loop is skipped and the
   wrap-around term reads z[nx-1] == z[-1]: in the MEX that is an
   out-of-bounds heap read; here it lands on the 0.0 guard slot. */
void escaffer6_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                    int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    double temp1, temp2;
    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);
    f[0] = 0.0;
    for (int i = 0; i < nx - 1; i++) {
        temp1 = sin(sqrt(z[i] * z[i] + z[i + 1] * z[i + 1]));
        temp1 = temp1 * temp1;
        temp2 = 1.0 + 0.001 * (z[i] * z[i] + z[i + 1] * z[i + 1]);
        f[0] += 0.5 + (temp1 - 0.5) / (temp2 * temp2);
    }
    temp1 = sin(sqrt(z[nx - 1] * z[nx - 1] + z[0] * z[0]));
    temp1 = temp1 * temp1;
    temp2 = 1.0 + 0.001 * (z[nx - 1] * z[nx - 1] + z[0] * z[0]);
    f[0] += 0.5 + (temp1 - 0.5) / (temp2 * temp2);
}

/* HappyCat */
void happycat_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                   int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    const double alpha = 1.0 / 8.0;
    sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag, sc);
    double r2 = 0.0;
    double sum_z = 0.0;
    for (int i = 0; i < nx; i++) {
        z[i] = z[i] - 1.0; // shift to origin
        r2 += z[i] * z[i];
        sum_z += z[i];
    }
    f[0] = pow(fabs(r2 - nx), 2 * alpha) + (0.5 * r2 + sum_z) / nx + 0.5;
}

/* HGBat */
void hgbat_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                int s_flag, int r_flag, Scratch& sc) {
    double* z = sc.z;
    const double alpha = 1.0 / 4.0;
    sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag, sc);
    double r2 = 0.0;
    double sum_z = 0.0;
    for (int i = 0; i < nx; i++) {
        z[i] = z[i] - 1.0; // shift to origin
        r2 += z[i] * z[i];
        sum_z += z[i];
    }
    // pow(r2,2.0) -> r2*r2 and pow(sum_z,2.0) -> sum_z*sum_z (GROUP B, <=1 ULP).
    f[0] = pow(fabs(r2 * r2 - sum_z * sum_z), 2 * alpha) + (0.5 * r2 + sum_z) / nx + 0.5;
}

/* Hybrid Function 1 (internal 4; F17/hf01 in CEC2014).
   NOTE: the partition loop starts at i = 1; G_nx[0] takes the remainder. */
void hf01(const double* x, double* f, int nx, const double* Os, const double* Mr,
          const int* S, int s_flag, int r_flag, Scratch& sc) {
    double* y = sc.y;
    double* z = sc.z;
    const int cf_num = 3;
    double fit[3];
    int G[3], G_nx[3];
    const double Gp[3] = {0.3, 0.3, 0.4};

    int tmp = 0;
    for (int i = 1; i < cf_num; i++) {
        G_nx[i] = static_cast<int>(ceil(Gp[i] * nx));
        tmp += G_nx[i];
    }
    G_nx[0] = nx - tmp;
    G[0] = 0;
    for (int i = 1; i < cf_num; i++) {
        G[i] = G[i - 1] + G_nx[i - 1];
    }

    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);

    for (int i = 0; i < nx; i++) {
        y[i] = z[S[i] - 1];
    }
    schwefel_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0, sc);
    rastrigin_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0, sc);
    ellips_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0, sc);

    f[0] = 0.0;
    for (int i = 0; i < cf_num; i++) {
        f[0] += fit[i];
    }
}

/* Hybrid Function 5 (internal 6; F21/hf05 in CEC2014).
   NOTE: the partition loop starts at i = 1; G_nx[0] takes the remainder.
   At D = 5 this yields G_nx = {0, 1, 1, 1, 2} (zero-width escaffer6). */
void hf05(const double* x, double* f, int nx, const double* Os, const double* Mr,
          const int* S, int s_flag, int r_flag, Scratch& sc) {
    double* y = sc.y;
    double* z = sc.z;
    const int cf_num = 5;
    double fit[5];
    int G[5], G_nx[5];
    const double Gp[5] = {0.1, 0.2, 0.2, 0.2, 0.3};

    int tmp = 0;
    for (int i = 1; i < cf_num; i++) {
        G_nx[i] = static_cast<int>(ceil(Gp[i] * nx));
        tmp += G_nx[i];
    }
    G_nx[0] = nx - tmp;
    G[0] = 0;
    for (int i = 1; i < cf_num; i++) {
        G[i] = G[i - 1] + G_nx[i - 1];
    }

    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);

    for (int i = 0; i < nx; i++) {
        y[i] = z[S[i] - 1];
    }
    escaffer6_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0, sc);
    hgbat_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0, sc);
    rosenbrock_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0, sc);
    schwefel_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0, sc);
    ellips_func(&y[G[4]], &fit[4], G_nx[4], Os, Mr, 0, 0, sc);

    f[0] = 0.0;
    for (int i = 0; i < cf_num; i++) {
        f[0] += fit[i];
    }
}

/* Hybrid Function 6 (internal 16; hf06 in CEC2014).
   NOTE: unlike hf01/hf05 the partition loop starts at i = 0 and the LAST
   group takes the remainder. */
void hf06(const double* x, double* f, int nx, const double* Os, const double* Mr,
          const int* S, int s_flag, int r_flag, Scratch& sc) {
    double* y = sc.y;
    double* z = sc.z;
    const int cf_num = 4;
    double fit[4];
    int G[4], G_nx[4];
    const double Gp[4] = {0.2, 0.2, 0.3, 0.3};

    int tmp = 0;
    for (int i = 0; i < cf_num - 1; i++) {
        G_nx[i] = static_cast<int>(ceil(Gp[i] * nx));
        tmp += G_nx[i];
    }
    G_nx[cf_num - 1] = nx - tmp;
    G[0] = 0;
    for (int i = 1; i < cf_num; i++) {
        G[i] = G[i - 1] + G_nx[i - 1];
    }

    sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag, sc);

    for (int i = 0; i < nx; i++) {
        y[i] = z[S[i] - 1];
    }
    escaffer6_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0, sc);
    hgbat_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0, sc);
    rosenbrock_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0, sc);
    schwefel_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0, sc);

    f[0] = 0.0;
    for (int i = 0; i < cf_num; i++) {
        f[0] += fit[i];
    }
}

/* Composition weight aggregation (cf_cal in the reference). */
void cf_cal(const double* x, double* f, int nx, const double* Os, const double* delta,
            const double* bias, double* fit, int cf_num) {
    double w[kLoaderCfNum]; // reference mallocs cf_num doubles; cf_num <= 10
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
        if (w[i] != 0) {
            // pow(1/w,0.5) -> sqrt(1/w); pow(delta,2.0) -> delta*delta (GROUP B).
            w[i] = sqrt(1.0 / w[i]) * exp(-w[i] / 2.0 / nx / (delta[i] * delta[i]));
        } else {
            w[i] = kInf;
        }
        if (w[i] > w_max) {
            w_max = w[i];
        }
    }
    for (int i = 0; i < cf_num; i++) {
        w_sum = w_sum + w[i];
    }
    if (w_max == 0) {
        for (int i = 0; i < cf_num; i++) {
            w[i] = 1;
        }
        w_sum = cf_num;
    }
    f[0] = 0.0;
    for (int i = 0; i < cf_num; i++) {
        f[0] = f[0] + w[i] / w_sum * fit[i];
    }
}

/* Composition Function 2 (internal 22) */
void cf02(const double* x, double* f, int nx, const double* Os, const double* Mr,
          int r_flag, Scratch& sc) {
    const int cf_num = 3;
    double fit[3];
    double delta[3] = {10, 20, 30};
    double bias[3] = {0, 100, 200};

    rastrigin_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag, sc);
    griewank_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag, sc);
    fit[1] = 1000 * fit[1] / 100;
    schwefel_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag, sc);
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

/* Composition Function 4 (internal 24) */
void cf04(const double* x, double* f, int nx, const double* Os, const double* Mr,
          int r_flag, Scratch& sc) {
    const int cf_num = 4;
    double fit[4];
    double delta[4] = {10, 20, 30, 40};
    double bias[4] = {0, 100, 200, 300};

    ackley_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag, sc);
    fit[0] = 1000 * fit[0] / 100;
    ellips_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag, sc);
    fit[1] = 10000 * fit[1] / 1e+10;
    griewank_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag, sc);
    fit[2] = 1000 * fit[2] / 100;
    rastrigin_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag, sc);
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

/* Composition Function 5 (internal 25) */
void cf05(const double* x, double* f, int nx, const double* Os, const double* Mr,
          int r_flag, Scratch& sc) {
    const int cf_num = 5;
    double fit[5];
    double delta[5] = {10, 20, 30, 40, 50};
    double bias[5] = {0, 100, 200, 300, 400};

    rastrigin_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag, sc);
    fit[0] = 10000 * fit[0] / 1e+3;
    happycat_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag, sc);
    fit[1] = 1000 * fit[1] / 1e+3;
    ackley_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag, sc);
    fit[2] = 1000 * fit[2] / 100;
    discus_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag, sc);
    fit[3] = 10000 * fit[3] / 1e+10;
    rosenbrock_func(x, &fit[4], nx, &Os[4 * nx], &Mr[4 * nx * nx], 1, r_flag, sc);
    cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
}

class Cec2020Problem final : public BenchmarkProblem {
public:
    Cec2020Problem(int function_id, int dimension, const std::filesystem::path& data_root) {
        const auto& functions = supported_functions();
        if (std::find(functions.begin(), functions.end(), function_id) == functions.end()) {
            throw std::invalid_argument("CEC2020 function id must be in 1..10, got " +
                                        std::to_string(function_id) + ".");
        }
        const auto& dimensions = supported_dimensions();
        if (std::find(dimensions.begin(), dimensions.end(), dimension) == dimensions.end()) {
            throw std::invalid_argument("CEC2020 dimension must be one of {5, 10, 15, 20}, got " +
                                        std::to_string(dimension) + ".");
        }
        public_id_ = function_id;
        internal_id_ = kInternalId[function_id - 1];
        nx_ = dimension;

        const int nx = nx_;
        const std::string id = std::to_string(internal_id_);
        const std::string dim = std::to_string(nx);
        // Reference loader branch: func_num < 20 loads one rotation block and
        // one shift row; func_num >= 20 (compositions) loads cf_num = 10 of each.
        const bool composition = internal_id_ >= 20;

        /* Load Matrix M (M_<id>_D<D>.txt). The MEX reads exactly nx*nx
           (or 10*nx*nx) values; extra trailing values would be ignored. */
        const std::filesystem::path m_path = data_root / ("M_" + id + "_D" + dim + ".txt");
        const std::size_t m_count = composition
            ? static_cast<std::size_t>(kLoaderCfNum) * nx * nx
            : static_cast<std::size_t>(nx) * nx;
        rotation_ = load_values_file(m_path, m_count);

        /* Load shift data (shift_data_<id>.txt). Single functions: the first
           nx values of the file. Compositions: the first nx values of EACH of
           the 10 rows (the MEX reads nx values per row, then skips the rest
           of the line). Rows are uniform width in the shipped data, so the
           row stride is total / 10. */
        const std::filesystem::path shift_path = data_root / ("shift_data_" + id + ".txt");
        if (!composition) {
            shift_ = load_values_file(shift_path, static_cast<std::size_t>(nx));
        } else {
            const Vector flat = load_values_file(shift_path);
            if (flat.size() % kLoaderCfNum != 0) {
                throw std::runtime_error("Composition shift file " + shift_path.string() +
                                         " holds " + std::to_string(flat.size()) +
                                         " values, not divisible into " +
                                         std::to_string(kLoaderCfNum) + " uniform rows.");
            }
            const std::size_t stride = flat.size() / kLoaderCfNum;
            if (stride < static_cast<std::size_t>(nx)) {
                throw std::runtime_error("Composition shift file " + shift_path.string() +
                                         " rows hold " + std::to_string(stride) +
                                         " values, expected at least " + dim + ".");
            }
            shift_.resize(static_cast<std::size_t>(kLoaderCfNum) * nx);
            for (int i = 0; i < kLoaderCfNum; i++) {
                for (int j = 0; j < nx; j++) {
                    shift_[static_cast<std::size_t>(i) * nx + j] =
                        flat[static_cast<std::size_t>(i) * stride + j];
                }
            }
        }

        /* Shuffle data (shuffle_data_<id>_D<D>.txt). Only internal ids
           4, 6 and 16 consume it (reference condition: func_num==4 ||
           func_num==6 || 11..20), but the CEC2020 data distribution defines
           per-dimension availability through these files for EVERY internal
           id: ids 1 and 22 ship no D5/D15 shuffle files, which is exactly
           why the reference protocol (and the MEX ground truth) excludes
           those combinations. Availability therefore stays data-driven:
           the file must exist for every (function, dimension). */
        const std::filesystem::path shuffle_path =
            data_root / ("shuffle_data_" + id + "_D" + dim + ".txt");
        require_file(shuffle_path);
        const bool uses_shuffle = internal_id_ == 4 || internal_id_ == 6 ||
                                  (internal_id_ >= 11 && internal_id_ <= 20);
        if (uses_shuffle) {
            const Vector raw = load_values_file(shuffle_path, static_cast<std::size_t>(nx));
            shuffle_.resize(nx);
            for (int i = 0; i < nx; i++) {
                const int v = static_cast<int>(raw[static_cast<std::size_t>(i)]);
                if (v < 1 || v > nx) {
                    throw std::runtime_error("Shuffle index " + std::to_string(v) +
                                             " out of range 1.." + dim + " in data file: " +
                                             shuffle_path.string());
                }
                shuffle_[static_cast<std::size_t>(i)] = v;
            }
        }

        y_.assign(static_cast<std::size_t>(nx), 0.0);
        // One guard slot BEFORE the z buffer: the reference reads z[-1] for
        // the zero-width escaffer6 slice of hf05 at D=5 (see header comment).
        z_storage_.assign(static_cast<std::size_t>(nx) + 1, 0.0);
        tmpx_.assign(static_cast<std::size_t>(nx), 0.0);
    }

    std::string suite_name() const override { return "cec2020"; }

    int function_id() const override { return public_id_; }

    int dimension() const override { return nx_; }

    Bounds bounds() const override {
        return Bounds::uniform(static_cast<Index>(nx_), -100.0, 100.0);
    }

    Real optimum() const override { return kOptimum[public_id_ - 1]; }

    /// Not thread-safe: shares the mutable y/z scratch buffers across calls.
    Real evaluate(std::span<const Real> x) const override {
        if (x.size() != static_cast<std::size_t>(nx_)) {
            throw std::invalid_argument("CEC2020 evaluate expected dimension " +
                                        std::to_string(nx_) + ", got " +
                                        std::to_string(x.size()) + ".");
        }
        Scratch sc{y_.data(), z_storage_.data() + 1, tmpx_.data()};
        const double* px = x.data();
        const double* Os = shift_.data();
        const double* Mr = rotation_.data();
        const int* SS = shuffle_.empty() ? nullptr : shuffle_.data();
        const int nx = nx_;
        double f = 0.0;
        // Per-case bias constants transcribed from the reference switch; they
        // equal the AGSK optimum vector (kOptimum), which the tests verify.
        switch (internal_id_) {
        case 1: // public F1: Bent Cigar
            bent_cigar_func(px, &f, nx, Os, Mr, 1, 1, sc);
            f += 100.0;
            break;
        case 2: // public F2: Schwefel (F11 in CEC2014)
            schwefel_func(px, &f, nx, Os, Mr, 1, 1, sc);
            f += 1100.0;
            break;
        case 3: // public F3: Lunacek bi-Rastrigin (F7 in CEC2017)
            bi_rastrigin_func(px, &f, nx, Os, Mr, 1, 1, sc);
            f += 700.0;
            break;
        case 7: // public F4: Griewank-Rosenbrock, UNSHIFTED/UNROTATED (flags 0,0)
            grie_rosen_func(px, &f, nx, Os, Mr, 0, 0, sc);
            f += 1900.0;
            break;
        case 4: // public F5: Hybrid 1 (F17 in CEC2014)
            hf01(px, &f, nx, Os, Mr, SS, 1, 1, sc);
            f += 1700.0;
            break;
        case 16: // public F6: Hybrid 2 (hf06 in CEC2014)
            hf06(px, &f, nx, Os, Mr, SS, 1, 1, sc);
            f += 1600.0;
            break;
        case 6: // public F7: Hybrid 3 (F21/hf05 in CEC2014)
            hf05(px, &f, nx, Os, Mr, SS, 1, 1, sc);
            f += 2100.0;
            break;
        case 22: // public F8: Composition 1 (cf02)
            cf02(px, &f, nx, Os, Mr, 1, sc);
            f += 2200.0;
            break;
        case 24: // public F9: Composition 2 (cf04)
            cf04(px, &f, nx, Os, Mr, 1, sc);
            f += 2400.0;
            break;
        case 25: // public F10: Composition 3 (cf05)
            cf05(px, &f, nx, Os, Mr, 1, sc);
            f += 2500.0;
            break;
        default:
            throw std::logic_error("CEC2020 internal id " + std::to_string(internal_id_) +
                                   " has no evaluator (constructor validation failed).");
        }
        return f;
    }

private:
    int public_id_ = 0;
    int internal_id_ = 0;
    int nx_ = 0;
    Vector shift_;             // nx values, or 10*nx for compositions
    Vector rotation_;          // nx*nx values, or 10*nx*nx for compositions
    std::vector<int> shuffle_; // nx indices for internal ids 4/6/16, else empty
    // Scratch buffers standing in for the MEX globals (mutable: evaluate()
    // is const but reuses them; NOT thread-safe on a shared instance).
    mutable Vector y_;
    mutable Vector z_storage_; // [0] is the z[-1] guard slot; z = data() + 1
    mutable Vector tmpx_;
};

} // namespace

std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               int dimension,
                                               const std::filesystem::path& data_root) {
    return std::make_unique<Cec2020Problem>(function_id, dimension, data_root);
}

const std::vector<int>& supported_functions() {
    static const std::vector<int> functions{1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    return functions;
}

const std::vector<int>& supported_dimensions() {
    static const std::vector<int> dimensions{5, 10, 15, 20};
    return dimensions;
}

long long budget_for_dimension(int dimension) {
    // AGSK CEC2020 reference protocol (Adaptive_GSK_ALI.m, lines 18-27).
    switch (dimension) {
    case 5:
        return 50000LL;
    case 10:
        return 1000000LL;
    case 15:
        return 3000000LL;
    case 20:
        return 10000000LL;
    default:
        throw std::invalid_argument("CEC2020 budget undefined for dimension " +
                                    std::to_string(dimension) +
                                    "; supported dimensions are 5, 10, 15, 20.");
    }
}

} // namespace gskcec::cec2020
