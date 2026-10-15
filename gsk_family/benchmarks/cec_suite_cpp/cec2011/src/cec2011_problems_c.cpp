// cec2011_problems_c.cpp -- work package C of the CEC2011 real-world suite:
//   problem 21: Messenger (full mission) MGA-DSM trajectory  (D = 26)
//   problem 22: Cassini 2 MGA-DSM trajectory                 (D = 22)
//
// Ported from the read-only MATLAB reference
//   historical source: CEC2011 real-world MATLAB package
//     messengerfull.m / cassini2.m  (one-line wrappers around mga_dsm)
//     mga_dsm.m                     (ESA ACT Space Mechanics Toolbox,
//                                    D. Izzo / C. Bombardelli, rev. 4 2007;
//                                    all line references below are to it)
//     define_boundaries.m cases 21/22 (canonical bounds)
//     Calc_Fitx_2011.m cases 21/22  (dispatch + NaN->0 rule)
// per docs/reference/cec2011_port_plan.md sections "Problem 21/22" and 6.
//
// Only the code paths live for these two problems are transcribed:
//   'orbit insertion' (P21):  J = DVtot, DV(N) = |DVper - DVper2|
//   'total DV rndv'   (P22):  J = DVtot + VINF, DV(N) = DVrel
// Dead branches of mga_dsm.m are deliberately NOT ported: 'gtoc1',
// 'time to AUs', 'rndv', 'total DV orbit insertion', 'deflection demo',
// CUSTOMeph (only reachable for sequence entries >= 10; also the only user
// of "global AU mu"), time2distance, and the mjd20002jed/mjd2jed helpers
// used solely by those branches. The yplot branch (problem.yplot == 0 in
// both .mat structs) is plotting-only and dropped.
//
// Reference quirks preserved on purpose (do NOT "fix"):
//  * THREE distinct solar gravitational constants coexist and are NOT
//    unified (plan section 6): kMuSunMain = 1.32712428e11 (mga_dsm.m line
//    120; feeds propagateKEP and lambertI, i.e. every spacecraft arc),
//    kMuSunPlephAnUnused = 1.327124400180000e11 (line 953; defined inside
//    pleph_an but never consumed -- planet states come from conversion()),
//    and kMuSunConversion = 1.327124280000000e11 (line 1099, local to
//    conversion(); generates the planet position/velocity). The first and
//    third happen to be the same double; they are kept as separate
//    constants in their own scopes for traceability.
//  * propagateKEP "DD" rotation hack (lines 498-506, 519-520): when the
//    orbit normal is within 1e-3 of +-z, state vectors are rotated by
//    DD = [1 0 0; 0 0 1; 0 -1 0] before IC2par and by DD' after par2IC so
//    the Euler angles stay defined for near-ecliptic orbits.
//  * lambertI N==0 secant loop (lines 759-771) has NO iteration cap:
//    "while err>tol && y1~=y2" only. A theoretical hang exists if the
//    log-secant iterates cycle without meeting either exit test; within
//    the suite bounds (transfer time > 0, finite geometry) the iteration
//    converges in a handful of steps. Preserved verbatim.
//  * M2E (lines 1140-1151) applies the ELLIPTIC Kepler-Newton iteration
//    (guess E = M + e*cos(M), tol 1e-10, <= 100 iterations) regardless of
//    eccentricity; propagateKEP calls it even for hyperbolic states whose
//    mean anomaly came from the Gudermannian E2M branch. Wrong physics,
//    deterministic output -- preserved.
//  * IC2par guards only the true-anomaly acos with real(...) (line 565).
//    MATLAB's real(acos(x)) for real |x| > 1 yields 0 (x > 1) or pi
//    (x < -1); that exact projection is replicated. The OTHER acos/asin
//    calls (inclination, node, argument of perigee, Lambert transfer
//    angle, beta) are unguarded in the reference: MATLAB would silently
//    go complex if rounding pushed an argument outside [-1,1], while this
//    port (plain double) would produce NaN. Probe verification against
//    the MATLAB ground truth (cec2011_expected.csv) confirmed no such
//    complex intermediate fires for the reference probes, so no
//    std::complex replication is needed (plan section 4, problems 21/22).
//  * Caller-side lw selection (lines 254-260 etc.): lw = sign of the
//    z-component of cross(rd, r_next); MATLAB maps sign +1 -> lw=0 and
//    sign 0 or -1 -> lw=1 (sign(0)==0 != 1). Transcribed as (z>0)?0:1.
//  * lambertI returns [NaN;NaN;NaN] velocities when the requested transfer
//    time is <= 0 (lines 711-716). Unreachable within the suite bounds
//    (tof >= 30 days, alpha <= 0.99) but preserved.
//  * MATLAB scalar/builtin kernels were reverse-verified BITWISE against
//    MATLAB R2025b on 2e5-sample random sweeps before porting (details at
//    the helper definitions below): mod(a,m) is the exact fmod remainder
//    sign-adjusted into m (NOT the documented a - m*floor(a/m), which is
//    ~1e-13 rad off for the wrapped mean anomalies); x^2 == x*x exactly;
//    x^3 is MATLAB's own pow kernel (std::pow(x,3.0) is the closest
//    reproducible match); the 3-element dot x'*y accumulates
//    right-associatively x1*y1 + (x2*y2 + x3*y3); norm(x) uses an
//    extended-precision sum of squares (reproduced via x87 long double);
//    sum(DV) is plain sequential accumulation. Evaluation order of
//    compound expressions follows MATLAB's left-to-right rules so
//    intermediate rounding matches.
//  * The reference reloads the problem .mat INSIDE the per-individual
//    evaluation loop (Calc_Fitx_2011.m lines 49/53) -- a pure performance
//    bug with no numerical effect. This port loads/validates the problem
//    definition ONCE in the constructor (plan section 3.4).
//  * Bounds come from define_boundaries.m (canonical for the GSK runs),
//    NOT from getlimit_messenger.m / getlimit_cassini2.m / the .mat
//    "bounds" fields. In particular P22 element 9 lower bound is 400
//    (define_boundaries) although getlimit_cassini2.m and the .mat say
//    800 (official GTOP value) -- plan section 3.6 [PRESERVE 400].
//  * The NaN->0 rule of Calc_Fitx_2011.m (lines 57-61) is applied as the
//    final step of evaluate() via detail::apply_reference_nan_rule.
//
// Known no-effect reference oddities, noted but with no code impact:
//  * mga_dsm.m line 247 assigns tDSM(1) before line 271 re-creates tDSM
//    as zeros(N-1,1); the value is consumed (line 250) before the wipe.
//  * In the lambertI N==0 branch, if the two starting ordinates were ever
//    exactly equal (y1 == y2, impossible for the strictly monotonic tof
//    curve), MATLAB would crash on the undefined variable xnew; this port
//    initializes xnew to NaN instead, which would propagate to a NaN cost
//    and then to 0 via the NaN rule. This is the single deliberate
//    divergence, confined to a provably unreachable path.
//
// Problem definitions (planet sequence, objective type/rp/e) are parsed
// from the MATLAB-exported text assets
//   <data_root>/messengerfull_problem.txt and <data_root>/cassini2_problem.txt
// so provenance stays with the exported .mat data; the parsed values are
// validated against the embedded constants from the port plan dossier
// (P21: sequence [3 2 2 1 1 1 1], 'orbit insertion', rp = 2640, e = 0.704;
//  P22: sequence [3 2 2 3 5 6], 'total DV rndv').
//
// Thread safety: evaluate() uses only local state and is const; instances
// are safe to share across threads.

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

