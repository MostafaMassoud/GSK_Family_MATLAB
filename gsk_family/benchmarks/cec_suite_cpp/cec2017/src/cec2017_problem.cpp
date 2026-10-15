/// @file cec2017_problem.cpp
/// @brief Standalone C++20 port of the CEC2017 single-objective test suite.
///
/// Historical provenance:
///   CEC2017 competition cec17_func.cpp
///   (Jane Jing Liang, Dec. 20th 2017, MATLAB MEX evaluator; SHA256
///   bc78dae256ee121552fdc7cdfcbcf5763daf017acb7c4afc41054e6358ff227e).
/// An unchanged copy of that file sits next to this one as cec17_func.cpp,
/// for reference only; it is never compiled.
///
/// The port matches the reference numerics exactly: same formulas,
/// constants, loop structure, summation order and biases (f adds
/// 100 * function_id). Reference quirks are kept on purpose, not fixed (see
/// the README in this directory). The MEX globals OShift, M, y, z and SS
/// become per-instance std::vector members, and ini_flag is replaced by the
/// constructor, which loads all input data once. y_ and z_ are mutable
/// scratch buffers, so one problem instance is NOT thread-safe; use one
/// instance per thread.

#include "gskcec/benchmark/cec2017.hpp"

#include "gskcec/benchmark/data_loading.hpp"
#include "gskcec/core/bounds.hpp"
#include "gskcec/core/types.hpp"

#include <cmath>
#include <cstddef>
#include <filesystem>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using gskcec::Real;

/// Constants copied exactly from the reference #defines.
constexpr double kInf = 1.0e99;
constexpr double kE = 2.7182818284590452353602874713526625;
constexpr double kPi = 3.1415926535897932384626433832795029;

/// Number of composition components the loader reads: the reference sizes
/// the f >= 21 shift and rotation tables for 10 components, even when a
/// function uses fewer.
constexpr int kLoaderCfNum = 10;

/// Values per line in shift_data_<f>.txt for f >= 21. Checked for the
/// shipped data; load_data() relies on it to find each row in the file.
constexpr std::size_t kShiftLineWidth = 100;

/// One CEC2017 problem (one function at one dimension) with its data loaded.
///
/// A direct transcription of cec17_func.cpp: each ported function keeps the
/// name of its reference free function, so the two are easy to compare.
/// They work on the mutable scratch buffers y_ and z_, which replace the
/// reference globals `y` and `z`. Results depend on how these buffers are
/// shared (schaffer_F7_func reads the y_ that sr_func wrote; hybrid
/// functions pass sub-views of y_ to their component functions), so the
/// reference raw-pointer call style is kept on purpose. All raw pointers
/// are non-owning views into the std::vector members.
///
/// NOT thread-safe: evaluate() writes the y_, z_, w_levy_ and tmpx_ scratch.
class Cec2017Problem final : public gskcec::BenchmarkProblem {
public:
    Cec2017Problem(int function_id, int dimension, const std::filesystem::path& data_root)
        : func_(function_id),
          nx_(dimension),
          // valid_dimension() throws on a bad id or D before any buffer is sized.
          y_(static_cast<std::size_t>(valid_dimension(function_id, dimension)), 0.0),
          z_(static_cast<std::size_t>(dimension), 0.0),
          w_levy_(static_cast<std::size_t>(dimension), 0.0),
          tmpx_(static_cast<std::size_t>(dimension), 0.0) {
        load_data(data_root);
    }

    std::string suite_name() const override { return "cec2017"; }

    int function_id() const override { return func_; }

    int dimension() const override { return nx_; }

    gskcec::Bounds bounds() const override {
        return gskcec::Bounds::uniform(static_cast<gskcec::Index>(nx_), -100.0, 100.0);
    }

    Real optimum() const override { return 100.0 * func_; }

