// cec2011_problems_a.cpp -- CEC2011 work package A: problems 1-8 and 10.
//
// Standalone C++20 port of the CEC2011 real-world MATLAB package.
// Source files (docs/reference/cec2011_port_plan.md section 5):
//   bench_func.m cases 1-8     -> problems 1-8
//   diffsolv.m + c_bifunc_data -> problem 3 ODE right-hand side
//   intgrl.m                   -> problem 4 ODE right-hand side
//   data6Bus.m                 -> problem 8 Garver 6-bus tables
//   antennafunccircular.m, array_factorcir.m -> problem 10
// Also holds a re-implementation of MATLAB's ode45 that follows the R2025b
// funfun/ode45.m code path used by problems 3-4. Quirks of the original code
// (marked [PRESERVE] in the port plan) are kept so results match; each one is
// commented where it occurs.
//
// Every objective ends with apply_reference_nan_rule (NaN -> 0, from
// Calc_Fitx_2011.m lines 57-61); Inf passes through unchanged.

#include "cec2011_detail.hpp"

#include "gskcec/benchmark/data_loading.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <fstream>
#include <limits>
#include <memory>
#include <span>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace gskcec::cec2011::detail {

namespace {

constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();
constexpr double kInf = std::numeric_limits<double>::infinity();
// MATLAB built-in pi (the IEEE double nearest to pi).
constexpr double kPi = 3.141592653589793;

// base^exponent by repeated squaring, like MATLAB `^` with a positive integer
// exponent (R2021b+). For the exponents 2 and 3 used in this file every
// multiply order gives the same bits. For problem 2's r^6 and r^12 MATLAB's
// multiply order is undocumented, so results agree to ~1 ulp (well inside
// the 1e-12 relative test tolerance).
double int_pow(double base, unsigned exponent) {
    double result = 1.0;
    double b = base;
    unsigned n = exponent;
    while (n > 0) {
        if ((n & 1u) != 0u) {
            result *= b;
        }
        n >>= 1u;
        if (n > 0) {
            b *= b;
        }
    }
    return result;
}

// max(v, 0) as MATLAB computes it, for the hinge penalties: NaN gives 0
// (MATLAB max ignores NaN), unlike std::max.
double hinge_at_zero(double v) {
    return v > 0.0 ? v : 0.0;
}

// ---- Common base ----
// evaluate() checks x has D entries (else std::invalid_argument), then
// applies the NaN rule to objective(x).

class WpaProblem : public BenchmarkProblem {
public:
    std::string suite_name() const override { return "cec2011"; }
    int function_id() const override { return id_; }
    int dimension() const override { return dim_; }
    Bounds bounds() const override { return Bounds(lower_, upper_); }
    Real optimum() const override { return kNaN; }  // no published optima

    Real evaluate(std::span<const Real> x) const final {
        if (x.size() != static_cast<std::size_t>(dim_)) {
            throw std::invalid_argument("cec2011 f" + std::to_string(id_) + ": expected dimension " +
                                        std::to_string(dim_) + ", got " + std::to_string(x.size()) + ".");
        }
        return apply_reference_nan_rule(objective(x));
    }

protected:
    WpaProblem(int id, int dim, Vector lower, Vector upper)
        : id_(id), dim_(dim), lower_(std::move(lower)), upper_(std::move(upper)) {}