constexpr double kPi = std::numbers::pi_v<double>; // == MATLAB pi

using Vec3 = std::array<double, 3>;

/* ------------------------------------------------------------------ */
/* Small vector helpers (mga_dsm.m lines 892-904)                      */
/* ------------------------------------------------------------------ */

// vett (lines 899-904). MATLAB's built-in cross() -- used by the reference
// only at lines 230/234 -- evaluates the identical component formulas.
inline Vec3 vett(const Vec3& r1, const Vec3& r2) {
    return {r1[1] * r2[2] - r1[2] * r2[1],
            r1[2] * r2[0] - r1[0] * r2[2],
            r1[0] * r2[1] - r1[1] * r2[0]};
}

// x'*y for column 3-vectors. MATLAB's small-vector dot kernel accumulates
// RIGHT-associatively: x1*y1 + (x2*y2 + x3*y3). Established empirically:
// the left-to-right form differs from MATLAB R2025b in ~27% of random
// cases (1 ulp), the form below in 0 of 200000 across mixed magnitudes.
inline double dot3(const Vec3& a, const Vec3& b) {
    return a[0] * b[0] + (a[1] * b[1] + a[2] * b[2]);
}

// norm(x) of a real 3-vector. MATLAB does NOT evaluate this as the plain
// double sqrt(x'*x): bitwise comparison against MATLAB R2025b shows the
// naive form off by 1 ulp in ~19% of cases, while an extended-precision
// (x87 80-bit) sum of squares + sqrt reproduces MATLAB's norm() exactly
// (0 of 200000 mismatches across position/velocity/unit magnitudes).
// NOTE: relies on long double being x87 extended (true for the MinGW
// toolchains this project builds with); under a compiler where
// long double == double this degrades to the naive form, costing only
// ~1e-13 relative agreement on the deep P21 swingby chain.
inline double norm3(const Vec3& a) {
    const long double x = a[0];
    const long double y = a[1];
    const long double z = a[2];
    return static_cast<double>(sqrtl(x * x + y * y + z * z));
}