    Real evaluate(std::span<const Real> x) const override {
        if (x.size() != static_cast<std::size_t>(nx_)) {
            throw std::invalid_argument("CEC2017 F" + std::to_string(func_) + " expects dimension " +
                                        std::to_string(nx_) + ", got vector of size " +
                                        std::to_string(x.size()) + ".");
        }
        const double* xp = x.data();
        const double* Os = oshift_.data();
        const double* Mr = m_.data();
        const int* S = ss_.empty() ? nullptr : ss_.data();
        double f = 0.0;
        // Same switch as the reference cec17_test_func; case k adds bias 100 * k.
        switch (func_) {
        case 1:
            bent_cigar_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 100.0;
            break;
        case 2:
            sum_diff_pow_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 200.0;
            break;
        case 3:
            zakharov_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 300.0;
            break;
        case 4:
            rosenbrock_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 400.0;
            break;
        case 5:
            rastrigin_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 500.0;
            break;
        case 6:
            schaffer_F7_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 600.0;
            break;
        case 7:
            bi_rastrigin_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 700.0;
            break;
        case 8:
            step_rastrigin_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 800.0;
            break;
        case 9:
            levy_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 900.0;
            break;
        case 10:
            schwefel_func(xp, &f, nx_, Os, Mr, 1, 1);
            f += 1000.0;
            break;
        case 11:
            hf01(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1100.0;
            break;
        case 12:
            hf02(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1200.0;
            break;
        case 13:
            hf03(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1300.0;
            break;
        case 14:
            hf04(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1400.0;
            break;
        case 15:
            hf05(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1500.0;
            break;
        case 16:
            hf06(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1600.0;
            break;
        case 17:
            hf07(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1700.0;
            break;
        case 18:
            hf08(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1800.0;
            break;
        case 19:
            hf09(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 1900.0;
            break;
        case 20:
            hf10(xp, &f, nx_, Os, Mr, S, 1, 1);
            f += 2000.0;
            break;
        case 21:
            cf01(xp, &f, nx_, Os, Mr, 1);
            f += 2100.0;
            break;
        case 22:
            cf02(xp, &f, nx_, Os, Mr, 1);
            f += 2200.0;
            break;
        case 23:
            cf03(xp, &f, nx_, Os, Mr, 1);
            f += 2300.0;
            break;
        case 24:
            cf04(xp, &f, nx_, Os, Mr, 1);
            f += 2400.0;
            break;
        case 25:
            cf05(xp, &f, nx_, Os, Mr, 1);
            f += 2500.0;
            break;
        case 26:
            cf06(xp, &f, nx_, Os, Mr, 1);
            f += 2600.0;
            break;
        case 27:
            cf07(xp, &f, nx_, Os, Mr, 1);
            f += 2700.0;
            break;
        case 28:
            cf08(xp, &f, nx_, Os, Mr, 1);
            f += 2800.0;
            break;
        case 29:
            cf09(xp, &f, nx_, Os, Mr, S, 1);
            f += 2900.0;
            break;
        case 30:
            cf10(xp, &f, nx_, Os, Mr, S, 1);
            f += 3000.0;
            break;
        default:
            // Unreachable: func_ is validated at construction.
            throw std::invalid_argument("CEC2017 function id out of range.");
        }
        return f;
    }

private:
    // ---------------------------------------------------------------- state
    int func_;
    int nx_;
    std::vector<double> oshift_;  ///< Shift rows packed with stride nx_ (reference OShift).
    std::vector<double> m_;       ///< Rotation matrices, row-major (reference M).
    std::vector<int> ss_;         ///< 1-based shuffle indices (reference SS); may be empty.
    mutable std::vector<double> y_;     ///< Reference global y (scratch).
    mutable std::vector<double> z_;     ///< Reference global z (scratch).
    mutable std::vector<double> w_levy_;///< Reference levy_func local w (a per-call malloc there).
    mutable std::vector<double> tmpx_;  ///< Reference bi_rastrigin_func local tmpx.

    // ----------------------------------------------------------- validation
    static int valid_dimension(int function_id, int dimension) {
        if (function_id < 1 || function_id > 30) {
            throw std::invalid_argument("CEC2017 function id must be in [1, 30], got " +
                                        std::to_string(function_id) + ".");
        }
        if (dimension != 10 && dimension != 30 && dimension != 50 && dimension != 100) {
            throw std::invalid_argument("CEC2017 dimension must be 10, 30, 50 or 100, got " +
                                        std::to_string(dimension) + ".");
        }
        return dimension;
    }

    // --------------------------------------------------------- data loading
    /// Loads M_<f>_D<D>.txt, shift_data_<f>.txt and, for the hybrid functions
    /// and the hybrid-based compositions, shuffle_data_<f>_D<D>.txt. Reads
    /// only what the reference fscanf loops actually use:
    ///  - M: f <= 20 uses one D*D matrix. (For f20 the reference asks for 10,
    ///    but M_20_D*.txt holds only one and only one is used.) f >= 21 uses
    ///    10 consecutive D*D matrices.
    ///  - shift: f <= 20 uses the first D values. (For f20 the reference asks
    ///    for 10 rows, but shift_data_20.txt has one line and only row 0
    ///    feeds hf10.) f >= 21 uses the first D values of each of 10 lines;
    ///    every line holds exactly 100 values, so line i is the i-th
    ///    100-value block of the flattened file.
    ///  - shuffle: f11..f20 use D indices; f29/f30 use 10*D indices (rows of
    ///    D; the compositions use only the first three rows).
    /// Throws std::runtime_error if a file is missing or too short, or if a
    /// shuffle index is outside [1, D].
    void load_data(const std::filesystem::path& data_root) {
        const std::string fid = std::to_string(func_);
        const std::string did = std::to_string(nx_);
        const std::size_t n = static_cast<std::size_t>(nx_);

        const std::filesystem::path m_path = data_root / ("M_" + fid + "_D" + did + ".txt");
        const std::size_t m_count = (func_ >= 21) ? static_cast<std::size_t>(kLoaderCfNum) * n * n
                                                  : n * n;
        m_ = gskcec::load_values_file(m_path, m_count);

        const std::filesystem::path shift_path = data_root / ("shift_data_" + fid + ".txt");
        if (func_ <= 20) {
            oshift_ = gskcec::load_values_file(shift_path, n);
        } else {
            const gskcec::Vector flat = gskcec::load_values_file(shift_path);
            oshift_.resize(static_cast<std::size_t>(kLoaderCfNum) * n);
            for (int i = 0; i < kLoaderCfNum; ++i) {
                const std::size_t row = static_cast<std::size_t>(i) * kShiftLineWidth;
                if (row + n > flat.size()) {
                    throw std::runtime_error("Data file " + shift_path.string() + " holds " +
                                             std::to_string(flat.size()) +
                                             " values, expected 10 rows of " +
                                             std::to_string(kShiftLineWidth) + ".");
                }
                for (std::size_t j = 0; j < n; ++j) {
                    oshift_[static_cast<std::size_t>(i) * n + j] = flat[row + j];
                }
            }
        }

        if ((func_ >= 11 && func_ <= 20) || func_ == 29 || func_ == 30) {
            const std::filesystem::path ss_path =
                data_root / ("shuffle_data_" + fid + "_D" + did + ".txt");
            const std::size_t ss_count =
                (func_ >= 29) ? static_cast<std::size_t>(kLoaderCfNum) * n : n;
            const gskcec::Vector raw = gskcec::load_values_file(ss_path, ss_count);
            ss_.resize(raw.size());
            for (std::size_t i = 0; i < raw.size(); ++i) {
                const int idx = static_cast<int>(std::lround(raw[i]));
                if (idx < 1 || idx > nx_) {
                    throw std::runtime_error("Shuffle index " + std::to_string(raw[i]) +
                                             " out of range [1, " + did + "] in data file: " +
                                             ss_path.string());
                }
                ss_[i] = idx;
            }
        }
    }

    // ------------------------------------------------- shift/rotate helpers
    /// xshift = x - Os.
    void shiftfunc(const double* x, double* xshift, int nx, const double* Os) const {
        for (int i = 0; i < nx; ++i) {
            xshift[i] = x[i] - Os[i];
        }
    }

    /// xrot = Mr * x, where Mr is a row-major nx x nx matrix.
    void rotatefunc(const double* x, double* xrot, int nx, const double* Mr) const {
        for (int i = 0; i < nx; ++i) {
            xrot[i] = 0;
            for (int j = 0; j < nx; ++j) {
                xrot[i] = xrot[i] + x[j] * Mr[i * nx + j];
            }
        }
    }

    /// Shift (if s_flag == 1), scale by sh_rate, then rotate (if r_flag == 1).
    /// With r_flag == 1 the scaled vector goes into y_ before rotation, as
    /// the reference does with its global y; schaffer_F7_func reads that
    /// buffer afterwards. With r_flag == 0, y_ is left unchanged.
    void sr_func(const double* x, double* sr_x, int nx, const double* Os, const double* Mr,
                 double sh_rate, int s_flag, int r_flag) const {
        double* y = y_.data();
        if (s_flag == 1) {
            if (r_flag == 1) {
                shiftfunc(x, y, nx, Os);
                for (int i = 0; i < nx; ++i) {  // shrink to the original search range
                    y[i] = y[i] * sh_rate;
                }
                rotatefunc(y, sr_x, nx, Mr);
            } else {
                shiftfunc(x, sr_x, nx, Os);
                for (int i = 0; i < nx; ++i) {
                    sr_x[i] = sr_x[i] * sh_rate;
                }
            }
        } else {
            if (r_flag == 1) {
                for (int i = 0; i < nx; ++i) {
                    y[i] = x[i] * sh_rate;
                }
                rotatefunc(y, sr_x, nx, Mr);
            } else {
                for (int i = 0; i < nx; ++i) {
                    sr_x[i] = x[i] * sh_rate;
                }
            }
        }
    }

    // ------------------------------------------------------ basic functions
    // Not ported: sphere_func, dif_powers_func, dixon_price_func, asyfunc and
    // oszfunc exist in the reference, but no CEC2017 function calls them.

    void bent_cigar_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                         int s_flag, int r_flag) const {
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        f[0] = z[0] * z[0];
        for (int i = 1; i < nx; ++i) {
            f[0] += std::pow(10.0, 6.0) * z[i] * z[i];
        }
    }

    void ellips_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                     int s_flag, int r_flag) const {
        double* z = z_.data();
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            f[0] += std::pow(10.0, 6.0 * i / (nx - 1)) * z[i] * z[i];
        }
    }

    /// The reference writes pow(abs(xi), i+1). Compiled as C++, abs picks the
    /// double overload (fabs) and the int exponent becomes a double, so the
    /// port calls fabs and passes a double exponent.
    void sum_diff_pow_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                           int s_flag, int r_flag) const {
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        f[0] = 0.0;
        double sum = 0.0;
        for (int i = 0; i < nx; ++i) {
            const double xi = z[i];
            const double newv = std::pow(std::fabs(xi), static_cast<double>(i + 1));
            sum = sum + newv;
        }
        f[0] = sum;
    }

    void zakharov_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                       int s_flag, int r_flag) const {
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        f[0] = 0.0;
        double sum1 = 0.0;
        double sum2 = 0.0;
        for (int i = 0; i < nx; ++i) {
            const double xi = z[i];
            sum1 = sum1 + std::pow(xi, 2.0);
            sum2 = sum2 + 0.5 * (i + 1) * xi;
        }
        f[0] = sum1 + std::pow(sum2, 2.0) + std::pow(sum2, 4.0);
    }

    void levy_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                   int s_flag, int r_flag) const {
        double* z = z_.data();
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);

        double* w = w_levy_.data();  // the reference mallocs a local w of size nx
        for (int i = 0; i < nx; ++i) {
            w[i] = 1.0 + (z[i] - 1.0) / 4.0;
        }
        const double term1 = std::pow(std::sin(kPi * w[0]), 2.0);
        const double term3 =
            std::pow(w[nx - 1] - 1, 2.0) * (1 + std::pow(std::sin(2 * kPi * w[nx - 1]), 2.0));
        double sum = 0.0;
        for (int i = 0; i < nx - 1; ++i) {
            const double wi = w[i];
            const double newv =
                std::pow(wi - 1, 2.0) * (1 + 10 * std::pow(std::sin(kPi * wi + 1), 2.0));
            sum = sum + newv;
        }
        f[0] = term1 + sum + term3;
    }

    void rosenbrock_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                         int s_flag, int r_flag) const {
        double* z = z_.data();
        double tmp1 = 0.0;
        double tmp2 = 0.0;
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 2.048 / 100.0, s_flag, r_flag);
        z[0] += 1.0;  // shift to origin
        for (int i = 0; i < nx - 1; ++i) {
            z[i + 1] += 1.0;  // shift to origin
            tmp1 = z[i] * z[i] - z[i + 1];
            tmp2 = z[i] - 1.0;
            f[0] += 100.0 * tmp1 * tmp1 + tmp2 * tmp2;
        }
    }

