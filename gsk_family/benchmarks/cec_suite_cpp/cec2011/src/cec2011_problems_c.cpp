// cec2011_problems_c.cpp -- CEC2011 real-world suite, work package C:
//   problem 21: Messenger (full mission) MGA-DSM trajectory  (D = 26)
//   problem 22: Cassini 2 MGA-DSM trajectory                 (D = 22)
//
// Ported from the read-only CEC2011 MATLAB package:
//   messengerfull.m / cassini2.m     one-line wrappers around mga_dsm
//   mga_dsm.m                        ESA ACT Space Mechanics Toolbox,
//                                    D. Izzo / C. Bombardelli, rev. 4 2007
//                                    (all line numbers below refer to it)
//   define_boundaries.m cases 21/22  bounds (canonical for the GSK runs)
//   Calc_Fitx_2011.m cases 21/22     dispatch and the NaN -> 0 rule
// See docs/reference/cec2011_port_plan.md, "Problem 21/22" and section 6.
//
// Only the code paths of these two problems are ported:
//   'orbit insertion' (P21):  J = DVtot, DV(N) = |DVper - DVper2|
//   'total DV rndv'   (P22):  J = DVtot + VINF, DV(N) = DVrel
// Unused mga_dsm.m branches are left out: 'gtoc1', 'time to AUs', 'rndv',
// 'total DV orbit insertion', 'deflection demo', CUSTOMeph (reached only
// for sequence entries >= 10; the only user of "global AU mu"),
// time2distance, and the mjd20002jed/mjd2jed helpers used only by those
// branches. The yplot branch only plots (problem.yplot == 0 in both .mat
// structs) and is dropped.
//
// Reference quirks kept on purpose (do NOT "fix" them):
//  * Three solar gravitational constants stay separate (plan section 6):
//    kMuSunMain = 1.32712428e11 (line 120) drives propagateKEP and
//    lambertI, i.e. every spacecraft arc; kMuSunPlephAnUnused =
//    1.327124400180000e11 (line 953) is defined in pleph_an but never used
//    (planet states come from conversion()); kMuSunConversion =
//    1.327124280000000e11 (line 1099) is local to conversion() and gives
//    the planet position/velocity. The first and third are the same
//    double; each stays in its own scope so it traces to the reference.
//  * propagateKEP "DD" rotation (lines 498-506, 519-520): if the orbit
//    normal is within 1e-3 of +-z, the state is rotated by
//    DD = [1 0 0; 0 0 1; 0 -1 0] before IC2par and by DD' after par2IC,
//    so the Euler angles stay defined for near-ecliptic orbits.
//  * The lambertI N == 0 secant loop (lines 759-771) has NO iteration cap,
//    only "while err>tol && y1~=y2". It could in theory hang if the
//    log-secant iterates cycle without meeting either test; within the
//    suite bounds (transfer time > 0, finite geometry) it converges in a
//    few steps.
//  * M2E (lines 1140-1151) always uses the ELLIPTIC Kepler-Newton iteration
//    (guess E = M + e*cos(M), tol 1e-10, at most 100 iterations), whatever
//    the eccentricity. propagateKEP calls it even for hyperbolic states,
//    whose mean anomaly comes from the Gudermannian branch of E2M. Wrong
//    physics, but deterministic output.
//  * IC2par guards only the true-anomaly acos with real(...) (line 565):
//    for real |x| > 1, MATLAB's real(acos(x)) is 0 (x > 1) or pi (x < -1),
//    and this port does the same. The other acos/asin calls (inclination,
//    node, argument of perigee, Lambert transfer angle, beta) are
//    unguarded: if rounding pushed an argument outside [-1,1], MATLAB would
//    silently go complex and this port (plain double) would give NaN.
//    Checks against the MATLAB ground truth (cec2011_expected.csv) show
//    this never happens for the reference probes, so std::complex is not
//    needed (plan section 4, problems 21/22).
//  * lw at the call sites (lines 254-260 etc.) comes from the sign of the
//    z-component of cross(rd, r_next): MATLAB maps sign +1 to lw = 0 and
//    sign 0 or -1 to lw = 1 (sign(0) == 0, not 1). Coded as (z>0)?0:1.
//  * lambertI returns [NaN;NaN;NaN] velocities when the transfer time is
//    <= 0 (lines 711-716). Unreachable within the suite bounds
//    (tof >= 30 days, alpha <= 0.99), but kept.
//  * Before porting, MATLAB's scalar/builtin kernels were checked bit for
//    bit against MATLAB R2025b on random sweeps of 2e5 samples (details at
//    each helper below): mod(a,m) is the exact fmod remainder moved into
//    the sign of m, NOT the documented a - m*floor(a/m) (~1e-13 rad off
//    for the wrapped mean anomalies); x^2 == x*x exactly; x^3 is MATLAB's
//    own pow kernel (std::pow(x,3.0) is the closest reproducible match);
//    the 3-element dot x'*y sums right to left, x1*y1 + (x2*y2 + x3*y3);
//    norm(x) sums the squares in extended precision (x87 long double here);
//    sum(DV) is a plain sequential sum. Compound expressions follow
//    MATLAB's left-to-right order so intermediate rounding matches.
//  * The reference reloads the problem .mat INSIDE the per-individual loop
//    (Calc_Fitx_2011.m lines 49/53); this only costs time. This port loads
//    and validates the problem definition ONCE, in the constructor (plan
//    section 3.4).
//  * Bounds come from define_boundaries.m (used for the GSK runs), NOT from
//    getlimit_messenger.m / getlimit_cassini2.m / the .mat "bounds" fields.
//    So the P22 element 9 lower bound is 400, although getlimit_cassini2.m
//    and the .mat give 800 (the official GTOP value). Plan section 3.6
//    [PRESERVE 400].
//  * The NaN -> 0 rule of Calc_Fitx_2011.m (lines 57-61) is the last step
//    of evaluate(), via detail::apply_reference_nan_rule.
//
// Reference oddities that do not change any result:
//  * mga_dsm.m line 247 sets tDSM(1) before line 271 re-creates tDSM as
//    zeros(N-1,1); the value is used (line 250) before it is wiped.
//  * In the lambertI N == 0 branch, if the two starting ordinates were
//    exactly equal (y1 == y2, impossible as the tof curve is strictly
//    monotonic), MATLAB would crash on the undefined variable xnew. This
//    port sets xnew to NaN instead, giving a NaN cost and then 0 via the
//    NaN rule. This is the only deliberate difference from the reference,
//    and it lies on a path that cannot be reached.
//
// The problem definitions (planet sequence, objective type, rp, e) are read
// from text files exported from the MATLAB .mat data, so they stay
// traceable to it:
//   <data_root>/messengerfull_problem.txt and <data_root>/cassini2_problem.txt
// The constructor checks the parsed values against these constants from
// the port plan:
//   P21: sequence [3 2 2 1 1 1 1], 'orbit insertion', rp = 2640, e = 0.704
//   P22: sequence [3 2 2 3 5 6], 'total DV rndv'
//
// Thread safety: evaluate() is const and uses only local state, so one
// instance can be shared across threads.

#include "cec2011_detail.hpp"