    virtual Real objective(std::span<const Real> x) const = 0;

private:
    int id_;
    int dim_;
    Vector lower_;
    Vector upper_;
};

// Bounds for problems 2, 5 and 6 (define_boundaries.m cases 2/5/6), D = 30
// (10 atoms x 3 coordinates, j is 1-based). Atom 1 lies in
// [0,4]x[0,4]x[0,pi]. For j >= 4 the box is symmetric and widens by 1/4 per
// atom: hi(j) = 4 + (1/4)*floor((j-4)/3), lo(j) = -hi(j).
std::pair<Vector, Vector> atom_cluster_bounds() {
    Vector lo(30), hi(30);
    for (int j = 1; j <= 30; ++j) {
        double upper = 0.0, lower = 0.0;
        if (j == 1 || j == 2) {
            upper = 4.0;
            lower = 0.0;
        } else if (j == 3) {
            upper = kPi;
            lower = 0.0;
        } else {
            const double widen = 0.25 * static_cast<double>((j - 4) / 3);  // (1/4)*floor((j-4)/3)
            upper = 4.0 + widen;
            lower = -4.0 - widen;
        }
        lo[static_cast<std::size_t>(j - 1)] = lower;
        hi[static_cast<std::size_t>(j - 1)] = upper;
    }
    return {std::move(lo), std::move(hi)};
}

// Euclidean distance between atoms i and j (0-based). Atom k is
// (x[3k], x[3k+1], x[3k+2]), i.e. row k+1 of MATLAB's column-major
// reshape(x,3,n)'. Sums in the same order as MATLAB
// sqrt(sum((x(i,:)-x(j,:)).^2)).
double atom_distance(std::span<const Real> x, int i, int j) {
    const double d0 = x[static_cast<std::size_t>(3 * i)] - x[static_cast<std::size_t>(3 * j)];
    const double d1 = x[static_cast<std::size_t>(3 * i + 1)] - x[static_cast<std::size_t>(3 * j + 1)];
    const double d2 = x[static_cast<std::size_t>(3 * i + 2)] - x[static_cast<std::size_t>(3 * j + 2)];
    return std::sqrt((d0 * d0 + d1 * d1) + d2 * d2);
}

// ---- MATLAB-compatible ode45 (problems 3 and 4) ----
// Follows MATLAB R2025b funfun/ode45.m, private/odearguments.m and
// private/ntrp45split.m, but only for the setup the reference uses: a
// two-element increasing tspan, scalar RelTol/AbsTol, Refine = 4, and no
// events, mass matrix, NonNegative, NormControl, MaxStep or InitialStep.
// The code is written independently, not copied from MATLAB: the
// Dormand-Prince RK5(4) tableau and 4th-order interpolant are published
// (Dormand & Prince 1980; Shampine & Reichelt, SIAM J. Sci. Comp. 18-1,
// 1997); the controller constants and operation order were checked against
// the MATLAB sources.
//
// Details that match ode45.m:
//  * initial step: absh = min(hmax, htspan), capped at 1/rh with
//    rh = ||f0 ./ max(|y0|,threshold)||_inf / (0.8*rtol^(1/5));
//  * hmax = max(0.1*|tfinal-t0|, 16*eps*max(|t0|,|tfinal|)) (default MaxStep
//    from odearguments.m); hmin = 16*eps(t), recomputed every step;
//  * stage sums use ode45.m's scalar-coefficient grouping
//    y + h.*(b1.*f1 + ... ), evaluated left to right;
//  * error: err = absh * || fE ./ max(max(|y|,|ynew|),threshold) ||_inf with
//    fE = f1*e1 + f3*e3 + f4*e4 + f5*e5 + f6*e6 + f7*e7;
//  * rejected step: first failure absh = max(hmin, absh*max(0.1,
//    0.8*(rtol/err)^0.2)); later failures absh = max(hmin, 0.5*absh);
//  * accepted step with no failure: temp = 1.25*(err/rtol)^0.2;
//    absh = (temp > 0.2) ? absh/temp : 5*absh;
//  * final-step stretch: if 1.1*absh >= |tfinal - t|, then h = tfinal - t,
//    tnew is set to tfinal exactly and h is recomputed as tnew - t;
//  * output rows: y0, then for each accepted step 3 interpolated points at
//    s = 1/4, 2/4, 3/4 (ntrp45split Horner form) and ynew, so
//    rows = 1 + 4*nsteps. Problem 4 sums over exactly these rows [PRESERVE].
// The only remaining differences from MATLAB are 1-ulp differences between
// the C library and MATLAB's libm in pow/exp (step-size selection and RHS).
// At RelTol = 0.1 they do not change which steps are accepted or rejected.

// MATLAB eps(x): gap from |x| to the next larger double; eps(0) is the
// smallest subnormal. Not valid at realmax (never reached here: t <= 0.78).
double matlab_eps(double x) {
    x = std::fabs(x);
    if (x == 0.0) {
        return 4.9406564584124654e-324;  // 2^-1074
    }
    return std::nextafter(x, kInf) - x;
}

// Integrates y' = f(t, y) from t0 to tfinal (needs tfinal > t0) with scalar
// RelTol = rtol and AbsTol = atol; rhs(t, y, dy) writes f into dy.
// Returns the output rows described above (1 + 4*nsteps states). Throws
// std::runtime_error if a step fails at the minimum step size hmin.
template <std::size_t Neq, typename Rhs>
std::vector<std::array<double, Neq>> ode45_matlab(const Rhs& rhs,
                                                  const std::array<double, Neq>& y0,
                                                  double t0, double tfinal,
                                                  double rtol, double atol) {
    using State = std::array<double, Neq>;

    // Dormand-Prince RK5(4) tableau. Same literal fractions as the reference,
    // so IEEE division rounds them to the same values.
    const double kPow = 1.0 / 5.0;
    const double a2 = 1.0 / 5.0, a3 = 3.0 / 10.0, a4 = 4.0 / 5.0, a5 = 8.0 / 9.0;
    const double b11 = 1.0 / 5.0;
    const double b21 = 3.0 / 40.0, b22 = 9.0 / 40.0;
    const double b31 = 44.0 / 45.0, b32 = -56.0 / 15.0, b33 = 32.0 / 9.0;
    const double b41 = 19372.0 / 6561.0, b42 = -25360.0 / 2187.0, b43 = 64448.0 / 6561.0,
                 b44 = -212.0 / 729.0;
    const double b51 = 9017.0 / 3168.0, b52 = -355.0 / 33.0, b53 = 46732.0 / 5247.0,
                 b54 = 49.0 / 176.0, b55 = -5103.0 / 18656.0;
    const double b61 = 35.0 / 384.0, b63 = 500.0 / 1113.0, b64 = 125.0 / 192.0,
                 b65 = -2187.0 / 6784.0, b66 = 11.0 / 84.0;
    const double e1 = 71.0 / 57600.0, e3 = -71.0 / 16695.0, e4 = 71.0 / 1920.0,
                 e5 = -17253.0 / 339200.0, e6 = 22.0 / 525.0, e7 = -1.0 / 40.0;
    // ntrp45split interpolant coefficients.
    const double bi12 = -183.0 / 64.0, bi13 = 37.0 / 12.0, bi14 = -145.0 / 128.0;
    const double bi32 = 1500.0 / 371.0, bi33 = -1000.0 / 159.0, bi34 = 1000.0 / 371.0;
    const double bi42 = -125.0 / 32.0, bi43 = 125.0 / 12.0, bi44 = -375.0 / 64.0;
    const double bi52 = 9477.0 / 3392.0, bi53 = -729.0 / 106.0, bi54 = 25515.0 / 6784.0;
    const double bi62 = -11.0 / 7.0, bi63 = 11.0 / 3.0, bi64 = -55.0 / 28.0;
    const double bi72 = 3.0 / 2.0, bi73 = -4.0, bi74 = 5.0 / 2.0;

    // Defaults from odearguments.m for the options the suite uses.
    const double epsDouble = 2.220446049250313e-16;  // eps('double')
    const double htspan = std::fabs(tfinal - t0);
    const double threshold = atol / rtol;
    const double safehmax = 16.0 * epsDouble * std::max(std::fabs(t0), std::fabs(tfinal));
    const double tlen = std::fabs(tfinal - t0);
    const double userhmax = std::max(0.1 * tlen, safehmax);  // default MaxStep
    const double userhmin = 0.0;                             // default MinStep

    double t = t0;
    State y = y0;
    State f1{};
    rhs(t, y, f1);  // f0

    std::vector<State> rows;
    rows.reserve(256);
    rows.push_back(y);

    // Initial step size (ode45.m rule when InitialStep is empty).
    double tinystep = 16.0 * matlab_eps(t);
    double hmin = std::max(tinystep, userhmin);
    double hmax = std::max(tinystep, userhmax);
    double absh = std::min(hmax, htspan);
    double rh = 0.0;
    for (std::size_t i = 0; i < Neq; ++i) {
        const double w = std::fabs(f1[i] / std::max(std::fabs(y[i]), threshold));
        if (w > rh) {  // norm(.,inf); NaN is skipped, as in MATLAB max
            rh = w;
        }
    }
    rh /= 0.8 * std::pow(rtol, kPow);
    if (absh * rh > 1.0) {
        absh = 1.0 / rh;
    }
    absh = std::max(absh, hmin);

    State y2{}, y3{}, y4{}, y5{}, y6{}, ynew{};
    State f2{}, f3{}, f4{}, f5{}, f6{}, f7{};

    bool done = false;
    while (!done) {
        tinystep = 16.0 * matlab_eps(t);
        hmin = std::max(tinystep, userhmin);
        hmax = std::max(tinystep, userhmax);
        absh = std::min(hmax, std::max(hmin, absh));
        double h = absh;  // tdir == +1 (tspan is [0, 0.78])

        // Stretch the step to tfinal if within 10% of tfinal - t.
        if (1.1 * absh >= std::fabs(tfinal - t)) {
            h = tfinal - t;
            absh = std::fabs(h);
            done = true;
        }

        bool nofailed = true;
        double err = 0.0;
        double tnew = t;
        while (true) {
            for (std::size_t i = 0; i < Neq; ++i) {
                y2[i] = y[i] + h * (b11 * f1[i]);
            }
            rhs(t + h * a2, y2, f2);
            for (std::size_t i = 0; i < Neq; ++i) {
                y3[i] = y[i] + h * (b21 * f1[i] + b22 * f2[i]);
            }
            rhs(t + h * a3, y3, f3);
            for (std::size_t i = 0; i < Neq; ++i) {
                y4[i] = y[i] + h * ((b31 * f1[i] + b32 * f2[i]) + b33 * f3[i]);
            }
            rhs(t + h * a4, y4, f4);
            for (std::size_t i = 0; i < Neq; ++i) {
                y5[i] = y[i] + h * (((b41 * f1[i] + b42 * f2[i]) + b43 * f3[i]) + b44 * f4[i]);
            }
            rhs(t + h * a5, y5, f5);
            for (std::size_t i = 0; i < Neq; ++i) {
                y6[i] = y[i] +
                        h * ((((b51 * f1[i] + b52 * f2[i]) + b53 * f3[i]) + b54 * f4[i]) + b55 * f5[i]);
            }
            rhs(t + h, y6, f6);

            tnew = t + h;
            if (done) {
                tnew = tfinal;  // Hit end point exactly.
            }
            h = tnew - t;  // Purify h: recompute it from tnew.

            for (std::size_t i = 0; i < Neq; ++i) {
                ynew[i] = y[i] +
                          h * ((((b61 * f1[i] + b63 * f3[i]) + b64 * f4[i]) + b65 * f5[i]) + b66 * f6[i]);
            }
            rhs(tnew, ynew, f7);

            // err = absh * norm(fE ./ max(max(|y|,|ynew|),threshold), inf)
            double scaled = 0.0;
            for (std::size_t i = 0; i < Neq; ++i) {
                const double fE =
                    ((((f1[i] * e1 + f3[i] * e3) + f4[i] * e4) + f5[i] * e5) + f6[i] * e6) + f7[i] * e7;
                const double denom = std::max(std::max(std::fabs(y[i]), std::fabs(ynew[i])), threshold);
                const double w = std::fabs(fE / denom);
                if (w > scaled) {
                    scaled = w;
                }
            }
            err = absh * scaled;

            if (err > rtol) {  // Failed step
                if (absh <= hmin) {
                    // MATLAB warns (IntegrationTolNotMet) and returns a
                    // truncated solution. Never reached for the suite's
                    // smooth RHS at RelTol = 0.1; throw instead.
                    throw std::runtime_error(
                        "cec2011 ode45: unable to meet integration tolerances without "
                        "reducing the step size below the smallest value allowed.");
                }
                if (nofailed) {
                    nofailed = false;
                    absh = std::max(hmin, absh * std::max(0.1, 0.8 * std::pow(rtol / err, kPow)));
                } else {
                    absh = std::max(hmin, 0.5 * absh);
                }
                h = absh;
                done = false;
            } else {  // Successful step
                break;
            }
        }

        // Refine=4 output: 3 interpolated points (ntrp45split) then ynew.
        for (int k = 1; k <= 3; ++k) {
            const double sk = static_cast<double>(k) / 4.0;  // S = (1:3)/4
            const double tref = t + (tnew - t) * sk;
            const double s = (tref - t) / h;
            const double s2 = s * s;
            const double bs1 = s + s2 * (bi12 + s * (bi13 + bi14 * s));
            const double bs3 = s2 * (bi32 + s * (bi33 + bi34 * s));
            const double bs4 = s2 * (bi42 + s * (bi43 + bi44 * s));
            const double bs5 = s2 * (bi52 + s * (bi53 + bi54 * s));
            const double bs6 = s2 * (bi62 + s * (bi63 + bi64 * s));
            const double bs7 = s2 * (bi72 + s * (bi73 + bi74 * s));
            State yi{};
            for (std::size_t i = 0; i < Neq; ++i) {
                yi[i] = y[i] + h * (((((f1[i] * bs1 + f3[i] * bs3) + f4[i] * bs4) + f5[i] * bs5) +
                                     f6[i] * bs6) +
                                    f7[i] * bs7);
            }
            rows.push_back(yi);
        }
        rows.push_back(ynew);

        if (done) {
            break;
        }

        // If this step had no failures, compute a new h.
        if (nofailed) {
            const double temp = 1.25 * std::pow(err / rtol, kPow);
            if (temp > 0.2) {
                absh = absh / temp;
            } else {
                absh = 5.0 * absh;
            }
        }

        // Advance the integration one step (FSAL: f1 <- f7).
        t = tnew;
        y = ynew;
        f1 = f7;
    }

    return rows;
}

// ---- Problem 1: FM sound-wave parameter estimation (bench_func.m case 1) ----

class FmSoundWaves final : public WpaProblem {
public:
    FmSoundWaves() : WpaProblem(1, 6, Vector(6, -6.4), Vector(6, 6.35)) {}

protected:
    Real objective(std::span<const Real> x) const override {
        const double theta = 2.0 * kPi / 100.0;
        double f = 0.0;
        for (int t = 0; t <= 100; ++t) {
            const double td = static_cast<double>(t);
            const double y_t =
                x[0] * std::sin(x[1] * td * theta +
                                x[2] * std::sin(x[3] * td * theta + x[4] * std::sin(x[5] * td * theta)));
            const double y0_t =
                1.0 * std::sin(5.0 * td * theta -
                               1.5 * std::sin(4.8 * td * theta + 2.0 * std::sin(4.9 * td * theta)));
            const double diff = y_t - y0_t;
            f = f + diff * diff;
        }
        return f;
    }
};

// ---- Problem 2: Lennard-Jones potential, 10 atoms (bench_func.m case 2) ----
// No guard for r == 0 [PRESERVE]: coincident atoms give 1/0 - 2/0 =
// Inf - Inf = NaN, which the NaN rule maps to 0 (the test probe at the
// bounds midpoint covers this).

class LennardJones final : public WpaProblem {
public:
    LennardJones()
        : WpaProblem(2, 30, atom_cluster_bounds().first, atom_cluster_bounds().second) {}

protected:
    Real objective(std::span<const Real> x) const override {
        constexpr int n = 10;
        double v = 0.0;
        for (int i = 0; i < n - 1; ++i) {
            for (int j = i + 1; j < n; ++j) {
                const double r = atom_distance(x, i, j);
                // a(i,j)=1, b(i,j)=2 in the reference.
                v = v + (1.0 / int_pow(r, 12) - 2.0 / int_pow(r, 6));
            }
        }
        return v;
    }
};

// ---- Problem 3: bifunctional catalyst blend optimal control ----
// From bench_func.m case 3, diffsolv.m and c_bifunc_data. The reference
// reloads c_bifunc_data.mat on every RHS call; here it is loaded once in the
// constructor, which gives the same numbers (port plan section 3).

// Reads a whitespace-separated table exported from MATLAB, skipping '#'
// comment lines. Layout: "rows cols", then rows*cols values. Returns every
// number in file order (dimensions first). Throws std::runtime_error if the
// file is missing or holds a non-numeric token.
std::vector<double> load_commented_table(const std::filesystem::path& path) {
    require_file(path);
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cec2011: cannot open data file: " + path.string());
    }
    std::vector<double> values;
    std::string line;
    while (std::getline(in, line)) {
        const std::size_t first = line.find_first_not_of(" \t\r");
        if (first == std::string::npos || line[first] == '#') {
            continue;
        }
        std::istringstream tokens(line);
        std::string token;
        while (tokens >> token) {
            try {
                std::size_t consumed = 0;
                const double value = std::stod(token, &consumed);
                if (consumed != token.size()) {
                    throw std::invalid_argument(token);
                }
                values.push_back(value);
            } catch (const std::exception&) {
                throw std::runtime_error("cec2011: non-numeric token '" + token +
                                         "' in data file: " + path.string());
            }
        }
    }
    return values;
}