// MATLAB scalar x^3 (mga_dsm uses ^3 only inside sqrt(mu/a^3) terms).
// MATLAB's power kernel is NOT (x*x)*x (1-ulp difference in ~27% of
// cases); std::pow(x, 3.0) is the closest reproducible form (UCRT pow is
// correctly rounded within ~5e-4 of cases, matching MATLAB in ~90%; the
// residual is MATLAB's own ~1 ulp pow error and is not reproducible by
// any closed-form double expression).
inline double matlab_cube(double x) {
    return std::pow(x, 3.0);
}

// vers (lines 892-894): V/sqrt(V'*V) -- the reference spells the norm out
// in plain double here (unlike its norm() calls), so this deliberately
// uses the double-precision dot kernel, not norm3().
inline Vec3 vers(const Vec3& v) {
    const double n = std::sqrt(dot3(v, v));
    return {v[0] / n, v[1] / n, v[2] / n};
}

// MATLAB mod(a,m) for finite doubles and m > 0. MATLAB documents
// b = a - m.*floor(a./m), but for scalar doubles it actually returns the
// EXACT remainder (std::fmod semantics) adjusted into the sign of m;
// the naive floor formula differs by the rounding of m*floor(a/m), which
// for the ~1.5e5-degree Mercury/Venus mean anomalies wrapped here is a
// ~1e-13 rad offset -- verified against MATLAB R2025b: only the
// fmod-based form reproduces mod(E(6), 2*pi) bit-exactly.
inline double matlab_mod(double a, double m) {
    double r = std::fmod(a, m);
    if (r != 0.0 && (r < 0.0) != (m < 0.0)) {
        r = r + m;
    }
    return r;
}

/* ------------------------------------------------------------------ */
/* Anomaly conversions                                                 */
/* ------------------------------------------------------------------ */

// M2E (lines 1140-1151): Newton iteration on the ELLIPTIC Kepler equation,
// initial guess E = M + e*cos(M), tol 1e-10, at most 100 iterations.
// [PRESERVE] The reference applies this unconditionally, also when e > 1
// (where M is the Gudermannian mean anomaly from E2M) -- wrong physics,
// deterministic arithmetic; replicated as-is.
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

// E2M (lines 1155-1170): eccentric anomaly -> mean anomaly; for e > 1 the
// input is the Gudermannian and the output is the hyperbolic N.
double E2M(double E, double e) {
    if (e < 1) { // Ellipse, E is the eccentric anomaly
        return E - e * std::sin(E);
    }
    // Hyperbola, E is the Gudermannian
    return e * std::tan(E) - std::log(std::tan(E / 2 + kPi / 4));
}