#include "gskcec/benchmark/data_loading.hpp"

#include <array>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <numbers>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace gskcec::cec2011::detail {

namespace {

constexpr double kPi = std::numbers::pi_v<double>; // same value as MATLAB pi

using Vec3 = std::array<double, 3>;

// ---- Small vector helpers (mga_dsm.m lines 892-904) ----

// vett (lines 899-904): cross product r1 x r2. MATLAB's cross(), which the
// reference calls only at lines 230/234, uses the same component formulas.
inline Vec3 vett(const Vec3& r1, const Vec3& r2) {
    return {r1[1] * r2[2] - r1[2] * r2[1],
            r1[2] * r2[0] - r1[0] * r2[2],
            r1[0] * r2[1] - r1[1] * r2[0]};
}

// x'*y for column 3-vectors. MATLAB sums small dot products right to left:
// x1*y1 + (x2*y2 + x3*y3). Tested against MATLAB R2025b with mixed
// magnitudes: the left-to-right form is 1 ulp off in ~27% of random
// cases, this form in 0 of 200000.
inline double dot3(const Vec3& a, const Vec3& b) {
    return a[0] * b[0] + (a[1] * b[1] + a[2] * b[2]);
}

// norm(x) of a real 3-vector. MATLAB does NOT compute this as a plain
// double sqrt(x'*x): against MATLAB R2025b that form is 1 ulp off in ~19%
// of cases. An extended-precision (x87 80-bit) sum of squares + sqrt
// matches MATLAB's norm() exactly (0 of 200000 mismatches for position,
// velocity and unit-vector magnitudes).
// Needs long double to be x87 extended (true for the MinGW toolchains this
// project builds with). Where long double == double this falls back to the
// plain form; results then agree only to ~1e-13 (relative) on the long P21
// swingby chain.
inline double norm3(const Vec3& a) {
    const long double x = a[0];
    const long double y = a[1];
    const long double z = a[2];
    return static_cast<double>(sqrtl(x * x + y * y + z * z));
}

// MATLAB scalar x^3 (mga_dsm uses ^3 only inside sqrt(mu/a^3) terms).
// MATLAB's power kernel is NOT (x*x)*x (1 ulp apart in ~27% of cases).
// std::pow(x, 3.0) is the closest reproducible form: UCRT pow is correctly
// rounded within ~5e-4 of cases and matches MATLAB in ~90%. The rest is
// MATLAB's own ~1 ulp pow error, which no closed-form double expression
// reproduces.
inline double matlab_cube(double x) {
    return std::pow(x, 3.0);
}

// vers (lines 892-894): unit vector V/sqrt(V'*V). The reference writes the
// norm out in plain double here (not norm()), so this uses dot3(), not
// norm3().
inline Vec3 vers(const Vec3& v) {
    const double n = std::sqrt(dot3(v, v));
    return {v[0] / n, v[1] / n, v[2] / n};
}

// MATLAB mod(a,m) for finite doubles and m > 0. MATLAB documents
// b = a - m.*floor(a./m), but for scalar doubles it returns the EXACT
// remainder (as std::fmod) moved into the sign of m. The floor formula
// adds the rounding of m*floor(a/m): for the ~1.5e5-degree Mercury/Venus
// mean anomalies wrapped here that is ~1e-13 rad. Checked against MATLAB
// R2025b: only the fmod form reproduces mod(E(6), 2*pi) bit for bit.
inline double matlab_mod(double a, double m) {
    double r = std::fmod(a, m);
    if (r != 0.0 && (r < 0.0) != (m < 0.0)) {
        r = r + m;
    }
    return r;
}

// ---- Anomaly conversions ----

// M2E (lines 1140-1151): mean -> eccentric anomaly by Newton iteration on
// the ELLIPTIC Kepler equation; initial guess E = M + e*cos(M), tol 1e-10,
// at most 100 iterations.
// [PRESERVE] The reference uses it for every e, also e > 1 (M then comes
// from the hyperbolic, Gudermannian branch of E2M). Wrong physics, but
// deterministic arithmetic, so it is kept as is.
double M2E(double M, double e) {
    int i = 0;
    const double tol = 1e-10;
    double err = 1.0;
    double E = M + e * std::cos(M); // initial guess
    while (err > tol && i < 100) {
        i = i + 1;
        const double Enew = E - (E - e * std::sin(E) - M) / (1 - e * std::cos(E));
        err = std::fabs(E - Enew);
        E = Enew;
    }
    return E;
}

// E2M (lines 1155-1170): eccentric anomaly -> mean anomaly. For e >= 1 the
// input is the Gudermannian and the output is the hyperbolic mean anomaly N.
double E2M(double E, double e) {
    if (e < 1) { // Ellipse, E is the eccentric anomaly
        return E - e * std::sin(E);
    }
    // Hyperbola, E is the Gudermannian
    return e * std::tan(E) - std::log(std::tan(E / 2 + kPi / 4));
}

// ni2E (lines 574-579): true anomaly -> eccentric anomaly (e < 1) or
// Gudermannian (e >= 1).
double ni2E(double ni, double e) {
    if (e < 1) {
        return 2 * std::atan(std::sqrt((1 - e) / (1 + e)) * std::tan(ni / 2));
    }
    return 2 * std::atan(std::sqrt((e - 1) / (e + 1)) * std::tan(ni / 2));
}

// ---- Orbital element <-> state conversions ----

// IC2par (lines 524-570): state (r0, v0) -> elements E = (a [negative for
// hyperbolas], e, i, OM, om, eccentric anomaly or Gudermannian). Only the
// true-anomaly acos has the reference's real(...) guard; the others are
// unguarded [PRESERVE].
std::array<double, 6> IC2par(const Vec3& r0, const Vec3& v0, double mu) {
    const Vec3 k = {0.0, 0.0, 1.0};
    const Vec3 h = vett(r0, v0);
    const double p = dot3(h, h) / mu;
    Vec3 n = vett(k, h);
    {
        const double nn = norm3(n);
        n = {n[0] / nn, n[1] / nn, n[2] / nn};
    }
    const double R0 = norm3(r0);
    const Vec3 vh = vett(v0, h);
    const Vec3 evett = {vh[0] / mu - r0[0] / R0,
                        vh[1] / mu - r0[1] / R0,
                        vh[2] / mu - r0[2] / R0};
    std::array<double, 6> E;
    double e = dot3(evett, evett); // e^2 at this point, exactly as in the reference
    E[0] = p / (1 - e);
    E[1] = std::sqrt(e);
    e = E[1];
    E[2] = std::acos(h[2] / norm3(h));
    E[4] = std::acos(dot3(n, evett) / e);
    if (evett[2] < 0) {
        E[4] = 2 * kPi - E[4];
    }
    E[3] = std::acos(n[0]);
    if (n[1] < 0) {
        E[3] = 2 * kPi - E[3];
    }
    // ni = real(acos(...)): the real part of MATLAB's (principal, complex)
    // acos is 0 for arguments > 1 and pi for arguments < -1.
    const double cni = dot3(evett, r0) / e / R0;
    double ni;
    if (cni > 1.0) {
        ni = 0.0;
    } else if (cni < -1.0) {
        ni = kPi;
    } else {
        ni = std::acos(cni);
    }
    if (dot3(r0, v0) < 0) {
        ni = 2 * kPi - ni;
    }
    E[5] = ni2E(ni, e);
    return E;
}

// par2IC (lines 584-647): elements E -> state (r0, v0). The hyperbola
// branch uses the tan(EA) form and dNdzeta exactly as in the reference.
void par2IC(const std::array<double, 6>& E, double mu, Vec3& r0, Vec3& v0) {
    const double a = E[0];
    const double e = E[1];
    const double i = E[2];
    const double omg = E[3];
    const double omp = E[4];
    const double EA = E[5];

    double xper, yper, xdotper, ydotper;
    if (e < 1) {
        const double b = a * std::sqrt(1 - e * e);
        const double n = std::sqrt(mu / matlab_cube(a));
        const double cEA = std::cos(EA);
        const double sEA = std::sin(EA);
        xper = a * (cEA - e);
        yper = b * sEA;
        xdotper = -((a * n) * sEA) / (1 - e * cEA);
        ydotper = ((b * n) * cEA) / (1 - e * cEA);
    } else {
        const double b = -a * std::sqrt(e * e - 1);
        const double n = std::sqrt(-mu / matlab_cube(a));
        const double tEA = std::tan(EA);
        const double cEA = std::cos(EA);
        const double th = std::tan(0.5 * EA + 0.25 * kPi); // tan(1/2*EA+1/4*pi)
        const double dNdzeta = e * (1 + tEA * tEA) - (0.5 + 0.5 * (th * th)) / th;
        xper = a / cEA - a * e;
        yper = b * tEA;
        xdotper = (((a * tEA) / cEA) * n) / dNdzeta;
        ydotper = ((b / (cEA * cEA)) * n) / dNdzeta;
    }

    const double cog = std::cos(omg), sog = std::sin(omg);
    const double cop = std::cos(omp), sop = std::sin(omp);
    const double ci = std::cos(i), si = std::sin(i);
    const double R11 = cog * cop - (sog * sop) * ci;
    const double R12 = -(cog * sop) - (sog * cop) * ci;
    const double R13 = sog * si;
    const double R21 = sog * cop + (cog * sop) * ci;
    const double R22 = -(sog * sop) + (cog * cop) * ci;
    const double R23 = -(cog * si);
    const double R31 = sop * si;
    const double R32 = cop * si;
    const double R33 = ci;
    // r0 = R*[xper;yper;0]. The zero third column is kept so signed zeros
    // come out exactly as in MATLAB's matrix-vector product.
    r0 = {R11 * xper + (R12 * yper + R13 * 0.0), R21 * xper + (R22 * yper + R23 * 0.0),
          R31 * xper + (R32 * yper + R33 * 0.0)};
    v0 = {R11 * xdotper + (R12 * ydotper + R13 * 0.0),
          R21 * xdotper + (R22 * ydotper + R23 * 0.0),
          R31 * xdotper + (R32 * ydotper + R33 * 0.0)};
}

// conversion (lines 1095-1135): elements E -> planet state (r, v). Uses its
// OWN local solar gravitational constant [PRESERVE; one of the three muSUN
// constants, see the file header].
void conversion(const std::array<double, 6>& E, Vec3& r, Vec3& v) {
    constexpr double kMuSunConversion = 1.327124280000000e+11; // line 1099

    const double a = E[0];
    const double e = E[1];
    const double i = E[2];
    const double omg = E[3];
    const double omp = E[4];
    const double EA = E[5];

    const double b = a * std::sqrt(1 - e * e);
    const double n = std::sqrt(kMuSunConversion / matlab_cube(a));
    const double cEA = std::cos(EA);
    const double sEA = std::sin(EA);
    const double xper = a * (cEA - e);
    const double yper = b * sEA;
    const double xdotper = -((a * n) * sEA) / (1 - e * cEA);
    const double ydotper = ((b * n) * cEA) / (1 - e * cEA);

    const double cog = std::cos(omg), sog = std::sin(omg);
    const double cop = std::cos(omp), sop = std::sin(omp);
    const double ci = std::cos(i), si = std::sin(i);
    const double R11 = cog * cop - (sog * sop) * ci;
    const double R12 = -(cog * sop) - (sog * cop) * ci;
    const double R13 = sog * si;
    const double R21 = sog * cop + (cog * sop) * ci;
    const double R22 = -(sog * sop) + (cog * cop) * ci;
    const double R23 = -(cog * si);
    const double R31 = sop * si;
    const double R32 = cop * si;
    const double R33 = ci;
    // r = R*[xper;yper;0] with the zero third column kept (signed zeros).
    r = {R11 * xper + (R12 * yper + R13 * 0.0), R21 * xper + (R22 * yper + R23 * 0.0),
         R31 * xper + (R32 * yper + R33 * 0.0)};
    v = {R11 * xdotper + (R12 * ydotper + R13 * 0.0),
         R21 * xdotper + (R22 * ydotper + R23 * 0.0),
         R31 * xdotper + (R32 * ydotper + R33 * 0.0)};
}

// ---- Analytic planetary ephemerides (lines 910-1091) ----

// pleph_an(mjd2000, planet): state r (km), v (km/s) of planet 1..9 at epoch
// mjd2000 (MJD2000, days).
// Classical elements in the mean ecliptic of date come from polynomials in
// T = Julian centuries since 1900; then M -> E (Kepler/Newton) and
// conversion() give the J2000 state. Throws std::invalid_argument for a
// planet index outside 1..9.
// All nine planets are ported; this suite's sequences only use
// Mercury (1), Venus (2), Earth (3), Jupiter (5) and Saturn (6).
void pleph_an(double mjd2000, int planet, Vec3& r, Vec3& v) {
    // Reference line 953 defines this local mu but never uses it (planet
    // states come from conversion()) [PRESERVE; second of the three solar
    // constants, kept unused in this scope].
    [[maybe_unused]] constexpr double kMuSunPlephAnUnused = 1.327124400180000e+11;
    constexpr double RAD = kPi / 180.0;
    constexpr double KM = 1.495978706910000e+8;

    double T = (mjd2000 + 36525.00) / 36525.00; // Julian centuries since 1900
    double TT = T * T;
    double TTT = T * TT;

    std::array<double, 6> E{};
    double XM;
    switch (planet) {
    case 1: // MERCURY
        E[0] = 0.38709860;
        E[1] = 0.205614210 + 0.000020460 * T - 0.000000030 * TT;
        E[2] = 7.002880555555555560 + 1.86083333333333333e-3 * T - 1.83333333333333333e-5 * TT;
        E[3] = 4.71459444444444444e+1 + 1.185208333333333330 * T + 1.73888888888888889e-4 * TT;
        E[4] = 2.87537527777777778e+1 + 3.70280555555555556e-1 * T + 1.20833333333333333e-4 * TT;
        XM = 1.49472515288888889e+5 + 6.38888888888888889e-6 * T;
        E[5] = 1.02279380555555556e2 + XM * T;
        break;
    case 2: // VENUS
        E[0] = 0.72333160;
        E[1] = 0.006820690 - 0.000047740 * T + 0.0000000910 * TT;
        E[2] = 3.393630555555555560 + 1.00583333333333333e-3 * T - 9.72222222222222222e-7 * TT;
        E[3] = 7.57796472222222222e+1 + 8.9985e-1 * T + 4.1e-4 * TT;
        E[4] = 5.43841861111111111e+1 + 5.08186111111111111e-1 * T - 1.38638888888888889e-3 * TT;
        XM = 5.8517803875e+4 + 1.28605555555555556e-3 * T;
        E[5] = 2.12603219444444444e2 + XM * T;
        break;
    case 3: // EARTH
        E[0] = 1.000000230;
        E[1] = 0.016751040 - 0.000041800 * T - 0.0000001260 * TT;
        E[2] = 0.00;
        E[3] = 0.00;
        E[4] = 1.01220833333333333e+2 + 1.7191750 * T + 4.52777777777777778e-4 * TT + 3.33333333333333333e-6 * TTT;
        XM = 3.599904975e+4 - 1.50277777777777778e-4 * T - 3.33333333333333333e-6 * TT;
        E[5] = 3.58475844444444444e2 + XM * T;
        break;
    case 4: // MARS
        E[0] = 1.5236883990;
        E[1] = 0.093312900 + 0.0000920640 * T - 0.0000000770 * TT;
        E[2] = 1.850333333333333330 - 6.75e-4 * T + 1.26111111111111111e-5 * TT;
        E[3] = 4.87864416666666667e+1 + 7.70991666666666667e-1 * T - 1.38888888888888889e-6 * TT - 5.33333333333333333e-6 * TTT;
        E[4] = 2.85431761111111111e+2 + 1.069766666666666670 * T + 1.3125e-4 * TT + 4.13888888888888889e-6 * TTT;
        XM = 1.91398585e+4 + 1.80805555555555556e-4 * T + 1.19444444444444444e-6 * TT;
        E[5] = 3.19529425e2 + XM * T;
        break;
    case 5: // JUPITER
        E[0] = 5.2025610;
        E[1] = 0.048334750 + 0.000164180 * T - 0.00000046760 * TT - 0.00000000170 * TTT;
        E[2] = 1.308736111111111110 - 5.69611111111111111e-3 * T + 3.88888888888888889e-6 * TT;
        E[3] = 9.94433861111111111e+1 + 1.010530 * T + 3.52222222222222222e-4 * TT - 8.51111111111111111e-6 * TTT;
        E[4] = 2.73277541666666667e+2 + 5.99431666666666667e-1 * T + 7.0405e-4 * TT + 5.07777777777777778e-6 * TTT;
        XM = 3.03469202388888889e+3 - 7.21588888888888889e-4 * T + 1.78444444444444444e-6 * TT;
        E[5] = 2.25328327777777778e2 + XM * T;
        break;
    case 6: // SATURN
        E[0] = 9.5547470;
        E[1] = 0.055892320 - 0.00034550 * T - 0.0000007280 * TT + 0.000000000740 * TTT;
        E[2] = 2.492519444444444440 - 3.91888888888888889e-3 * T - 1.54888888888888889e-5 * TT + 4.44444444444444444e-8 * TTT;
        E[3] = 1.12790388888888889e+2 + 8.73195138888888889e-1 * T - 1.52180555555555556e-4 * TT - 5.30555555555555556e-6 * TTT;
        E[4] = 3.38307772222222222e+2 + 1.085220694444444440 * T + 9.78541666666666667e-4 * TT + 9.91666666666666667e-6 * TTT;
        XM = 1.22155146777777778e+3 - 5.01819444444444444e-4 * T - 5.19444444444444444e-6 * TT;
        E[5] = 1.75466216666666667e2 + XM * T;
        break;
    case 7: // URANUS
        E[0] = 19.218140;
        E[1] = 0.04634440 - 0.000026580 * T + 0.0000000770 * TT;
        E[2] = 7.72463888888888889e-1 + 6.25277777777777778e-4 * T + 3.95e-5 * TT;
        E[3] = 7.34770972222222222e+1 + 4.98667777777777778e-1 * T + 1.31166666666666667e-3 * TT;
        E[4] = 9.80715527777777778e+1 + 9.85765e-1 * T - 1.07447222222222222e-3 * TT - 6.05555555555555556e-7 * TTT;
        XM = 4.28379113055555556e+2 + 7.88444444444444444e-5 * T + 1.11111111111111111e-9 * TT;
        E[5] = 7.26488194444444444e1 + XM * T;
        break;
    case 8: // NEPTUNE
        E[0] = 30.109570;
        E[1] = 0.008997040 + 0.0000063300 * T - 0.0000000020 * TT;
        E[2] = 1.779241666666666670 - 9.54361111111111111e-3 * T - 9.11111111111111111e-6 * TT;
        E[3] = 1.30681358333333333e+2 + 1.0989350 * T + 2.49866666666666667e-4 * TT - 4.71777777777777778e-6 * TTT;
        E[4] = 2.76045966666666667e+2 + 3.25639444444444444e-1 * T + 1.4095e-4 * TT + 4.11333333333333333e-6 * TTT;
        XM = 2.18461339722222222e+2 - 7.03333333333333333e-5 * T;
        E[5] = 3.77306694444444444e1 + XM * T;
        break;
    case 9: { // PLUTO -- fifth-order fit in mjd2000/36525 (reference lines 1060-1074)
        T = mjd2000 / 36525;
        TT = T * T;
        TTT = TT * T;
        const double TTTT = TTT * T;
        const double TTTTT = TTTT * T;
        E[0] = 39.34041961252520 + 4.33305138120726 * T - 22.93749932403733 * TT + 48.76336720791873 * TTT - 45.52494862462379 * TTTT + 15.55134951783384 * TTTTT;
        E[1] = 0.24617365396517 + 0.09198001742190 * T - 0.57262288991447 * TT + 1.39163022881098 * TTT - 1.46948451587683 * TTTT + 0.56164158721620 * TTTTT;
        E[2] = 17.16690003784702 - 0.49770248790479 * T + 2.73751901890829 * TT - 6.26973695197547 * TTT + 6.36276927397430 * TTTT - 2.37006911673031 * TTTTT;
        E[3] = 110.222019291707 + 1.551579150048 * T - 9.701771291171 * TT + 25.730756810615 * TTT - 30.140401383522 * TTTT + 12.796598193159 * TTTTT;
        E[4] = 113.368933916592 + 9.436835192183 * T - 35.762300003726 * TT + 48.966118351549 * TTT - 19.384576636609 * TTTT - 3.362714022614 * TTTTT;
        E[5] = 15.17008631634665 + 137.023166578486 * T + 28.362805871736 * TT - 29.677368415909 * TTT - 3.585159909117 * TTTT + 13.406844652829 * TTTTT;
        break;
    }
    default:
        throw std::invalid_argument("pleph_an: planet index must be 1..9, got " +
                                    std::to_string(planet) + ".");
    }

    // AU -> km, deg -> rad; then wrap the mean anomaly into [0, 2*pi).
    E[0] = E[0] * KM;
    for (int I = 2; I <= 5; ++I) {
        E[I] = E[I] * RAD;
    }
    E[5] = matlab_mod(E[5], 2 * kPi);

    // Mean anomaly -> eccentric anomaly via Kepler's equation.
    E[5] = M2E(E[5], E[1]);

    conversion(E, r, v);
}

// ---- Kepler propagation (lines 479-520) ----

// propagateKEP: moves the state (r0in, v0in) forward by t seconds along a
// Kepler orbit with gravitational constant mu; result in (r, v).
void propagateKEP(const Vec3& r0in, const Vec3& v0in, double t, double mu, Vec3& r, Vec3& v) {
    // [PRESERVE] DD rotation: if the orbit normal is within 1e-3 of +-z
    // (the abs also covers retrograde ih = [0,0,-1]), rotate the state by
    // DD = [1 0 0; 0 0 1; 0 -1 0] so par2IC's Euler angles stay defined,
    // and rotate back with DD' at the end.
    const Vec3 h = vett(r0in, v0in);
    const double nh = norm3(h);
    const double ih3 = h[2] / nh;
    const bool rotated = std::fabs(std::fabs(ih3) - 1.0) < 1e-3;

    Vec3 r0 = r0in;
    Vec3 v0 = v0in;
    if (rotated) {
        r0 = {r0in[0], r0in[2], -r0in[1]}; // DD*r0
        v0 = {v0in[0], v0in[2], -v0in[1]}; // DD*v0
    }

    std::array<double, 6> E = IC2par(r0, v0, mu);
    const double M0 = E2M(E[5], E[1]);
    double M;
    if (E[1] < 1) {
        M = M0 + std::sqrt(mu / matlab_cube(E[0])) * t;
    } else {
        M = M0 + std::sqrt(-mu / matlab_cube(E[0])) * t;
    }
    E[5] = M2E(M, E[1]);
    par2IC(E, mu, r, v);

    if (rotated) {
        r = {r[0], -r[2], r[1]}; // DD'*r
        v = {v[0], -v[2], v[1]}; // DD'*v
    }
}

// ---- Izzo Lambert solver, N = 0 branch only (lines 652-889) ----

// tofabn (lines 881-889) for N = 0 revolutions. The reference adds N*2*pi
// inside the ellipse expression; with N == 0 that term is an exact +0, so
// it is dropped here.
double tofabn(double sigma, double alfa, double beta) {
    if (sigma > 0) {
        return sigma * std::sqrt(sigma) * ((alfa - std::sin(alfa)) - (beta - std::sin(beta)));
    }
    return -sigma * std::sqrt(-sigma) * ((std::sinh(alfa) - alfa) - (std::sinh(beta) - beta));
}

// x2tof (lines 860-877), N = 0: non-dimensional time of flight for the
// Lambert variable x.
double x2tof(double x, double s, double c, int lw) {
    const double am = s / 2;
    const double a = am / (1 - x * x);
    double alfa, beta;
    if (x < 1) { // ellipse
        beta = 2 * std::asin(std::sqrt((s - c) / 2 / a));
        if (lw) {
            beta = -beta;
        }
        alfa = 2 * std::acos(x);
    } else { // hyperbola
        alfa = 2 * std::acosh(x);
        beta = 2 * std::asinh(std::sqrt((s - c) / (-2 * a)));
        if (lw) {
            beta = -beta;
        }
    }
    return tofabn(a, alfa, beta);
}

// lambertI (lines 652-855) with nargin == 5, i.e. N = 0: single-revolution
// branch only (mga_dsm never reaches the multi-revolution branch). Gives
// the velocities v1 at r1in and v2 at r2in for transfer time t (seconds);
// lw = 1 takes the long way (transfer angle 2*pi - theta). Only v1 and v2
// are returned; the caller uses no other output of the reference.
void lambertI(const Vec3& r1in, const Vec3& r2in, double t, double mu, int lw, Vec3& v1, Vec3& v2) {
    if (t <= 0) {
        // Reference lines 711-716: warning + NaN velocities. Unreachable
        // within the suite bounds, but kept.
        v1 = {std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(),
              std::numeric_limits<double>::quiet_NaN()};
        v2 = v1;
        return;
    }

    const double tol = 1e-11;

    // Non-dimensional units.
    const double R = norm3(r1in);
    const double V = std::sqrt(mu / R);
    const double T = R / V;
    const Vec3 r1 = {r1in[0] / R, r1in[1] / R, r1in[2] / R};
    const Vec3 r2 = {r2in[0] / R, r2in[1] / R, r2in[2] / R};
    const double tn = t / T;

    const double r2mod = norm3(r2);
    double theta = std::acos(dot3(r1, r2) / r2mod);
    if (lw) {
        theta = 2 * kPi - theta;
    }
    const double c = std::sqrt(1 + r2mod * r2mod - (2 * r2mod) * std::cos(theta));
    const double s = (1 + r2mod + c) / 2;
    const double am = s / 2;
    const double lambda = std::sqrt(r2mod) * std::cos(theta / 2) / s;

    // N == 0: log-secant iteration (like regula falsi) on
    // y = log(tof(x)) - log(tn), with x in log(1+inn) coordinates.
    const double inn1 = -.5233;
    const double inn2 = .5233;
    double x1 = std::log(1 + inn1);
    double x2 = std::log(1 + inn2);
    double y1 = std::log(x2tof(inn1, s, c, lw)) - std::log(tn);
    double y2 = std::log(x2tof(inn2, s, c, lw)) - std::log(tn);

    // [PRESERVE] No iteration cap: "while err>tol && y1~=y2" only (see the
    // file header for the theoretical hang). xnew starts as NaN only so the
    // unreachable y1 == y2 entry case stays defined.
    double err = 1.0;
    double xnew = std::numeric_limits<double>::quiet_NaN();
    while (err > tol && y1 != y2) {
        xnew = (x1 * y2 - y1 * x2) / (y2 - y1);
        const double ynew = std::log(x2tof(std::exp(xnew) - 1, s, c, lw)) - std::log(tn);
        x1 = x2;
        y1 = y2;
        x2 = xnew;
        y2 = ynew;
        err = std::fabs(x1 - xnew);
    }
    const double x = std::exp(xnew) - 1;

    const double a = am / (1 - x * x);
    double psi, eta, eta2;
    if (x < 1) { // ellipse
        double beta = 2 * std::asin(std::sqrt((s - c) / 2 / a));
        if (lw) {
            beta = -beta;
        }
        const double alfa = 2 * std::acos(x);
        psi = (alfa - beta) / 2;
        const double sp = std::sin(psi);
        eta2 = (2 * a) * (sp * sp) / s;
        eta = std::sqrt(eta2);
    } else { // hyperbola
        double beta = 2 * std::asinh(std::sqrt((c - s) / 2 / a));
        if (lw) {
            beta = -beta;
        }
        const double alfa = 2 * std::acosh(x);
        psi = (alfa - beta) / 2;
        const double sh = std::sinh(psi);
        eta2 = (-2 * a) * (sh * sh) / s;
        eta = std::sqrt(eta2);
    }
    const double st2 = std::sin(theta / 2);
    const double p = r2mod / am / eta2 * (st2 * st2);
    const double sigma1 = 1 / eta / std::sqrt(am) * ((2 * lambda) * am - (lambda + x * eta));
    Vec3 ih = vers(vett(r1, r2));
    if (lw) {
        ih = {-ih[0], -ih[1], -ih[2]};
    }

    const double vr1 = sigma1;
    const double vt1 = std::sqrt(p);
    const Vec3 ihxr1 = vett(ih, r1);
    v1 = {vr1 * r1[0] + vt1 * ihxr1[0], vr1 * r1[1] + vt1 * ihxr1[1],
          vr1 * r1[2] + vt1 * ihxr1[2]};

    const double vt2 = vt1 / r2mod;
    const double vr2 = -vr1 + (vt1 - vt2) / std::tan(theta / 2);
    // v2 = vr2*r2/r2mod + vt2*vett(ih, r2/r2mod)': the first term is
    // (vr2*r2)/r2mod, while the cross product takes r2/r2mod. Both are kept
    // so the rounding matches the reference exactly.
    const Vec3 r2u = {r2[0] / r2mod, r2[1] / r2mod, r2[2] / r2mod};
    const Vec3 ihxr2u = vett(ih, r2u);
    v2 = {(vr2 * r2[0]) / r2mod + vt2 * ihxr2u[0], (vr2 * r2[1]) / r2mod + vt2 * ihxr2u[1],
          (vr2 * r2[2]) / r2mod + vt2 * ihxr2u[2]};

    // Back to dimensional units. The reference's a and p outputs are not
    // returned, since the caller never uses them.
    v1 = {v1[0] * V, v1[1] * V, v1[2] * V};
    v2 = {v2[0] * V, v2[1] * V, v2[2] * V};
}

// ---- mga_dsm main routine (lines 82-377), P21/P22 objectives only ----

enum class ObjectiveType {
    orbit_insertion, // P21: J = DVtot
    total_dv_rndv    // P22: J = DVtot + VINF
};

struct MgaDsmData {
    std::vector<int> sequence; // planet ids 1..6 (mga_dsm's mu/radius tables)
    ObjectiveType type = ObjectiveType::orbit_insertion;
    double rp_target = 0.0; // 'orbit insertion' only
    double e_target = 0.0;  // 'orbit insertion' only
};

// mga_dsm: objective J (km/s) of an MGA-DSM trajectory. t is the decision
// vector, length 4*N - 2 for a sequence of N planets.
double mga_dsm(std::span<const double> t, const MgaDsmData& prob) {
    // Planet gravitational constants (lines 113-118, km^3/s^2) and radii
    // (lines 126-131, km) for planets 1..6 (Mercury to Saturn).
    static constexpr double kMuPlanet[6] = {22321.0,  324860.0, 398601.19,
                                            42828.3,  126.7e6,  37.93951970883e6};
    static constexpr double kRPL[6] = {2440.0, 6052.0, 6378.0, 3397.0, 71492.0, 60330.0};
    // Main solar gravitational constant (line 120), used by propagateKEP and
    // lambertI for every spacecraft arc [PRESERVE; first of the three muSUN
    // constants].
    constexpr double kMuSunMain = 1.32712428e+11;

    const std::size_t N = prob.sequence.size();

    // Unpack the decision vector (lines 137-173, non-'time to AUs' branch).
    // The end-of-line comments give the 1-based MATLAB form; with 0-based i
    // the C++ index expressions come out the same.
    const double tdep = t[0]; // departure epoch (MJD2000)
    const double VINF = t[1]; // hyperbolic escape speed (km/s)
    const double udir = t[2];
    const double vdir = t[3];

    std::vector<double> tof(N - 1), alpha(N - 1);
    for (std::size_t i = 0; i < N - 1; ++i) {
        tof[i] = t[i + 4];       // MATLAB tof(i) = t(i+4)
        alpha[i] = t[N + i + 3]; // MATLAB alpha(i) = t(N+i+3)
    }
    std::vector<double> rp_non_dim(N - 2), gamma(N - 2);
    for (std::size_t i = 0; i < N - 2; ++i) {
        rp_non_dim[i] = t[i + 2 * N + 2]; // MATLAB rp_non_dim(i) = t(i+2*N+2)
        gamma[i] = t[3 * N + i];          // MATLAB gamma(i) = t(3*N+i)
    }

    // Planet positions/velocities at the cumulative epochs (lines 179-208).
    // seq = abs(sequence): a negative entry would mark a retrograde orbit.
    // Neither problem has one; the abs is kept to match the reference.
    std::vector<Vec3> r(N), v(N);
    std::vector<double> muvec(N);
    {
        double T = tdep;
        for (std::size_t i = 0; i < N; ++i) {
            const int seq_i = std::abs(prob.sequence[i]);
            pleph_an(T, seq_i, r[i], v[i]);
            muvec[i] = kMuPlanet[seq_i - 1];
            if (i < N - 1) {
                T = T + tof[i]; // dT(N) = 0 in the reference
            }
        }
    }

    // Dimensional flyby radii (lines 217-222): rp(i) refers to planet i+1.
    std::vector<double> rp(N - 2);
    for (std::size_t i = 0; i < N - 2; ++i) {
        rp[i] = rp_non_dim[i] * kRPL[std::abs(prob.sequence[i + 1]) - 1];
    }

    // ---- First block: P1 -> P2 (lines 230-265) ----

    const Vec3 vtemp = vett(r[0], v[0]); // reference uses cross() here; same formula
    const double nv0 = norm3(v[0]);
    const Vec3 iP1 = {v[0][0] / nv0, v[0][1] / nv0, v[0][2] / nv0};
    const double nvt = norm3(vtemp);
    const Vec3 zP1 = {vtemp[0] / nvt, vtemp[1] / nvt, vtemp[2] / nvt};
    const Vec3 jP1 = vett(zP1, iP1);

    const double theta = 2 * kPi * udir;                  // see Picking a Point on a Sphere
    const double phi = std::acos(2 * vdir - 1) - kPi / 2; // -pi/2 < phi < pi/2
    const double ctcp = std::cos(theta) * std::cos(phi);
    const double stcp = std::sin(theta) * std::cos(phi);
    const double sphi = std::sin(phi);
    Vec3 vinf;
    for (int j = 0; j < 3; ++j) {
        vinf[j] = VINF * ((ctcp * iP1[j] + stcp * jP1[j]) + sphi * zP1[j]);
    }

    std::vector<Vec3> v_sc_pl_in(N), v_sc_pl_out(N);
    v_sc_pl_in[0] = v[0]; // never used later (as in the reference)
    for (int j = 0; j < 3; ++j) {
        v_sc_pl_out[0][j] = v[0][j] + vinf[j];
    }

    std::vector<double> DV(N, 0.0);
    Vec3 rd, v_sc_dsm_in, v_sc_dsm_out;
    {
        const double tDSM = alpha[0] * tof[0]; // days from P1 to DSM1
        propagateKEP(r[0], v_sc_pl_out[0], tDSM * 24 * 60 * 60, kMuSunMain, rd, v_sc_dsm_in);

        // lw from the z-component of cross(rd, r2), as in MATLAB:
        // sign(z) == 1 -> lw = 0; sign(z) in {0,-1} -> lw = 1.
        const Vec3 lwv = vett(rd, r[1]);
        const int lw = (lwv[2] > 0) ? 0 : 1;
        lambertI(rd, r[1], tof[0] * (1 - alpha[0]) * 24 * 60 * 60, kMuSunMain, lw, v_sc_dsm_out,
                 v_sc_pl_in[1]);

        const Vec3 d = {v_sc_dsm_out[0] - v_sc_dsm_in[0], v_sc_dsm_out[1] - v_sc_dsm_in[1],
                        v_sc_dsm_out[2] - v_sc_dsm_in[2]};
        DV[0] = norm3(d);
    }

    // ---- Intermediate blocks (lines 271-317) ----

    for (std::size_t i = 0; i < N - 2; ++i) {
        // Unpowered swingby at planet i+2 (1-based; 0-based index i+1).
        const Vec3 v_rel_in = {v_sc_pl_in[i + 1][0] - v[i + 1][0],
                               v_sc_pl_in[i + 1][1] - v[i + 1][1],
                               v_sc_pl_in[i + 1][2] - v[i + 1][2]};

        // MATLAB evaluates e = 1 + rp(i)/muvec(i+1)*v_rel_in'*v_rel_in as
        // ((rp/mu)*v_rel_in') * v_rel_in: the scalar scales each component
        // BEFORE the row-times-column product, which then sums right to
        // left (see dot3).
        const double rpmu = rp[i] / muvec[i + 1];
        const Vec3 w = {rpmu * v_rel_in[0], rpmu * v_rel_in[1], rpmu * v_rel_in[2]};
        const double e = 1 + dot3(w, v_rel_in);

        const double beta_rot = 2 * std::asin(1 / e); // turn angle of v_rel

        const double nrel = norm3(v_rel_in);
        const Vec3 ix = {v_rel_in[0] / nrel, v_rel_in[1] / nrel, v_rel_in[2] / nrel};
        const double nvp = norm3(v[i + 1]);
        const Vec3 vpu = {v[i + 1][0] / nvp, v[i + 1][1] / nvp, v[i + 1][2] / nvp};
        Vec3 iy = vett(ix, vpu);
        {
            const double niy = norm3(iy);
            iy = {iy[0] / niy, iy[1] / niy, iy[2] / niy};
        }
        const Vec3 iz = vett(ix, iy);

        const double cb = std::cos(beta_rot);
        const double cgsb = std::cos(gamma[i]) * std::sin(beta_rot);
        const double sgsb = std::sin(gamma[i]) * std::sin(beta_rot);
        Vec3 v_rel_out;
        for (int j = 0; j < 3; ++j) {
            const double iVout_j = (cb * ix[j] + cgsb * iy[j]) + sgsb * iz[j];
            v_rel_out[j] = nrel * iVout_j;
        }
        for (int j = 0; j < 3; ++j) {
            v_sc_pl_out[i + 1][j] = v[i + 1][j] + v_rel_out[j];
        }

        const double tDSM = alpha[i + 1] * tof[i + 1]; // days from P(i+1) to DSM(i+1)
        propagateKEP(r[i + 1], v_sc_pl_out[i + 1], tDSM * 24 * 60 * 60, kMuSunMain, rd,
                     v_sc_dsm_in);

        const Vec3 lwv = vett(rd, r[i + 2]);
        const int lw = (lwv[2] > 0) ? 0 : 1;
        lambertI(rd, r[i + 2], tof[i + 1] * (1 - alpha[i + 1]) * 24 * 60 * 60, kMuSunMain, lw,
                 v_sc_dsm_out, v_sc_pl_in[i + 2]);

        const Vec3 d = {v_sc_dsm_out[0] - v_sc_dsm_in[0], v_sc_dsm_out[1] - v_sc_dsm_in[1],
                        v_sc_dsm_out[2] - v_sc_dsm_in[2]};
        DV[i + 1] = norm3(d);
    }

    // ---- Final block (lines 320-346) ----

    const Vec3 drel = {v[N - 1][0] - v_sc_pl_in[N - 1][0], v[N - 1][1] - v_sc_pl_in[N - 1][1],
                       v[N - 1][2] - v_sc_pl_in[N - 1][2]};
    const double DVrel = norm3(drel); // relative velocity at the target planet

    double DVarr;
    if (prob.type == ObjectiveType::orbit_insertion) {
        const double DVper = std::sqrt(DVrel * DVrel + 2 * muvec[N - 1] / prob.rp_target); // hyperbola
        const double DVper2 = std::sqrt(2 * muvec[N - 1] / prob.rp_target -
                                        muvec[N - 1] / prob.rp_target * (1 - prob.e_target)); // ellipse
        DVarr = std::fabs(DVper - DVper2);
    } else { // 'total DV rndv'
        DVarr = DVrel;
    }
    DV[N - 1] = DVarr;

    // DVtot = sum(DV) (lines 354-361, non-gtoc1 branch), summed in order.
    double DVtot = 0.0;
    for (std::size_t i = 0; i < N; ++i) {
        DVtot = DVtot + DV[i];
    }

    // Objective (lines 371-377).
    if (prob.type == ObjectiveType::total_dv_rndv) {
        return DVtot + VINF;
    }
    return DVtot; // 'orbit insertion'
}

// ---- Problem definition files ----

// Parsed content of <data_root>/{messengerfull,cassini2}_problem.txt
// (committed text files made during the validated CEC2011 port; format:
// '#' comment lines and "key: value" lines).
struct ParsedProblemFile {
    std::vector<int> sequence;
    std::string objective_type;
    bool has_rp = false;
    bool has_e = false;
    double rp = 0.0;
    double e = 0.0;
};

// Returns s without leading and trailing spaces and tabs.
std::string trim_copy(const std::string& s) {
    const std::string ws = " \t";
    const std::size_t b = s.find_first_not_of(ws);
    if (b == std::string::npos) {
        return {};
    }
    const std::size_t e = s.find_last_not_of(ws);
    return s.substr(b, e - b + 1);
}

// Parses the whole token as a double; otherwise throws std::runtime_error
// naming the file.
double parse_double_token(const std::string& token, const std::filesystem::path& path) {
    try {
        std::size_t consumed = 0;
        const double value = std::stod(token, &consumed);
        if (consumed != token.size()) {
            throw std::invalid_argument(token);
        }
        return value;
    } catch (const std::exception&) {
        throw std::runtime_error("Non-numeric value '" + token +
                                 "' in problem definition file: " + path.string());
    }
}

// Reads a problem file. Blank and '#' lines are skipped. Keys: sequence
// (planet ids separated by spaces), objective_type, objective_rp,
// objective_e. Throws std::runtime_error if the file is missing or cannot
// be opened, or on a line without ':', a bad number or an unknown key.
ParsedProblemFile parse_problem_file(const std::filesystem::path& path) {
    require_file(path);
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("Cannot open data file: " + path.string());
    }
    ParsedProblemFile out;
    std::string line;
    while (std::getline(in, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
            line.pop_back();
        }
        const std::string stripped = trim_copy(line);
        if (stripped.empty() || stripped[0] == '#') {
            continue;
        }
        const std::size_t colon = stripped.find(':');
        if (colon == std::string::npos) {
            throw std::runtime_error("Malformed line (no ':') in problem definition file " +
                                     path.string() + ": '" + stripped + "'");
        }
        const std::string key = trim_copy(stripped.substr(0, colon));
        const std::string value = trim_copy(stripped.substr(colon + 1));
        if (key == "sequence") {
            std::istringstream ss(value);
            int planet = 0;
            while (ss >> planet) {
                out.sequence.push_back(planet);
            }
            if (!ss.eof()) {
                throw std::runtime_error("Non-integer planet id in sequence of " + path.string());
            }
        } else if (key == "objective_type") {
            out.objective_type = value;
        } else if (key == "objective_rp") {
            out.rp = parse_double_token(value, path);
            out.has_rp = true;
        } else if (key == "objective_e") {
            out.e = parse_double_token(value, path);
            out.has_e = true;
        } else {
            throw std::runtime_error("Unknown key '" + key +
                                     "' in problem definition file: " + path.string());
        }
    }
    return out;
}