    /// Reference quirk, kept as is: the body reads y_ as sr_func wrote it
    /// (shifted but NOT rotated) instead of the rotated z, so the rotation
    /// never affects F6. Inside a hybrid (s_flag == r_flag == 0) sr_func does
    /// not write y_, so this reads y_[0..nx-1]: the start of the hybrid's
    /// shuffled vector, not its own sub-block.
    void schaffer_F7_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                          int s_flag, int r_flag) const {
        double* y = y_.data();
        double* z = z_.data();
        double tmp = 0.0;
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx - 1; ++i) {
            z[i] = std::pow(y[i] * y[i] + y[i + 1] * y[i + 1], 0.5);
            tmp = std::sin(50.0 * std::pow(z[i], 0.2));
            f[0] += std::pow(z[i], 0.5) + std::pow(z[i], 0.5) * tmp * tmp;
        }
        f[0] = f[0] * f[0] / (nx - 1) / (nx - 1);
    }

    void ackley_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                     int s_flag, int r_flag) const {
        double* z = z_.data();
        double sum1 = 0.0;
        double sum2 = 0.0;
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            sum1 += z[i] * z[i];
            sum2 += std::cos(2.0 * kPi * z[i]);
        }
        sum1 = -0.2 * std::sqrt(sum1 / nx);
        sum2 /= nx;
        f[0] = kE - 20.0 * std::exp(sum1) - std::exp(sum2) + 20.0;
    }

    void weierstrass_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                          int s_flag, int r_flag) const {
        double* z = z_.data();
        const double a = 0.5;
        const double b = 3.0;
        const int k_max = 20;
        double sum = 0.0;
        double sum2 = 0.0;
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 0.5 / 100.0, s_flag, r_flag);
        // pow(a,j) and pow(b,j) depend only on j: compute them once, not for
        // every i as the reference does. Bit-identical: same values, same
        // summation order over j.
        double aj[21];
        double bj[21];
        for (int j = 0; j <= k_max; ++j) {
            aj[j] = std::pow(a, static_cast<double>(j));
            bj[j] = std::pow(b, static_cast<double>(j));
        }
        // sum2 does not depend on i. The reference recomputes it for every i
        // but uses only the last value, so computing it once gives the same
        // result.
        for (int j = 0; j <= k_max; ++j) {
            sum2 += aj[j] * std::cos(2.0 * kPi * bj[j] * 0.5);
        }
        for (int i = 0; i < nx; ++i) {
            sum = 0.0;
            for (int j = 0; j <= k_max; ++j) {
                sum += aj[j] * std::cos(2.0 * kPi * bj[j] * (z[i] + 0.5));
            }
            f[0] += sum;
        }
        f[0] -= nx * sum2;
    }

    void griewank_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                       int s_flag, int r_flag) const {
        double* z = z_.data();
        double s = 0.0;
        double p = 1.0;
        sr_func(x, z, nx, Os, Mr, 600.0 / 100.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            s += z[i] * z[i];
            p *= std::cos(z[i] / std::sqrt(1.0 + i));
        }
        f[0] = 1.0 + s / 4000.0 - p;
    }

    void rastrigin_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                        int s_flag, int r_flag) const {
        double* z = z_.data();
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 5.12 / 100.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            f[0] += (z[i] * z[i] - 10.0 * std::cos(2.0 * kPi * z[i]) + 10.0);
        }
    }

    /// Reference quirk, kept as is: the "noncontinuous" rounding loop below
    /// works on stale y_ values that sr_func then overwrites (F8, the only
    /// caller, passes r_flag == 1), so it has no effect. F8 behaves as plain
    /// shifted, rotated Rastrigin (scaled by 5.12/100).
    void step_rastrigin_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                             int s_flag, int r_flag) const {
        double* y = y_.data();
        double* z = z_.data();
        f[0] = 0.0;
        for (int i = 0; i < nx; ++i) {
            if (std::fabs(y[i] - Os[i]) > 0.5) {
                y[i] = Os[i] + std::floor(2 * (y[i] - Os[i]) + 0.5) / 2;
            }
        }
        sr_func(x, z, nx, Os, Mr, 5.12 / 100.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            f[0] += (z[i] * z[i] - 10.0 * std::cos(2.0 * kPi * z[i]) + 10.0);
        }
    }

    void schwefel_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                       int s_flag, int r_flag) const {
        double* z = z_.data();
        double tmp = 0.0;
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 1000.0 / 100.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            z[i] += 4.209687462275036e+002;
            if (z[i] > 500) {
                f[0] -= (500.0 - std::fmod(z[i], 500)) *
                        std::sin(std::pow(500.0 - std::fmod(z[i], 500), 0.5));
                tmp = (z[i] - 500.0) / 100;
                f[0] += tmp * tmp / nx;
            } else if (z[i] < -500) {
                f[0] -= (-500.0 + std::fmod(std::fabs(z[i]), 500)) *
                        std::sin(std::pow(500.0 - std::fmod(std::fabs(z[i]), 500), 0.5));
                tmp = (z[i] + 500.0) / 100;
                f[0] += tmp * tmp / nx;
            } else {
                f[0] -= z[i] * std::sin(std::pow(std::fabs(z[i]), 0.5));
            }
        }
        f[0] += 4.189828872724338e+002 * nx;
    }

    void katsuura_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                       int s_flag, int r_flag) const {
        double* z = z_.data();
        double temp = 0.0;
        double tmp1 = 0.0;
        double tmp2 = 0.0;
        f[0] = 1.0;
        const double tmp3 = std::pow(1.0 * nx, 1.2);
        // pow(2,j) depends only on j: compute it once instead of nx*32 times.
        // Bit-identical: the same std::pow(2.0, j) values.
        double pow2[33];
        for (int j = 1; j <= 32; ++j) {
            pow2[j] = std::pow(2.0, static_cast<double>(j));
        }
        sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            temp = 0.0;
            for (int j = 1; j <= 32; ++j) {
                tmp1 = pow2[j];
                tmp2 = tmp1 * z[i];
                temp += std::fabs(tmp2 - std::floor(tmp2 + 0.5)) / tmp1;
            }
            f[0] *= std::pow(1.0 + (i + 1) * temp, 10.0 / tmp3);
        }
        tmp1 = 10.0 / nx / nx;
        f[0] = f[0] * tmp1 - tmp1;
    }

    /// Inside a hybrid (s_flag == 0) the reference copies x into the global
    /// y, although x is itself a sub-view of y. The two ranges never overlap
    /// for a supported dimension, and the port shares the buffers the same
    /// way. The sign flip uses Os[i]; inside a hybrid these are the leading
    /// entries of the FULL shift vector.
    void bi_rastrigin_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                           int s_flag, int r_flag) const {
        double* y = y_.data();
        double* z = z_.data();
        double* tmpx = tmpx_.data();  // the reference mallocs a local tmpx of size nx
        const double mu0 = 2.5;
        const double d = 1.0;
        double tmp = 0.0;
        double tmp1 = 0.0;
        double tmp2 = 0.0;
        const double s = 1.0 - 1.0 / (2.0 * std::pow(nx + 20.0, 0.5) - 8.2);
        const double mu1 = -std::pow((mu0 * mu0 - d) / s, 0.5);

        if (s_flag == 1) {
            shiftfunc(x, y, nx, Os);
        } else {
            for (int i = 0; i < nx; ++i) {
                y[i] = x[i];
            }
        }
        for (int i = 0; i < nx; ++i) {  // shrink to the original search range
            y[i] *= 10.0 / 100.0;
        }
        for (int i = 0; i < nx; ++i) {
            tmpx[i] = 2 * y[i];
            if (Os[i] < 0.0) {
                tmpx[i] *= -1.;
            }
        }
        for (int i = 0; i < nx; ++i) {
            z[i] = tmpx[i];
            tmpx[i] += mu0;
        }
        tmp1 = 0.0;
        tmp2 = 0.0;
        for (int i = 0; i < nx; ++i) {
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
            for (int i = 0; i < nx; ++i) {
                tmp += std::cos(2.0 * kPi * y[i]);
            }
            if (tmp1 < tmp2) {
                f[0] = tmp1;
            } else {
                f[0] = tmp2;
            }
            f[0] += 10.0 * (nx - tmp);
        } else {
            for (int i = 0; i < nx; ++i) {
                tmp += std::cos(2.0 * kPi * z[i]);
            }
            if (tmp1 < tmp2) {
                f[0] = tmp1;
            } else {
                f[0] = tmp2;
            }
            f[0] += 10.0 * (nx - tmp);
        }
    }

    void grie_rosen_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                         int s_flag, int r_flag) const {
        double* z = z_.data();
        double temp = 0.0;
        double tmp1 = 0.0;
        double tmp2 = 0.0;
        f[0] = 0.0;
        sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag);
        z[0] += 1.0;  // shift to origin
        for (int i = 0; i < nx - 1; ++i) {
            z[i + 1] += 1.0;  // shift to origin
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

    void escaffer6_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                        int s_flag, int r_flag) const {
        double* z = z_.data();
        double temp1 = 0.0;
        double temp2 = 0.0;
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        f[0] = 0.0;
        for (int i = 0; i < nx - 1; ++i) {
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

    void happycat_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                       int s_flag, int r_flag) const {
        double* z = z_.data();
        const double alpha = 1.0 / 8.0;
        sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag);
        double r2 = 0.0;
        double sum_z = 0.0;
        for (int i = 0; i < nx; ++i) {
            z[i] = z[i] - 1.0;  // shift to origin
            r2 += z[i] * z[i];
            sum_z += z[i];
        }
        f[0] = std::pow(std::fabs(r2 - nx), 2 * alpha) + (0.5 * r2 + sum_z) / nx + 0.5;
    }

    void hgbat_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                    int s_flag, int r_flag) const {
        double* z = z_.data();
        const double alpha = 1.0 / 4.0;
        sr_func(x, z, nx, Os, Mr, 5.0 / 100.0, s_flag, r_flag);
        double r2 = 0.0;
        double sum_z = 0.0;
        for (int i = 0; i < nx; ++i) {
            z[i] = z[i] - 1.0;  // shift to origin
            r2 += z[i] * z[i];
            sum_z += z[i];
        }
        f[0] = std::pow(std::fabs(std::pow(r2, 2.0) - std::pow(sum_z, 2.0)), 2 * alpha) +
               (0.5 * r2 + sum_z) / nx + 0.5;
    }

    void discus_func(const double* x, double* f, int nx, const double* Os, const double* Mr,
                     int s_flag, int r_flag) const {
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        f[0] = std::pow(10.0, 6.0) * z[0] * z[0];
        for (int i = 1; i < nx; ++i) {
            f[0] += z[i] * z[i];
        }
    }

    // ----------------------------------------------------- hybrid functions
    /// Block split shared by all hybrid functions (the reference repeats this
    /// code in each hfNN): G_nx[i] = ceil(Gp[i]*nx) for every block but the
    /// last, which takes the rest. G[i] is the 0-based start index of block i.
    template <int CfNum>
    void hf_partition(const double (&Gp)[CfNum], int nx, int (&G)[CfNum], int (&G_nx)[CfNum]) const {
        int tmp = 0;
        for (int i = 0; i < CfNum - 1; ++i) {
            G_nx[i] = static_cast<int>(std::ceil(Gp[i] * nx));
            tmp += G_nx[i];
        }
        G_nx[CfNum - 1] = nx - tmp;
        G[0] = 0;
        for (int i = 1; i < CfNum; ++i) {
            G[i] = G[i - 1] + G_nx[i - 1];
        }
    }

    void hf01(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 1
        constexpr int cf_num = 3;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.2, 0.4, 0.4};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        zakharov_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        rosenbrock_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        rastrigin_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf02(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 2
        constexpr int cf_num = 3;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.3, 0.3, 0.4};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        ellips_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        schwefel_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        bent_cigar_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf03(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 3
        constexpr int cf_num = 3;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.3, 0.3, 0.4};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        bent_cigar_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        rosenbrock_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        bi_rastrigin_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf04(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 4
        constexpr int cf_num = 4;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.2, 0.2, 0.2, 0.4};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        ellips_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        ackley_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        schaffer_F7_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        rastrigin_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf05(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 5
        constexpr int cf_num = 4;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.2, 0.2, 0.3, 0.3};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        bent_cigar_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        hgbat_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        rastrigin_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        rosenbrock_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf06(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 6
        constexpr int cf_num = 4;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.2, 0.2, 0.3, 0.3};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        escaffer6_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        hgbat_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        rosenbrock_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        schwefel_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf07(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 7
        constexpr int cf_num = 5;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.1, 0.2, 0.2, 0.2, 0.3};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        katsuura_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        ackley_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        grie_rosen_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        schwefel_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        rastrigin_func(&y[G[4]], &fit[4], G_nx[4], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf08(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 8
        constexpr int cf_num = 5;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.2, 0.2, 0.2, 0.2, 0.2};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        ellips_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        ackley_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        rastrigin_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        hgbat_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        discus_func(&y[G[4]], &fit[4], G_nx[4], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf09(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 9
        constexpr int cf_num = 5;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.2, 0.2, 0.2, 0.2, 0.2};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        bent_cigar_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        rastrigin_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        grie_rosen_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        weierstrass_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        escaffer6_func(&y[G[4]], &fit[4], G_nx[4], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    void hf10(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* S,
              int s_flag, int r_flag) const {  // Hybrid Function 10
        constexpr int cf_num = 6;
        double fit[cf_num];
        int G[cf_num];
        int G_nx[cf_num];
        const double Gp[cf_num] = {0.1, 0.1, 0.2, 0.2, 0.2, 0.2};
        hf_partition(Gp, nx, G, G_nx);
        double* y = y_.data();
        double* z = z_.data();
        sr_func(x, z, nx, Os, Mr, 1.0, s_flag, r_flag);
        for (int i = 0; i < nx; ++i) {
            y[i] = z[S[i] - 1];
        }
        hgbat_func(&y[G[0]], &fit[0], G_nx[0], Os, Mr, 0, 0);
        katsuura_func(&y[G[1]], &fit[1], G_nx[1], Os, Mr, 0, 0);
        ackley_func(&y[G[2]], &fit[2], G_nx[2], Os, Mr, 0, 0);
        rastrigin_func(&y[G[3]], &fit[3], G_nx[3], Os, Mr, 0, 0);
        schwefel_func(&y[G[4]], &fit[4], G_nx[4], Os, Mr, 0, 0);
        schaffer_F7_func(&y[G[5]], &fit[5], G_nx[5], Os, Mr, 0, 0);
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] += fit[i];
        }
    }

    // ------------------------------------------------ composition functions
    /// Adds bias[i] to fit[i] (in place) and writes their weighted mean
    /// (weights divided by their sum) to f[0]. Weight i falls with the
    /// distance from x to shift row i (width delta[i]); an exact hit gets
    /// kInf. If all weights are 0, all become 1.
    void cf_cal(const double* x, double* f, int nx, const double* Os, const double* delta,
                const double* bias, double* fit, int cf_num) const {
        double w[kLoaderCfNum];  // the reference mallocs cf_num (<= 6) weights
        double w_max = 0.0;
        double w_sum = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            fit[i] += bias[i];
            w[i] = 0;
            for (int j = 0; j < nx; ++j) {
                w[i] += std::pow(x[j] - Os[i * nx + j], 2.0);
            }
            if (w[i] != 0) {
                w[i] = std::pow(1.0 / w[i], 0.5) *
                       std::exp(-w[i] / 2.0 / nx / std::pow(delta[i], 2.0));
            } else {
                w[i] = kInf;
            }
            if (w[i] > w_max) {
                w_max = w[i];
            }
        }
        for (int i = 0; i < cf_num; ++i) {
            w_sum = w_sum + w[i];
        }
        if (w_max == 0) {
            for (int i = 0; i < cf_num; ++i) {
                w[i] = 1;
            }
            w_sum = cf_num;
        }
        f[0] = 0.0;
        for (int i = 0; i < cf_num; ++i) {
            f[0] = f[0] + w[i] / w_sum * fit[i];
        }
    }

    void cf01(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 1
        constexpr int cf_num = 3;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30};
        const double bias[cf_num] = {0, 100, 200};
        rosenbrock_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        ellips_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 10000 * fit[1] / 1e+10;
        rastrigin_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf02(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 2
        constexpr int cf_num = 3;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30};
        const double bias[cf_num] = {0, 100, 200};
        rastrigin_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        griewank_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 1000 * fit[1] / 100;
        schwefel_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf03(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 3
        constexpr int cf_num = 4;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30, 40};
        const double bias[cf_num] = {0, 100, 200, 300};
        rosenbrock_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        ackley_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 1000 * fit[1] / 100;
        schwefel_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        rastrigin_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf04(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 4
        constexpr int cf_num = 4;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30, 40};
        const double bias[cf_num] = {0, 100, 200, 300};
        ackley_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        fit[0] = 1000 * fit[0] / 100;
        ellips_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 10000 * fit[1] / 1e+10;
        griewank_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        fit[2] = 1000 * fit[2] / 100;
        rastrigin_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf05(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 5
        constexpr int cf_num = 5;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30, 40, 50};
        const double bias[cf_num] = {0, 100, 200, 300, 400};
        rastrigin_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        fit[0] = 10000 * fit[0] / 1e+3;
        happycat_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 1000 * fit[1] / 1e+3;
        ackley_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        fit[2] = 1000 * fit[2] / 100;
        discus_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag);
        fit[3] = 10000 * fit[3] / 1e+10;
        rosenbrock_func(x, &fit[4], nx, &Os[4 * nx], &Mr[4 * nx * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf06(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 6
        constexpr int cf_num = 5;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 20, 30, 40};
        const double bias[cf_num] = {0, 100, 200, 300, 400};
        escaffer6_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        fit[0] = 10000 * fit[0] / 2e+7;
        schwefel_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        griewank_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        fit[2] = 1000 * fit[2] / 100;
        rosenbrock_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag);
        rastrigin_func(x, &fit[4], nx, &Os[4 * nx], &Mr[4 * nx * nx], 1, r_flag);
        fit[4] = 10000 * fit[4] / 1e+3;
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf07(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 7
        constexpr int cf_num = 6;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30, 40, 50, 60};
        const double bias[cf_num] = {0, 100, 200, 300, 400, 500};
        hgbat_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        fit[0] = 10000 * fit[0] / 1000;
        rastrigin_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 10000 * fit[1] / 1e+3;
        schwefel_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        fit[2] = 10000 * fit[2] / 4e+3;
        bent_cigar_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag);
        fit[3] = 10000 * fit[3] / 1e+30;
        ellips_func(x, &fit[4], nx, &Os[4 * nx], &Mr[4 * nx * nx], 1, r_flag);
        fit[4] = 10000 * fit[4] / 1e+10;
        escaffer6_func(x, &fit[5], nx, &Os[5 * nx], &Mr[5 * nx * nx], 1, r_flag);
        fit[5] = 10000 * fit[5] / 2e+7;
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf08(const double* x, double* f, int nx, const double* Os, const double* Mr,
              int r_flag) const {  // Composition Function 8
        constexpr int cf_num = 6;
        double fit[cf_num];
        const double delta[cf_num] = {10, 20, 30, 40, 50, 60};
        const double bias[cf_num] = {0, 100, 200, 300, 400, 500};
        ackley_func(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], 1, r_flag);
        fit[0] = 1000 * fit[0] / 100;
        griewank_func(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], 1, r_flag);
        fit[1] = 1000 * fit[1] / 100;
        discus_func(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], 1, r_flag);
        fit[2] = 10000 * fit[2] / 1e+10;
        rosenbrock_func(x, &fit[3], nx, &Os[3 * nx], &Mr[3 * nx * nx], 1, r_flag);
        happycat_func(x, &fit[4], nx, &Os[4 * nx], &Mr[4 * nx * nx], 1, r_flag);
        fit[4] = 1000 * fit[4] / 1e+3;
        escaffer6_func(x, &fit[5], nx, &Os[5 * nx], &Mr[5 * nx * nx], 1, r_flag);
        fit[5] = 10000 * fit[5] / 2e+7;
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf09(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* SS,
              int r_flag) const {  // Composition Function 9 (hybrid-based)
        constexpr int cf_num = 3;
        double fit[cf_num];
        const double delta[cf_num] = {10, 30, 50};
        const double bias[cf_num] = {0, 100, 200};
        hf05(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], &SS[0 * nx], 1, r_flag);
        hf06(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], &SS[1 * nx], 1, r_flag);
        hf07(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], &SS[2 * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }

    void cf10(const double* x, double* f, int nx, const double* Os, const double* Mr, const int* SS,
              int r_flag) const {  // Composition Function 10 (hybrid-based)
        constexpr int cf_num = 3;
        double fit[cf_num];
        const double delta[cf_num] = {10, 30, 50};
        const double bias[cf_num] = {0, 100, 200};
        hf05(x, &fit[0], nx, &Os[0 * nx], &Mr[0 * nx * nx], &SS[0 * nx], 1, r_flag);
        hf08(x, &fit[1], nx, &Os[1 * nx], &Mr[1 * nx * nx], &SS[1 * nx], 1, r_flag);
        hf09(x, &fit[2], nx, &Os[2 * nx], &Mr[2 * nx * nx], &SS[2 * nx], 1, r_flag);
        cf_cal(x, f, nx, Os, delta, bias, fit, cf_num);
    }
};

}  // namespace

namespace gskcec::cec2017 {

std::unique_ptr<BenchmarkProblem> make_problem(int function_id, int dimension,
                                               const std::filesystem::path& data_root) {
    return std::make_unique<Cec2017Problem>(function_id, dimension, data_root);
}

const std::vector<int>& supported_functions() {
    static const std::vector<int> ids = [] {
        std::vector<int> v(30);
        for (int i = 0; i < 30; ++i) {
            v[static_cast<std::size_t>(i)] = i + 1;
        }
        return v;
    }();
    return ids;
}

const std::vector<int>& supported_dimensions() {
    static const std::vector<int> dims{10, 30, 50, 100};
    return dims;
}

}  // namespace gskcec::cec2017
