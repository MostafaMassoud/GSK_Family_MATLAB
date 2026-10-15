#pragma once

// CEC2013 Large-Scale Global Optimization benchmark suite -- shared base
// class for the 15 test functions (F1..F15).
//
// Adapted from the reference implementation (Benchmarks.cpp/h of the
// CEC2013 LSGO test suite) for standalone project use:
//   * data files load from an explicit directory passed at construction
//     (no current-working-directory dependence),
//   * missing/bad data files raise std::runtime_error naming the path,
//   * buffers are std::vector (RAII) instead of raw new[]/delete[],
//   * the legacy evaluation-counting/CSV-milestone harness, the unused
//     on-the-fly random data generators and the CCVIL index-map helpers
//     were removed (none of them participate in function evaluation).
// The numerical paths (formulas, loop order, transformation chains,
// rotation/permutation/grouping logic) are preserved exactly.
//
// This is the LARGE-SCALE suite (D = 1000 / 905). It is completely
// distinct from the standard CEC2013 suite; the two must never be merged.

#include <filesystem>
#include <string>
#include <vector>

namespace gskcec::cec2013lsgo {

class Benchmarks {
public:
    explicit Benchmarks(std::filesystem::path dataDir);
    virtual ~Benchmarks() = default;

    Benchmarks(const Benchmarks&) = delete;
    Benchmarks& operator=(const Benchmarks&) = delete;

    /// Evaluates the function at @p x (length getDimension()).
    /// Mutates internal scratch buffers: NOT thread-safe.
    virtual double compute(const double* x) = 0;

    int getMinX() const { return minX; }
    int getMaxX() const { return maxX; }
    int getDimension() const { return dimension; }
    unsigned getID() const { return ID; }

protected:
    // Same literals as the reference #define PI / #define E.
    static constexpr double PI = 3.141592653589793238462643383279;
    static constexpr double E = 2.718281828459045235360287471352;

    // --- data loading (throws std::runtime_error naming the file path) ---
    std::filesystem::path dataFilePath(const std::string& suffix) const;
    /// F<ID>-xopt.txt: shift vector, exactly getDimension() values.
    std::vector<double> readOvector() const;
    /// F<ID>-xopt.txt split into the s[] groups (requires s loaded first).
    std::vector<std::vector<double>> readOvectorVec() const;
    /// F<ID>-p.txt: permutation, 1-based in file, converted to 0-based.
    std::vector<int> readPermVector() const;
    /// F<ID>-R<sub_dim>.txt: sub_dim x sub_dim rotation matrix.
    std::vector<std::vector<double>> readR(int sub_dim) const;
    /// F<ID>-s.txt: the @p num subcomponent sizes (25/50/100 each).
    std::vector<int> readS(int num) const;
    /// F<ID>-w.txt: the @p num subcomponent weights.
    std::vector<double> readW(int num) const;

    // --- transformation chain (mutates z in place, as in the reference) ---
    void transform_osz(double* z, int dim) const;
    void transform_asy(double* z, double beta, int dim) const;
    void Lambda(double* z, double alpha, int dim) const;
    static int sign(double x);
    static double hat(double x);
    static double c1(double x);
    static double c2(double x);

    // --- basic functions (apply their transforms to x in place) ---
    double elliptic(double* x, int dim) const;
    double rastrigin(double* x, int dim) const;
    double ackley(double* x, int dim) const;
    double schwefel(double* x, int dim) const;
    double sphere(double* x, int dim) const;
    double rosenbrock(double* x, int dim) const;

    // --- rotation helpers for the grouped functions ---
    std::vector<double> multiply(const double* z,
                                 const std::vector<std::vector<double>>& matrix,
                                 int dim) const;
    /// Allocation-free variant of multiply(): writes the rotated vector into
    /// the caller-provided @p out buffer (which must hold at least @p dim
    /// doubles). The inner accumulation loop matches multiply() exactly
    /// (i = dim-1..0, j = dim-1..0), so the result is bit-identical.
    void multiply_into(double* out, const double* z,
                       const std::vector<std::vector<double>>& matrix,
                       int dim) const;
    /// r25/r50/r100 by subcomponent size; throws std::runtime_error otherwise.
    const std::vector<std::vector<double>>& rotationMatrixFor(int subDimension) const;
    /// Extracts (via Pvector) and rotates subcomponent @p i of anotherz;
    /// advances @p c by s[i]. Used by the non-overlapping grouped functions.
    /// Returns a reference to the reused rot_scratch_ buffer; the caller MUST
    /// consume the result (it holds at least s[i] valid doubles) before the
    /// next rotateVector*() call, which overwrites the same buffer. All
    /// current callers do exactly that. Non-const reference so callers may
    /// pass .data() to the in-place transform_* functions.
    std::vector<double>& rotateVector(int i, int& c) const;
    /// Overlapping (conforming) variant: subcomponents share `overlap`
    /// coordinates of the shifted vector. Used by F13. Same scratch-reuse
    /// contract as rotateVector().
    std::vector<double>& rotateVectorConform(int i, int& c) const;
    /// Overlapping (conflicting) variant: each subcomponent has its own
    /// shift group from OvectorVec, applied to the raw input. Used by F14.
    /// Same scratch-reuse contract as rotateVector().
    std::vector<double>& rotateVectorConflict(int i, int& c, const double* x) const;

    unsigned ID = 0;
    int minX = -100;
    int maxX = 100;
    int dimension = 1000;
    int s_size = 0;
    int overlap = 0;

    std::filesystem::path data_dir;

    std::vector<double> Ovector;
    std::vector<std::vector<double>> OvectorVec;
    std::vector<int> Pvector;
    std::vector<std::vector<double>> r25;
    std::vector<std::vector<double>> r50;
    std::vector<std::vector<double>> r100;
    std::vector<int> s;
    std::vector<double> w;
    std::vector<double> anotherz; // scratch: shifted input, mutated by compute()

    // Per-call scratch for the rotateVector*() helpers, reused across calls to
    // avoid heap churn (evaluate() runs billions of times). Grown lazily to
    // the largest subcomponent size encountered. `mutable` because the rotate
    // helpers are const and each problem instance is single-threaded.
    mutable std::vector<double> z_scratch_;   // gathered subcomponent input
    mutable std::vector<double> rot_scratch_; // rotated subcomponent output
};

} // namespace gskcec::cec2013lsgo