class BifunctionalCatalyst final : public WpaProblem {
public:
    explicit BifunctionalCatalyst(const std::filesystem::path& data_root)
        : WpaProblem(3, 1, Vector(1, 0.6), Vector(1, 0.9)) {
        const std::filesystem::path path = data_root / "c_bifunc_data.txt";
        const std::vector<double> values = load_commented_table(path);
        if (values.size() != 2 + 40 || values[0] != 10.0 || values[1] != 4.0) {
            throw std::runtime_error("cec2011 f3: " + path.string() +
                                     " must hold a 10x4 table preceded by its dimensions.");
        }
        for (int i = 0; i < 10; ++i) {
            for (int j = 0; j < 4; ++j) {
                c_[static_cast<std::size_t>(i)][static_cast<std::size_t>(j)] =
                    values[static_cast<std::size_t>(2 + 4 * i + j)];
            }
        }
    }

protected:
    Real objective(std::span<const Real> x) const override {
        const double u = x[0];
        // diffsolv.m: ml = [1 u u^2 u^3]; k = sum(c.*repmat(ml,10,1), 2).
        const double u2 = u * u;
        const double u3 = u2 * u;
        std::array<double, 10> k{};
        for (std::size_t i = 0; i < 10; ++i) {
            k[i] = ((c_[i][0] * 1.0 + c_[i][1] * u) + c_[i][2] * u2) + c_[i][3] * u3;
        }
        const auto rhs = [&k](double /*t*/, const std::array<double, 7>& s,
                              std::array<double, 7>& dy) {
            dy[0] = -k[0] * s[0];
            dy[1] = (k[0] * s[0] - (k[1] + k[2]) * s[1]) + k[3] * s[4];
            dy[2] = k[1] * s[1];
            dy[3] = -k[5] * s[3] + k[4] * s[4];
            dy[4] = (((k[2] * s[1] + k[5] * s[3]) - ((((k[3] + k[4]) + k[7]) + k[8]) * s[4])) +
                     k[6] * s[5]) +
                    k[9] * s[6];
            dy[5] = k[7] * s[4] - k[6] * s[5];
            dy[6] = k[8] * s[4] - k[9] * s[6];
        };
        const std::array<double, 7> y0 = {1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
        const auto rows = ode45_matlab<7>(rhs, y0, 0.0, 0.78, 1.0e-01, 1.0e-6);
        // f = Y(end,end)*1e3: last output row, last state (y7).
        return rows.back()[6] * 1.0e+3;
    }

private:
    std::array<std::array<double, 4>, 10> c_{};
};

// ---- Problem 4: optimal control of a nonlinear stirred tank reactor ----
// From bench_func.m case 4 and intgrl.m. f = sum(sum(Y.^2,2) + 0.1*u*u) sums
// over the ode45 output rows (the Refine = 4 grid), so f depends on the
// number of accepted steps [PRESERVE].

class StirredTankReactor final : public WpaProblem {
public:
    StirredTankReactor() : WpaProblem(4, 1, Vector(1, 0.0), Vector(1, 5.0)) {}

protected:
    Real objective(std::span<const Real> x) const override {
        const double u = x[0];
        const auto rhs = [u](double /*t*/, const std::array<double, 2>& s,
                             std::array<double, 2>& dy) {
            // intgrl.m has the same exp(...) term in both equations;
            // computing it once gives the same bits.
            const double e = std::exp(25.0 * s[0] / (s[0] + 2.0));
            dy[0] = -(2.0 + u) * (s[0] + 0.25) + (s[1] + 0.5) * e;
            dy[1] = (0.5 - s[1]) - (s[1] + 0.5) * e;
        };
        const std::array<double, 2> y0 = {0.09, 0.09};
        const auto rows = ode45_matlab<2>(rhs, y0, 0.0, 0.78, 1.0e-01, 1.0e-6);
        const double q = (0.1 * u) * u;  // (0.1)*(u).*(u)
        double f = 0.0;
        for (const auto& row : rows) {
            f += (row[0] * row[0] + row[1] * row[1]) + q;
        }
        return f;
    }
};

// ---- Problems 5 and 6: Tersoff potentials Si(B) and Si(C) ----
// From bench_func.m cases 5 and 6 (same code, different constants).
// [PRESERVE] the law-of-cosines typo: ctheta uses rd3 CUBED, not squared.
// Coincident atoms give ctheta = 0/0 = NaN, which reaches f and is then set
// to 0 by the NaN rule (the test probe at the bounds midpoint covers this).

struct TersoffConstants {
    double R1, R2, A, B, lemda1, lemda2, lemda3, c, d, n1, gama, h;
};

constexpr TersoffConstants kTersoffSiB = {
    3.0, 0.2, 3.2647e+3, 9.5373e+1, 3.2394, 1.3258, 1.3258,
    4.8381, 2.0417, 22.956, 0.33675, 0.0};

constexpr TersoffConstants kTersoffSiC = {
    2.85, 0.15, 1.8308e+3, 4.7118e+2, 2.4799, 1.7322, 1.7322,
    1.0039e+05, 1.6218e+01, 7.8734e-01, 1.0999e-06, -5.9826e-01};

class TersoffPotential final : public WpaProblem {
public:
    TersoffPotential(int id, const TersoffConstants& constants)
        : WpaProblem(id, 30, atom_cluster_bounds().first, atom_cluster_bounds().second),
          k_(constants) {}

protected:
    Real objective(std::span<const Real> x) const override {
        constexpr int NP = 10;  // number of atoms (not a population size)
        std::array<std::array<double, NP>, NP> r{}, fcr{}, VRr{}, VAr{};
        for (int i = 0; i < NP; ++i) {
            for (int j = 0; j < NP; ++j) {
                const double rij = atom_distance(x, i, j);
                r[i][j] = rij;
                if (rij < (k_.R1 - k_.R2)) {
                    fcr[i][j] = 1.0;
                } else if (rij > (k_.R1 + k_.R2)) {
                    fcr[i][j] = 0.0;
                } else {
                    fcr[i][j] = 0.5 - 0.5 * std::sin(kPi / 2.0 * (rij - k_.R1) / k_.R2);
                }
                VRr[i][j] = k_.A * std::exp(-k_.lemda1 * rij);
                VAr[i][j] = k_.B * std::exp(-k_.lemda2 * rij);
            }
        }
        std::array<double, NP> E{};
        for (int i = 0; i < NP; ++i) {
            for (int j = 0; j < NP; ++j) {
                if (i == j) {
                    continue;
                }
                double jeta = 0.0;
                for (int kk = 0; kk < NP; ++kk) {
                    if (i == kk || j == kk) {
                        continue;
                    }
                    const double rd1 = r[i][kk];
                    const double rd3 = r[kk][j];
                    const double rd2 = r[i][j];
                    // (rd1^2 + rd2^2 - rd3^3) / (2*rd1*rd2) -- rd3 cubed [PRESERVE]
                    const double ctheta =
                        ((rd1 * rd1 + rd2 * rd2) - (rd3 * rd3) * rd3) / ((2.0 * rd1) * rd2);
                    const double G =
                        (1.0 + (k_.c * k_.c) / (k_.d * k_.d)) -
                        (k_.c * k_.c) / ((k_.d * k_.d) + (k_.h - ctheta) * (k_.h - ctheta));
                    const double dr = r[i][j] - r[i][kk];
                    jeta = jeta + (fcr[i][kk] * G) *
                                      std::exp(((k_.lemda3 * k_.lemda3) * k_.lemda3) *
                                               ((dr * dr) * dr));
                }
                const double Bij = std::pow(1.0 + std::pow(k_.gama * jeta, k_.n1), -0.5 / k_.n1);
                E[i] = E[i] + (fcr[i][j] * (VRr[i][j] - Bij * VAr[i][j])) / 2.0;
            }
        }
        double f = 0.0;
        for (int i = 0; i < NP; ++i) {
            f += E[i];
        }
        return f;
    }

private:
    TersoffConstants k_;
};

// ---- Problem 7: spread-spectrum radar polyphase code design ----
// From bench_func.m case 7. Empty j-ranges leave hsum(kk) = 0 (odd kk, i > d)
// or 0.5 (even kk, i >= d); these entries still count in the max [PRESERVE].

class SpreadSpectrumRadar final : public WpaProblem {
public:
    SpreadSpectrumRadar() : WpaProblem(7, 20, Vector(20, 0.0), Vector(20, 2.0 * kPi)) {}

protected:
    Real objective(std::span<const Real> x) const override {
        constexpr int d = 20;
        constexpr int var = 2 * d - 1;  // 39
        std::array<double, 2 * var> hsum{};
        for (int kk = 1; kk <= 2 * var; ++kk) {
            double acc = 0.0;
            if (kk % 2 != 0) {
                const int i = (kk + 1) / 2;
                for (int j = i; j <= d; ++j) {
                    double summ = 0.0;
                    for (int i1 = std::abs(2 * i - j - 1) + 1; i1 <= j; ++i1) {
                        summ = x[static_cast<std::size_t>(i1 - 1)] + summ;
                    }
                    acc = std::cos(summ) + acc;
                }
            } else {
                const int i = kk / 2;
                for (int j = i + 1; j <= d; ++j) {
                    double summ = 0.0;
                    for (int i1 = std::abs(2 * i - j) + 1; i1 <= j; ++i1) {
                        summ = x[static_cast<std::size_t>(i1 - 1)] + summ;
                    }
                    acc = std::cos(summ) + acc;
                }
                acc = acc + 0.5;
            }
            hsum[static_cast<std::size_t>(kk - 1)] = acc;
        }
        // f = max(hsum), skipping NaN like MATLAB max. The constant 0.5
        // entries (even kk, i >= d) are never NaN, so hsum is never all NaN
        // and this running max gives the same result as MATLAB.
        double f = -kInf;
        for (const double v : hsum) {
            if (v > f) {
                f = v;
            }
        }
        return f;
    }
};

// ---- Problem 8: transmission network expansion planning (TNEP) ----
// Garver 6-bus system, from bench_func.m case 8 and data6Bus.m.

struct TnepLine {
    int from;
    int to;
    double x;
    double pijmax;
    double cost;
};

// data6Bus.m columns used by bench_func case 8: from(2), to(3), X(4),
// Pijmax(6), cost(7). num_Line(5) and Overloads(8) are unused. Bus numbers
// are 1-based.
constexpr std::array<TnepLine, 7> kTnepBaseLines = {{
    {1, 2, 0.4, 1.0, kInf},
    {1, 4, 0.6, 0.8, kInf},
    {1, 5, 0.2, 1.0, kInf},
    {2, 3, 0.2, 1.0, kInf},
    {2, 4, 0.4, 1.0, kInf},
    {3, 5, 0.2, 1.0, 20.0},
    {6, 2, 0.3, 1.0, 30.0},
}};

constexpr std::array<TnepLine, 15> kTnepCandidates = {{
    {1, 2, 0.4, 1.0, 40.0},
    {1, 3, 0.38, 1.0, 38.0},
    {1, 4, 0.6, 0.8, 60.0},
    {1, 5, 0.2, 1.0, 20.0},
    {1, 6, 0.68, 0.7, 68.0},
    {2, 3, 0.2, 1.0, 20.0},
    {2, 4, 0.4, 1.0, 40.0},
    {2, 5, 0.31, 1.0, 31.0},
    {6, 2, 0.3, 1.0, 30.0},
    {3, 4, 0.69, 0.82, 59.0},
    {3, 5, 0.2, 1.0, 20.0},
    {6, 3, 0.48, 1.0, 48.0},
    {4, 5, 0.63, 0.75, 63.0},
    {4, 6, 0.30, 1.0, 30.0},
    {5, 6, 0.61, 0.78, 61.0},
}};

constexpr std::array<double, 6> kTnepPgen = {0.5, 0.0, 1.65, 0.0, 0.0, 5.45};
constexpr std::array<double, 6> kTnepPload = {0.8, 2.4, 0.4, 1.6, 2.4, 0.0};

// Replaces MATLAB inv() for the 6x6 susceptance matrix: LU factorization with
// partial pivoting (as LAPACK dgetrf), then one solve per identity column.
// May differ from MATLAB's LAPACK in the last ulp; agreement is ~1e-15
// relative, well inside the 1e-12 probe tolerance. A singular matrix gives
// Inf/NaN, as MATLAB inv does (with a warning).
void invert6(const std::array<std::array<double, 6>, 6>& a,
             std::array<std::array<double, 6>, 6>& inv) {
    std::array<std::array<double, 6>, 6> lu = a;
    std::array<int, 6> piv{};
    for (int col = 0; col < 6; ++col) {
        int p = col;
        double best = std::fabs(lu[col][col]);
        for (int row = col + 1; row < 6; ++row) {
            const double mag = std::fabs(lu[row][col]);
            if (mag > best) {
                best = mag;
                p = row;
            }
        }
        piv[col] = p;
        if (p != col) {
            std::swap(lu[p], lu[col]);
        }
        const double pivot = lu[col][col];
        for (int row = col + 1; row < 6; ++row) {
            lu[row][col] /= pivot;
            const double m = lu[row][col];
            for (int cc = col + 1; cc < 6; ++cc) {
                lu[row][cc] -= m * lu[col][cc];
            }
        }
    }
    for (int e = 0; e < 6; ++e) {
        std::array<double, 6> b{};
        b[e] = 1.0;
        for (int col = 0; col < 6; ++col) {
            if (piv[col] != col) {
                std::swap(b[piv[col]], b[col]);
            }
        }
        for (int row = 1; row < 6; ++row) {
            double acc = b[row];
            for (int cc = 0; cc < row; ++cc) {
                acc -= lu[row][cc] * b[cc];
            }
            b[row] = acc;
        }
        for (int row = 5; row >= 0; --row) {
            double acc = b[row];
            for (int cc = row + 1; cc < 6; ++cc) {
                acc -= lu[row][cc] * b[cc];
            }
            b[row] = acc / lu[row][row];
        }
        for (int row = 0; row < 6; ++row) {
            inv[row][e] = b[row];
        }
    }
}

class TransmissionExpansion final : public WpaProblem {
public:
    TransmissionExpansion() : WpaProblem(8, 7, Vector(7, 0.0), Vector(7, 15.0)) {}

protected:
    Real objective(std::span<const Real> x) const override {
        // sw = ceil(x) picks row Candidate(sw,:) (1-based). The bounds allow
        // x == 0, where MATLAB Candidate(ceil(0),:) would use index 0, so sw
        // is clamped to 1..15 and x == 0 maps to the first candidate. This
        // keeps F8 usable when an optimizer lands on lb and keeps the 15
        // candidate choices.
        std::array<int, 7> sw{};
        for (std::size_t kIdx = 0; kIdx < 7; ++kIdx) {
            const double c = std::ceil(x[kIdx]);
            sw[kIdx] = std::clamp(static_cast<int>(c), 1, 15);
        }

        // Linedata = [base; Candidate(sw(1..7),:)] -- duplicates allowed.
        std::array<TnepLine, 14> lines{};
        for (std::size_t i = 0; i < 7; ++i) {
            lines[i] = kTnepBaseLines[i];
        }
        for (std::size_t kIdx = 0; kIdx < 7; ++kIdx) {
            lines[7 + kIdx] = kTnepCandidates[static_cast<std::size_t>(sw[kIdx] - 1)];
        }

        // DC power flow susceptance matrix (bench_func.m lines 249-264).
        std::array<std::array<double, 6>, 6> B{};
        for (const TnepLine& line : lines) {
            const double bline = 1.0 / line.x;
            const int k = line.from - 1;
            const int m = line.to - 1;
            B[k][m] = B[k][m] - bline;
            B[m][k] = B[k][m];
            B[k][k] = B[k][k] + bline;
            B[m][m] = B[m][m] + bline;
        }
        B[0][0] = 10000000.0;  // slack regularization [PRESERVE]

        std::array<std::array<double, 6>, 6> X{};
        invert6(B, X);

        std::array<double, 6> delP{};
        for (std::size_t i = 0; i < 6; ++i) {
            delP[i] = kTnepPgen[i] - kTnepPload[i];
        }
        std::array<double, 6> delta{};
        for (std::size_t i = 0; i < 6; ++i) {
            double acc = 0.0;
            for (std::size_t j = 0; j < 6; ++j) {
                acc += X[i][j] * delP[j];
            }
            delta[i] = acc;
        }

        std::array<double, 14> pij{};
        for (std::size_t kIdx = 0; kIdx < 14; ++kIdx) {
            const TnepLine& line = lines[kIdx];
            pij[kIdx] = (delta[static_cast<std::size_t>(line.from - 1)] -
                         delta[static_cast<std::size_t>(line.to - 1)]) /
                        line.x;
        }

        // f = sum(cost of the 7 appended candidate lines) + 30.
        double f = 0.0;
        for (std::size_t i = 7; i < 14; ++i) {
            f += lines[i].cost;
        }
        f = f + 30.0;

        // Penalties: 5000*(|pij| - pijmax) for each overloaded line, plus
        // 1000 for each candidate chosen more than 3 times.
        double pen = 0.0;
        for (std::size_t i = 0; i < 14; ++i) {
            pen = pen + 5000.0 * hinge_at_zero(std::fabs(pij[i]) - lines[i].pijmax);
        }
        for (int i = 1; i <= 15; ++i) {
            int count = 0;
            for (const int s : sw) {
                if (s == i) {
                    ++count;
                }
            }
            if (count > 3) {
                pen = pen + 1000.0;
            }
        }
        return f + pen;
    }
};

// ---- Problem 10: circular antenna array design ----
// From Calc_Fitx_2011.m case 10 (null = [50 120], phi_desired = 180,
// distance = 0.5), antennafunccircular.m and array_factorcir.m.
// Quirks kept:
//  * array_factorcir and antennafunccircular use a truncated local
//    pi = 3.141592654 instead of the built-in pi [PRESERVE]. trapezoidalcir
//    does not, but it is not needed here (see below).
//  * the null angles 50 and 120 go to the array factor unconverted, so they
//    act as radians, while the scan grid is converted from degrees
//    [PRESERVE].
//  * the directivity term (trapezoidalcir + 2*pi*maxi^2/uavg) is only stored
//    in `global directivity`, which nothing reads, and never enters the
//    objective, so it is not computed (port plan sections 1 and 5/P10).

class CircularAntennaArray final : public WpaProblem {
public:
    CircularAntennaArray() : WpaProblem(10, 12, make_lower(), make_upper()) {}

protected:
    Real objective(std::span<const Real> x) const override {
        constexpr int num1 = 300;
        const double pl = 3.141592654;  // local pi [PRESERVE]

        // phi = linspace(0,360,300) in degrees: y(i) = ((i-1)*360)/299 with
        // both endpoints set exactly (MATLAB linspace.m general branch).
        std::array<double, num1> phi{};
        for (int i = 0; i < num1; ++i) {
            phi[static_cast<std::size_t>(i)] = (static_cast<double>(i) * 360.0) / 299.0;
        }
        phi[0] = 0.0;
        phi[num1 - 1] = 360.0;

        std::array<double, num1> yax{};
        yax[0] = array_factor(x, (pl / 180.0) * phi[0]);
        double maxi = yax[0];
        double phizero = 0.0;
        int phi_ref = 1;  // 1-based like the reference
        for (int i = 2; i <= num1; ++i) {
            const double value = array_factor(x, (pl / 180.0) * phi[static_cast<std::size_t>(i - 1)]);
            yax[static_cast<std::size_t>(i - 1)] = value;
            if (maxi < value) {
                maxi = value;
                phizero = phi[static_cast<std::size_t>(i - 1)];
                phi_ref = i;
            }
        }

        // Collect sidelobes: endpoint peaks first, then strict interior peaks.
        std::vector<double> sidelobes;
        sidelobes.reserve(64);
        if (yax[0] > yax[num1 - 1] && yax[0] > yax[1]) {
            sidelobes.push_back(yax[0]);
        }
        if (yax[num1 - 1] > yax[0] && yax[num1 - 1] > yax[num1 - 2]) {
            sidelobes.push_back(yax[num1 - 1]);
        }
        for (int i = 2; i <= num1 - 1; ++i) {
            if (yax[static_cast<std::size_t>(i - 1)] > yax[static_cast<std::size_t>(i)] &&
                yax[static_cast<std::size_t>(i - 1)] > yax[static_cast<std::size_t>(i - 2)]) {
                sidelobes.push_back(yax[static_cast<std::size_t>(i - 1)]);
            }
        }
        std::sort(sidelobes.begin(), sidelobes.end(), std::greater<double>());
        if (sidelobes.size() < 2) {
            // The reference would fail on sidelobes(2) (index out of range).
            // Not reached: real 12-element patterns have >= 2 local maxima.
            throw std::runtime_error("cec2011 f10: fewer than two pattern maxima "
                                     "(reference MATLAB code would error here).");
        }
        const double sllreturn = 20.0 * std::log10(sidelobes[1] / maxi);

        // Beamwidth: walk from phi_ref to the first local minimum each side.
        double upper_bound = 180.0;
        double lower_bound = 180.0;
        for (int i = 1; i <= num1 / 2; ++i) {
            if ((phi_ref + i) > num1 - 1) {
                upper_bound = 180.0;
                break;
            }
            if (yax[static_cast<std::size_t>(phi_ref + i - 1)] <
                    yax[static_cast<std::size_t>(phi_ref + i - 2)] &&
                yax[static_cast<std::size_t>(phi_ref + i - 1)] <
                    yax[static_cast<std::size_t>(phi_ref + i)]) {
                upper_bound = phi[static_cast<std::size_t>(phi_ref + i - 1)] -
                              phi[static_cast<std::size_t>(phi_ref - 1)];
                break;
            }
        }
        for (int i = 1; i <= num1 / 2; ++i) {
            if (phi_ref - i < 2) {
                lower_bound = 180.0;
                break;
            }
            if (yax[static_cast<std::size_t>(phi_ref - i - 1)] <
                    yax[static_cast<std::size_t>(phi_ref - i - 2)] &&
                yax[static_cast<std::size_t>(phi_ref - i - 1)] <
                    yax[static_cast<std::size_t>(phi_ref - i)]) {
                lower_bound = phi[static_cast<std::size_t>(phi_ref - 1)] -
                              phi[static_cast<std::size_t>(phi_ref - i - 1)];
                break;
            }
        }
        const double bwfn = upper_bound + lower_bound;

        // Null control: null = [50, 120] passed raw (radians) [PRESERVE].
        double y1 = 0.0;
        y1 = y1 + (array_factor(x, 50.0) / maxi);
        y1 = y1 + (array_factor(x, 120.0) / maxi);

        // Pointing error (degrees), zeroed under 5 degrees.
        double y3 = std::fabs(phizero - 180.0);
        if (y3 < 5.0) {
            y3 = 0.0;
        }

        // Beamwidth penalty above 80 degrees.
        double y = 0.0;
        if (bwfn > 80.0) {
            y = y + std::fabs(bwfn - 80.0);
        }

        return ((sllreturn + y) + y1) + y3;
    }

private:
    // Bounds: amplitudes x(1:6) in [0.2, 1], phases x(7:12) in [-180, 180]
    // degrees.
    static Vector make_lower() {
        Vector lo(12);
        for (int j = 0; j < 12; ++j) {
            lo[static_cast<std::size_t>(j)] = j < 6 ? 0.2 : -180.0;
        }
        return lo;
    }
    static Vector make_upper() {
        Vector hi(12);
        for (int j = 0; j < 12; ++j) {
            hi[static_cast<std::size_t>(j)] = j < 6 ? 1.0 : 180.0;
        }
        return hi;
    }