// ni2E (lines 574-579): true anomaly -> eccentric anomaly (e < 1) or
// Gudermannian (e > 1).
double ni2E(double ni, double e) {
    if (e < 1) {
        return 2 * std::atan(std::sqrt((1 - e) / (1 + e)) * std::tan(ni / 2));
    }
    return 2 * std::atan(std::sqrt((e - 1) / (e + 1)) * std::tan(ni / 2));
}

/* ------------------------------------------------------------------ */
/* Orbital element <-> state conversions                               */
/* ------------------------------------------------------------------ */

// IC2par (lines 524-570). E = (a [negative for hyperbolas], e, i, OM, om,
// eccentric anomaly or Gudermannian). Only the true-anomaly acos carries
// the reference's real(...) guard; the others are unguarded [PRESERVE].
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
    // ni = real(acos(...)): MATLAB's real part of the principal complex
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

// par2IC (lines 584-647): elements -> state, with the hyperbola branch
// using the tan(EA) parametrization and dNdzeta exactly as written.
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
    // r0 = R*[xper;yper;0]: the zero third column is kept so signed-zero
    // components come out exactly as in MATLAB's matrix-vector product.
    r0 = {R11 * xper + (R12 * yper + R13 * 0.0), R21 * xper + (R22 * yper + R23 * 0.0),
          R31 * xper + (R32 * yper + R33 * 0.0)};
    v0 = {R11 * xdotper + (R12 * ydotper + R13 * 0.0),
          R21 * xdotper + (R22 * ydotper + R23 * 0.0),
          R31 * xdotper + (R32 * ydotper + R33 * 0.0)};
}

// conversion (lines 1095-1135): elements -> planet state. Uses its OWN
// local solar gravitational parameter [PRESERVE -- one of the three
// coexisting muSUN constants; see file header].
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

/* ------------------------------------------------------------------ */
/* Analytic planetary ephemerides (lines 910-1091)                     */
/* ------------------------------------------------------------------ */