// ---- Benchmark problem wrapper ----

// CEC2011 problem 21 or 22 as a BenchmarkProblem. The constructor sets the
// bounds, then loads and checks the problem file from data_root.
class MgaDsmTrajectoryProblem final : public BenchmarkProblem {
public:
    MgaDsmTrajectoryProblem(int function_id, const std::filesystem::path& data_root)
        : function_id_(function_id) {
        const char* file_name = nullptr;
        std::vector<int> expected_sequence;
        const char* expected_type = nullptr;

        if (function_id == 21) {
            // Messenger (full mission): E V V M M M M, 'orbit insertion'
            // around Mercury with rp = 2640 km, e = 0.704.
            file_name = "messengerfull_problem.txt";
            expected_sequence = {3, 2, 2, 1, 1, 1, 1};
            expected_type = "orbit insertion";
            // Bounds: define_boundaries.m case 21 (same as
            // getlimit_messenger.m; the unused .mat 'bounds' field differs
            // and is ignored).
            lower_ = {1900, 2.5, 0,    0,    100,  100,  100,  100,  100,
                      100,  0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 1.1,  1.1,
                      1.05, 1.05, 1.05, -kPi, -kPi, -kPi, -kPi, -kPi};
            upper_ = {2300, 4.05, 1,    1,    500,  500,  500,  500, 500,
                      600,  0.99, 0.99, 0.99, 0.99, 0.99, 0.99, 6,   6,
                      6,    6,    6,    kPi,  kPi,  kPi,  kPi,  kPi};
        } else if (function_id == 22) {
            // Cassini 2: E V V E J S, 'total DV rndv' at Saturn.
            file_name = "cassini2_problem.txt";
            expected_sequence = {3, 2, 2, 3, 5, 6};
            expected_type = "total DV rndv";
            // Bounds: define_boundaries.m case 22. [PRESERVE] The element 9
            // lower bound is 400 (canonical for GSK), NOT the 800 of
            // getlimit_cassini2.m and the .mat 'bounds' field (the official
            // GTOP value); the GSK results were produced with 400.
            lower_ = {-1000, 3,    0,    0,    100,  100,  30,  400, 400, 0.01, 0.01,
                      0.01,  0.01, 0.01, 1.05, 1.05, 1.15, 1.7, -kPi, -kPi, -kPi, -kPi};
            upper_ = {0,   5,   1,   1,   400, 500, 300, 1600, 2200, 0.9, 0.9,
                      0.9, 0.9, 0.9, 6,   6,   6.5, 291, kPi,  kPi,  kPi, kPi};
        } else {
            throw std::invalid_argument(
                "cec2011 work package C implements only function ids 21 and 22, got " +
                std::to_string(function_id) + ".");
        }

        // Load the problem definition ONCE here. The reference reloads the
        // .mat inside the per-individual evaluation loop (Calc_Fitx_2011.m
        // lines 49/53), which only costs time and changes no result.
        const std::filesystem::path path = data_root / file_name;
        const ParsedProblemFile parsed = parse_problem_file(path);

        // Check the file against the constants from the port plan, so a
        // corrupted or swapped file is caught.
        if (parsed.sequence != expected_sequence) {
            throw std::runtime_error("Unexpected planet sequence in " + path.string());
        }
        if (parsed.objective_type != expected_type) {
            throw std::runtime_error("Unexpected objective_type '" + parsed.objective_type +
                                     "' in " + path.string() + " (expected '" + expected_type +
                                     "').");
        }
        data_.sequence = parsed.sequence;
        if (function_id == 21) {
            if (!parsed.has_rp || !parsed.has_e) {
                throw std::runtime_error("Missing objective_rp/objective_e in " + path.string());
            }
            if (parsed.rp != 2640.0 || parsed.e != 0.704) {
                throw std::runtime_error("Unexpected objective_rp/objective_e values in " +
                                         path.string());
            }
            data_.type = ObjectiveType::orbit_insertion;
            data_.rp_target = parsed.rp;
            data_.e_target = parsed.e;
        } else {
            if (parsed.has_rp || parsed.has_e) {
                throw std::runtime_error("Unexpected objective_rp/objective_e for 'total DV "
                                         "rndv' problem in " + path.string());
            }
            data_.type = ObjectiveType::total_dv_rndv;
        }

        // D = 4*N - 2 for the non-'time to AUs' decision vector; it must
        // match define_boundaries.m (26 and 22).
        dimension_ = static_cast<int>(4 * data_.sequence.size() - 2);
        if (dimension_ != static_cast<int>(lower_.size()) ||
            dimension_ != static_cast<int>(upper_.size())) {
            throw std::runtime_error("Internal bounds/dimension mismatch for cec2011 function " +
                                     std::to_string(function_id) + ".");
        }
    }

