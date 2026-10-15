#pragma once

// CEC2013-LSGO (large-scale) benchmark suite: base class shared by the 15
// test functions F1..F15.
//
// Adapted from the reference implementation (Benchmarks.cpp/h of the
// CEC2013-LSGO test suite). Differences:
//   * data files load from the directory passed to the constructor, not
//     from the current working directory;
//   * a missing or bad data file raises std::runtime_error naming the path;
//   * buffers are std::vector instead of raw new[]/delete[];
//   * the evaluation-counting/CSV harness, the unused random data
//     generators and the CCVIL index-map helpers are left out (none of them
//     affect function values).
// Formulas, loop order, transformation chains and the rotation,
// permutation and grouping logic are the same as the reference.
//
// This is the large-scale suite (D = 1000, or 905 for F13/F14). It is a
// separate suite from the standard CEC2013 one; never merge the two.

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

    /// Returns the function value at @p x (getDimension() values).
    /// Not thread-safe: writes to internal scratch buffers.
    virtual double compute(const double* x) = 0;

    int getMinX() const { return minX; }
    int getMaxX() const { return maxX; }
    int getDimension() const { return dimension; }
    unsigned getID() const { return ID; }

protected:
    // Same literals as the reference #define PI / #define E.
    static constexpr double PI = 3.141592653589793238462643383279;
    static constexpr double E = 2.718281828459045235360287471352;

    // ---- Data loading (errors: std::runtime_error naming the file) ----
    std::filesystem::path dataFilePath(const std::string& suffix) const;
    /// F<ID>-xopt.txt: shift vector, exactly getDimension() values.
    std::vector<double> readOvector() const;
    /// F<ID>-xopt.txt split into the s[] groups (load s first).
    std::vector<std::vector<double>> readOvectorVec() const;
    /// F<ID>-p.txt: permutation, 1-based in the file, returned 0-based.
    std::vector<int> readPermVector() const;
    /// F<ID>-R<sub_dim>.txt: sub_dim x sub_dim rotation matrix.
    std::vector<std::vector<double>> readR(int sub_dim) const;
    /// F<ID>-s.txt: the @p num subcomponent sizes (25, 50 or 100 each).
    std::vector<int> readS(int num) const;
    /// F<ID>-w.txt: the @p num subcomponent weights.
    std::vector<double> readW(int num) const;

    // ---- Transformations (change z in place, as in the reference) ----
    void transform_osz(double* z, int dim) const;
    void transform_asy(double* z, double beta, int dim) const;
    void Lambda(double* z, double alpha, int dim) const;
    static int sign(double x);
    static double hat(double x);
    static double c1(double x);
    static double c2(double x);

    // ---- Basic functions (apply their transforms to x in place) ----
    double elliptic(double* x, int dim) const;
    double rastrigin(double* x, int dim) const;
    double ackley(double* x, int dim) const;
    double schwefel(double* x, int dim) const;
    double sphere(double* x, int dim) const;
    double rosenbrock(double* x, int dim) const;

    // ---- Rotation helpers for the grouped functions ----
    std::vector<double> multiply(const double* z,
                                 const std::vector<std::vector<double>>& matrix,
                                 int dim) const;
    /// Same as multiply(), but writes into @p out (at least @p dim doubles)
    /// instead of allocating. Same loop order (i, j = dim-1..0), so the
    /// result matches multiply() bit for bit.
    void multiply_into(double* out, const double* z,
                       const std::vector<std::vector<double>>& matrix,
                       int dim) const;
    /// r25, r50 or r100 for a subcomponent size of 25, 50 or 100; any other
    /// size throws std::runtime_error.
    const std::vector<std::vector<double>>& rotationMatrixFor(int subDimension) const;
    /// Gathers subcomponent @p i of anotherz (through Pvector), rotates it
    /// and advances @p c by s[i]. Used by the non-overlapping grouped
    /// functions. Returns the shared rot_scratch_ buffer (at least s[i]
    /// valid values): use the result before the next rotateVector*() call,
    /// which overwrites it. Non-const so callers can pass .data() to the
    /// in-place transform_* functions.
    std::vector<double>& rotateVector(int i, int& c) const;
    /// Overlapping (conforming) variant: neighbouring subcomponents share
    /// `overlap` coordinates of the shifted vector. Used by F13. Same buffer
    /// rule as rotateVector().
    std::vector<double>& rotateVectorConform(int i, int& c) const;
    /// Overlapping (conflicting) variant: each subcomponent subtracts its own
    /// shift group OvectorVec[i] from the raw input @p x. Used by F14. Same
    /// buffer rule as rotateVector().
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
    std::vector<double> anotherz; // scratch: shifted input, changed by compute()

    // Scratch buffers for the rotateVector*() helpers, reused so the s_size
    // calls inside every compute() allocate nothing. They grow to the
    // largest subcomponent size seen. `mutable` because the helpers are
    // const; each problem instance is used by one thread only.
    mutable std::vector<double> z_scratch_;   // gathered subcomponent input
    mutable std::vector<double> rot_scratch_; // rotated subcomponent output
};

} // namespace gskcec::cec2013lsgo