// pleph_an(mjd2000, planet): classical planetary elements in the mean
// ecliptic of date from polynomials in T = Julian centuries since 1900,
// then M -> E (Kepler/Newton) and conversion() to the J2000 state.
// All nine planets are transcribed; this suite's sequences only use
// Mercury(1), Venus(2), Earth(3), Jupiter(5) and Saturn(6).
void pleph_an(double mjd2000, int planet, Vec3& r, Vec3& v) {
    // Reference line 953 defines this local mu and never consumes it
    // (planet states come from conversion()) [PRESERVE -- second of the
    // three coexisting solar constants; kept in this scope, unused].
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

/* ------------------------------------------------------------------ */
/* Kepler propagation (lines 479-520)                                  */
/* ------------------------------------------------------------------ */

void propagateKEP(const Vec3& r0in, const Vec3& v0in, double t, double mu, Vec3& r, Vec3& v) {
    // [PRESERVE] DD rotation hack: for orbit normals within 1e-3 of +-z
    // (the abs covers retrograde ih = [0,0,-1]) rotate the state by
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

/* ------------------------------------------------------------------ */
/* Izzo Lambert solver, N = 0 branch only (lines 652-889)              */
/* ------------------------------------------------------------------ */

// tofabn (lines 881-889) specialized to N = 0 revolutions (the reference
// adds N*2*pi inside the ellipse expression; with N == 0 that term is an
// exact +0 and is dropped here).
double tofabn(double sigma, double alfa, double beta) {
    if (sigma > 0) {
        return sigma * std::sqrt(sigma) * ((alfa - std::sin(alfa)) - (beta - std::sin(beta)));
    }
    return -sigma * std::sqrt(-sigma) * ((std::sinh(alfa) - alfa) - (std::sinh(beta) - beta));
}

// x2tof (lines 860-877), N = 0.
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

// lambertI (lines 652-855) with nargin == 5 => N = 0, single-revolution
// branch only (the multi-rev branch is never reached by mga_dsm). Only the
// two velocity outputs the caller consumes are produced.
void lambertI(const Vec3& r1in, const Vec3& r2in, double t, double mu, int lw, Vec3& v1, Vec3& v2) {
    if (t <= 0) {
        // Reference lines 711-716: warning + NaN velocities. Unreachable
        // within the suite bounds; preserved.
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

    // N == 0: log-secant ("regula-falsi-like") iteration on
    // y = log(tof(x)) - log(t), x in log(1+inn) coordinates.
    const double inn1 = -.5233;
    const double inn2 = .5233;
    double x1 = std::log(1 + inn1);
    double x2 = std::log(1 + inn2);
    double y1 = std::log(x2tof(inn1, s, c, lw)) - std::log(tn);
    double y2 = std::log(x2tof(inn2, s, c, lw)) - std::log(tn);

    // [PRESERVE] no iteration cap: "while err>tol && y1~=y2" only (see
    // file header for the theoretical hang risk). xnew is initialized to
    // NaN solely to keep the unreachable y1 == y2 entry case defined.
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
    // v2 = vr2*r2/r2mod + vt2*vett(ih, r2/r2mod)': note the first term is
    // (vr2*r2)/r2mod while the cross product takes r2/r2mod -- transcribed
    // with exactly those roundings.
    const Vec3 r2u = {r2[0] / r2mod, r2[1] / r2mod, r2[2] / r2mod};
    const Vec3 ihxr2u = vett(ih, r2u);
    v2 = {(vr2 * r2[0]) / r2mod + vt2 * ihxr2u[0], (vr2 * r2[1]) / r2mod + vt2 * ihxr2u[1],
          (vr2 * r2[2]) / r2mod + vt2 * ihxr2u[2]};

    // Re-dimensionalize (a and p are outputs the caller never consumes).
    v1 = {v1[0] * V, v1[1] * V, v1[2] * V};
    v2 = {v2[0] * V, v2[1] * V, v2[2] * V};
}

/* ------------------------------------------------------------------ */
/* mga_dsm main routine (lines 82-377), live objectives only           */
/* ------------------------------------------------------------------ */

enum class ObjectiveType {
    orbit_insertion, // P21: J = DVtot
    total_dv_rndv    // P22: J = DVtot + VINF
};

struct MgaDsmData {
    std::vector<int> sequence; // planet ids (1..9); all entries < 10 here
    ObjectiveType type = ObjectiveType::orbit_insertion;
    double rp_target = 0.0; // 'orbit insertion' only
    double e_target = 0.0;  // 'orbit insertion' only
};

double mga_dsm(std::span<const double> t, const MgaDsmData& prob) {
    // Planetary gravitational constants (lines 113-118) and radii
    // (lines 126-131), km^3/s^2 and km.
    static constexpr double kMuPlanet[6] = {22321.0,  324860.0, 398601.19,
                                            42828.3,  126.7e6,  37.93951970883e6};
    static constexpr double kRPL[6] = {2440.0, 6052.0, 6378.0, 3397.0, 71492.0, 60330.0};
    // Main-scope solar gravitational constant (line 120): feeds
    // propagateKEP and lambertI for every spacecraft arc [PRESERVE --
    // first of the three coexisting muSUN constants].
    constexpr double kMuSunMain = 1.32712428e+11;

    const std::size_t N = prob.sequence.size();

    // Decision vector unpack (lines 137-173, non-'time to AUs' branch).
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
    // seq = abs(sequence): a negative entry would flag a retrograde orbit;
    // neither problem uses one, the abs is kept for fidelity.
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

    /* ---------------- first block: P1 -> P2 (lines 230-265) -------- */

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
    v_sc_pl_in[0] = v[0]; // never consumed afterwards (as in the reference)
    for (int j = 0; j < 3; ++j) {
        v_sc_pl_out[0][j] = v[0][j] + vinf[j];
    }

    std::vector<double> DV(N, 0.0);
    Vec3 rd, v_sc_dsm_in, v_sc_dsm_out;
    {
        const double tDSM = alpha[0] * tof[0]; // days from P1 to DSM1
        propagateKEP(r[0], v_sc_pl_out[0], tDSM * 24 * 60 * 60, kMuSunMain, rd, v_sc_dsm_in);

        // lw choice from the z-component of cross(rd, r2): MATLAB maps
        // sign(z) == 1 -> lw = 0 and sign(z) in {0,-1} -> lw = 1.
        const Vec3 lwv = vett(rd, r[1]);
        const int lw = (lwv[2] > 0) ? 0 : 1;
        lambertI(rd, r[1], tof[0] * (1 - alpha[0]) * 24 * 60 * 60, kMuSunMain, lw, v_sc_dsm_out,
                 v_sc_pl_in[1]);

        const Vec3 d = {v_sc_dsm_out[0] - v_sc_dsm_in[0], v_sc_dsm_out[1] - v_sc_dsm_in[1],
                        v_sc_dsm_out[2] - v_sc_dsm_in[2]};
        DV[0] = norm3(d);
    }

    /* ---------------- intermediate blocks (lines 271-317) ---------- */

    for (std::size_t i = 0; i < N - 2; ++i) {
        // Unpowered swingby at planet i+2 (0-based i+1).
        const Vec3 v_rel_in = {v_sc_pl_in[i + 1][0] - v[i + 1][0],
                               v_sc_pl_in[i + 1][1] - v[i + 1][1],
                               v_sc_pl_in[i + 1][2] - v[i + 1][2]};

        // e = 1 + rp(i)/muvec(i+1)*v_rel_in'*v_rel_in evaluates in MATLAB
        // as ((rp/mu)*v_rel_in') * v_rel_in: the scalar multiplies each
        // component BEFORE the row-times-column product, which then uses
        // the right-associative small-dot kernel (see dot3).
        const double rpmu = rp[i] / muvec[i + 1];
        const Vec3 w = {rpmu * v_rel_in[0], rpmu * v_rel_in[1], rpmu * v_rel_in[2]};
        const double e = 1 + dot3(w, v_rel_in);

        const double beta_rot = 2 * std::asin(1 / e); // velocity rotation

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

    /* ---------------- final block (lines 320-346) ------------------ */

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

    // DVtot = sum(DV) (lines 354-361, non-gtoc1 branch), sequential sum.
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

/* ------------------------------------------------------------------ */
/* Problem definition assets                                           */
/* ------------------------------------------------------------------ */

// Parsed content of <data_root>/{messengerfull,cassini2}_problem.txt
// (committed text assets derived during the validated CEC2011 port;
// format: '#' comments, "key: value" lines).
struct ParsedProblemFile {
    std::vector<int> sequence;
    std::string objective_type;
    bool has_rp = false;
    bool has_e = false;
    double rp = 0.0;
    double e = 0.0;
};

std::string trim_copy(const std::string& s) {
    const std::string ws = " \t";
    const std::size_t b = s.find_first_not_of(ws);
    if (b == std::string::npos) {
        return {};
    }
    const std::size_t e = s.find_last_not_of(ws);
    return s.substr(b, e - b + 1);
}

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

/* ------------------------------------------------------------------ */
/* Benchmark problem wrapper                                           */
/* ------------------------------------------------------------------ */

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
            // define_boundaries.m case 21 (matches getlimit_messenger.m;
            // the unused .mat 'bounds' field differs and is ignored).
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
            // define_boundaries.m case 22. [PRESERVE] element 9 lower
            // bound is 400 (GSK-canonical), NOT the 800 in
            // getlimit_cassini2.m / the .mat 'bounds' field (official
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

        // Load the problem struct ONCE here. The reference re-loads the
        // .mat inside the per-individual evaluation loop (Calc_Fitx_2011.m
        // lines 49/53) -- a pure performance bug, numerically irrelevant.
        const std::filesystem::path path = data_root / file_name;
        const ParsedProblemFile parsed = parse_problem_file(path);

        // Validate the exported asset against the dossier's embedded
        // constants so a corrupted/swapped file cannot go unnoticed.
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

        // Dimension = 4*N - 2 for the non-'time to AUs' decision vector;
        // must agree with define_boundaries.m (26 and 22).
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