    std::string suite_name() const override {
        return "cec2011";
    }

    int function_id() const override {
        return function_id_;
    }

    int dimension() const override {
        return dimension_;
    }

    Bounds bounds() const override {
        return Bounds(lower_, upper_);
    }

    // No published optimum for the CEC2011 real-world problems.
    Real optimum() const override {
        return std::numeric_limits<Real>::quiet_NaN();
    }

    Real evaluate(std::span<const Real> x) const override {
        if (x.size() != static_cast<std::size_t>(dimension_)) {
            throw std::invalid_argument("cec2011 f" + std::to_string(function_id_) +
                                        " expects dimension " + std::to_string(dimension_) +
                                        ", got " + std::to_string(x.size()) + ".");
        }
        const double J = mga_dsm(x, data_);
        return apply_reference_nan_rule(J);
    }

private:
    int function_id_;
    int dimension_ = 0;
    Vector lower_;
    Vector upper_;
    MgaDsmData data_;
};

} // namespace

// Factory for work package C. Throws std::invalid_argument unless
// function_id is 21 or 22.
std::unique_ptr<BenchmarkProblem> make_problem_wpc(int function_id,
                                                   const std::filesystem::path& data_root) {
    if (function_id != 21 && function_id != 22) {
        throw std::invalid_argument(
            "cec2011 work package C implements only function ids 21 and 22, got " +
            std::to_string(function_id) + ".");
    }
    return std::make_unique<MgaDsmTrajectoryProblem>(function_id, data_root);
}

} // namespace gskcec::cec2011::detail