    // array_factorcir.m with dim = 12, phi_desired = 180, distance = 0.5.
    // Returns the array factor magnitude at angle phi (radians); x1(1:6) are
    // amplitudes, x1(7:12) phases in degrees.
    static double array_factor(std::span<const Real> x1, double phi) {
        constexpr int dim = 12;
        const double pl = 3.141592654;  // local pi [PRESERVE]
        double y = 0.0;
        double y1 = 0.0;
        for (int i1 = 1; i1 <= dim / 2; ++i1) {
            const double delphi = (2.0 * pl) * static_cast<double>(i1 - 1) / 12.0;
            double shi = std::cos(phi - delphi) - std::cos(180.0 * (pl / 180.0) - delphi);
            shi = (shi * 12.0) * 0.5;  // shi*dim*distance
            y = y + x1[static_cast<std::size_t>(i1 - 1)] *
                        std::cos(shi + x1[static_cast<std::size_t>(dim / 2 + i1 - 1)] * (pl / 180.0));
        }
        for (int i1 = dim / 2 + 1; i1 <= dim; ++i1) {
            const double delphi = (2.0 * pl) * static_cast<double>(i1 - 1) / 12.0;
            double shi = std::cos(phi - delphi) - std::cos(180.0 * (pl / 180.0) - delphi);
            shi = (shi * 12.0) * 0.5;
            y = y + x1[static_cast<std::size_t>(i1 - dim / 2 - 1)] *
                        std::cos(shi - x1[static_cast<std::size_t>(i1 - 1)] * (pl / 180.0));
        }
        for (int i1 = 1; i1 <= dim / 2; ++i1) {
            const double delphi = (2.0 * pl) * static_cast<double>(i1 - 1) / 12.0;
            double shi = std::cos(phi - delphi) - std::cos(180.0 * (pl / 180.0) - delphi);
            shi = (shi * 12.0) * 0.5;
            y1 = y1 + x1[static_cast<std::size_t>(i1 - 1)] *
                          std::sin(shi + x1[static_cast<std::size_t>(dim / 2 + i1 - 1)] * (pl / 180.0));
        }
        for (int i1 = dim / 2 + 1; i1 <= dim; ++i1) {
            const double delphi = (2.0 * pl) * static_cast<double>(i1 - 1) / 12.0;
            double shi = std::cos(phi - delphi) - std::cos(180.0 * (pl / 180.0) - delphi);
            shi = (shi * 12.0) * 0.5;
            y1 = y1 + x1[static_cast<std::size_t>(i1 - dim / 2 - 1)] *
                          std::sin(shi - x1[static_cast<std::size_t>(i1 - 1)] * (pl / 180.0));
        }
        y = y * y + y1 * y1;
        return std::sqrt(y);
    }
};

}  // namespace

std::unique_ptr<BenchmarkProblem> make_problem_wpa(int function_id,
                                                   const std::filesystem::path& data_root) {
    switch (function_id) {
    case 1:
        return std::make_unique<FmSoundWaves>();
    case 2:
        return std::make_unique<LennardJones>();
    case 3:
        return std::make_unique<BifunctionalCatalyst>(data_root);
    case 4:
        return std::make_unique<StirredTankReactor>();
    case 5:
        return std::make_unique<TersoffPotential>(5, kTersoffSiB);
    case 6:
        return std::make_unique<TersoffPotential>(6, kTersoffSiC);
    case 7:
        return std::make_unique<SpreadSpectrumRadar>();
    case 8:
        return std::make_unique<TransmissionExpansion>();
    case 10:
        return std::make_unique<CircularAntennaArray>();
    default:
        throw std::invalid_argument("cec2011: work package A implements problems 1-8 and 10, got " +
                                    std::to_string(function_id) + ".");
    }
}

}  // namespace gskcec::cec2011::detail
