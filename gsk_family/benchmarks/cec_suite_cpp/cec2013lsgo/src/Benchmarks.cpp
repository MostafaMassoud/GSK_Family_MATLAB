#include "Benchmarks.h"

#include "gskcec/benchmark/data_loading.hpp"

#include <cmath>
#include <cstddef>
#include <fstream>
#include <iterator>
#include <map>
#include <sstream>
#include <stdexcept>
#include <utility>
#include <vector>

namespace gskcec::cec2013lsgo {

namespace {

// Reads every numeric value from a text file, treating commas as
// separators in addition to whitespace. This reproduces the token stream
// of the reference line/comma parsers for the comma-separated permutation
// (F<ID>-p.txt) and rotation matrix (F<ID>-R*.txt) files. Throws
// std::runtime_error naming the file path when the file is missing,
// unreadable, empty or contains a non-numeric token.
std::vector<double> readNumberList(const std::filesystem::path& path) {
    require_file(path);
    std::ifstream file(path);
    if (!file) {
        throw std::runtime_error("Cannot open data file: " + path.string());
    }
    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    for (char& ch : content) {
        if (ch == ',') {
            ch = ' ';
        }
    }
    std::istringstream in(content);
    std::vector<double> values;
    std::string token;
    while (in >> token) {
        try {
            std::size_t consumed = 0;
            const double value = std::stod(token, &consumed);
            if (consumed != token.size()) {
                throw std::invalid_argument(token);
            }
            values.push_back(value);
        } catch (const std::exception&) {
            throw std::runtime_error("Non-numeric token '" + token + "' at value index " +
                                     std::to_string(values.size()) +
                                     " in data file: " + path.string());
        }
    }
    if (values.empty()) {
        throw std::runtime_error("Data file contains no values: " + path.string());
    }
    return values;
}

void requireValueCount(const std::vector<double>& values, std::size_t expected,
                       const std::filesystem::path& path) {
    if (values.size() != expected) {
        throw std::runtime_error("Data file " + path.string() + " holds " +
                                 std::to_string(values.size()) + " values, expected " +
                                 std::to_string(expected) + ".");
    }
}

// --- per-dim pow caches (GROUP A: bit-identical) -------------------------
//
// elliptic() and Lambda() call std::pow(const_base, f(i, dim)) for every
// coordinate on every evaluation, where the exponent depends only on i and
// dim (not on the input values). Caching the per-index pow results keyed by
// dim turns a pow() per coordinate per call into a table lookup. The cached
// doubles are produced by the SAME std::pow(base, exponent) expression with
// the SAME operands, so reusing them is bit-identical to recomputing.
//
// thread_local because the surrounding class documents one instance per
// thread; this keeps the cache lock-free while staying safe if separate
// worker threads each construct their own benchmark objects.

// elliptic: pow(1.0e6, i / (double)(dim-1)), i in [0, dim).
const std::vector<double>& ellipticPowTable(int dim) {
    thread_local std::map<int, std::vector<double>> cache;
    auto it = cache.find(dim);
    if (it != cache.end()) {
        return it->second;
    }
    std::vector<double> table(static_cast<std::size_t>(dim));
    for (int i = 0; i < dim; ++i) {
        table[static_cast<std::size_t>(i)] = std::pow(1.0e6, i / ((double)(dim - 1)));
    }
    return cache.emplace(dim, std::move(table)).first->second;
}

// Lambda: pow(alpha, 0.5 * i / (double)(dim-1)), i in [0, dim).
const std::vector<double>& lambdaPowTable(double alpha, int dim) {
    thread_local std::map<std::pair<double, int>, std::vector<double>> cache;
    const std::pair<double, int> key{alpha, dim};
    auto it = cache.find(key);
    if (it != cache.end()) {
        return it->second;
    }
    std::vector<double> table(static_cast<std::size_t>(dim));
    for (int i = 0; i < dim; ++i) {
        table[static_cast<std::size_t>(i)] = std::pow(alpha, 0.5 * i / ((double)(dim - 1)));
    }
    return cache.emplace(key, std::move(table)).first->second;
}

} // namespace

Benchmarks::Benchmarks(std::filesystem::path dataDir) : data_dir(std::move(dataDir)) {}

std::filesystem::path Benchmarks::dataFilePath(const std::string& suffix) const {
    return data_dir / ("F" + std::to_string(ID) + suffix);
}

std::vector<double> Benchmarks::readOvector() const {
    const std::filesystem::path path = dataFilePath("-xopt.txt");
    std::vector<double> values = load_values_file(path);
    requireValueCount(values, static_cast<std::size_t>(dimension), path);
    return values;
}

std::vector<std::vector<double>> Benchmarks::readOvectorVec() const {
    const std::filesystem::path path = dataFilePath("-xopt.txt");
    const std::vector<double> values = load_values_file(path);
    std::size_t total = 0;
    for (int i = 0; i < s_size; ++i) {
        total += static_cast<std::size_t>(s[i]);
    }
    requireValueCount(values, total, path);
    // Same grouping as the reference reader: group i takes the next s[i]
    // consecutive values of the file.
    std::vector<std::vector<double>> groups(static_cast<std::size_t>(s_size));
    auto group_begin = values.begin();
    for (int i = 0; i < s_size; ++i) {
        groups[i].assign(group_begin, group_begin + s[i]);
        group_begin += s[i];
    }
    return groups;
}

std::vector<int> Benchmarks::readPermVector() const {
    const std::filesystem::path path = dataFilePath("-p.txt");
    const std::vector<double> values = readNumberList(path);
    requireValueCount(values, static_cast<std::size_t>(dimension), path);
    std::vector<int> perm(values.size());
    for (std::size_t i = 0; i < values.size(); ++i) {
        perm[i] = static_cast<int>(values[i] - 1.0); // reference: stod(value) - 1 into int
        if (perm[i] < 0 || perm[i] >= dimension) {
            throw std::runtime_error("Permutation index " + std::to_string(values[i]) +
                                     " out of range [1," + std::to_string(dimension) +
                                     "] in data file: " + path.string());
        }
    }
    return perm;
}

std::vector<std::vector<double>> Benchmarks::readR(int sub_dim) const {
    const std::filesystem::path path = dataFilePath("-R" + std::to_string(sub_dim) + ".txt");
    const std::vector<double> values = readNumberList(path);
    const std::size_t n = static_cast<std::size_t>(sub_dim);
    requireValueCount(values, n * n, path);
    // Row-major file layout (one matrix row per line), as the reference read it.
    std::vector<std::vector<double>> m(n, std::vector<double>(n));
    for (std::size_t i = 0; i < n; ++i) {
        for (std::size_t j = 0; j < n; ++j) {
            m[i][j] = values[i * n + j];
        }
    }
    return m;
}

std::vector<int> Benchmarks::readS(int num) const {
    const std::filesystem::path path = dataFilePath("-s.txt");
    const std::vector<double> values = load_values_file(path);
    requireValueCount(values, static_cast<std::size_t>(num), path);
    std::vector<int> sizes(values.size());
    for (std::size_t i = 0; i < values.size(); ++i) {
        sizes[i] = static_cast<int>(values[i]); // reference: stod(value) into int
    }
    return sizes;
}

std::vector<double> Benchmarks::readW(int num) const {
    const std::filesystem::path path = dataFilePath("-w.txt");
    std::vector<double> values = load_values_file(path);
    requireValueCount(values, static_cast<std::size_t>(num), path);
    return values;
}

// --- transformation chain (verbatim from the reference) ---

void Benchmarks::transform_osz(double* z, int dim) const {
    // apply osz transformation to z
    for (int i = 0; i < dim; ++i) {
        z[i] = sign(z[i]) *
               std::exp(hat(z[i]) +
                        0.049 * (std::sin(c1(z[i]) * hat(z[i])) + std::sin(c2(z[i]) * hat(z[i]))));
    }
}

void Benchmarks::transform_asy(double* z, double beta, int dim) const {
    for (int i = 0; i < dim; ++i) {
        if (z[i] > 0) {
            z[i] = std::pow(z[i], 1 + beta * i / ((double)(dim - 1)) * std::sqrt(z[i]));
        }
    }
}

void Benchmarks::Lambda(double* z, double alpha, int dim) const {
    // GROUP A: pow(alpha, 0.5*i/(dim-1)) depends only on (alpha, i, dim) and is
    // served from a per-dim cache; the multiply order/operands are unchanged.
    const std::vector<double>& lambdaPow = lambdaPowTable(alpha, dim);
    for (int i = 0; i < dim; ++i) {
        z[i] = z[i] * lambdaPow[static_cast<std::size_t>(i)];
    }
}

int Benchmarks::sign(double x) {
    if (x > 0) return 1;
    if (x < 0) return -1;
    return 0;
}

double Benchmarks::hat(double x) {
    if (x == 0) {
        return 0;
    }
    return std::log(std::abs(x));
}

double Benchmarks::c1(double x) {
    if (x > 0) {
        return 10;
    }
    return 5.5;
}

double Benchmarks::c2(double x) {
    if (x > 0) {
        return 7.9;
    }
    return 3.1;
}

// --- basic functions (verbatim formulas and loop order) ---

double Benchmarks::elliptic(double* x, int dim) const {
    double result = 0.0;
    int i;

    transform_osz(x, dim);

    // GROUP A: pow(1.0e6, i/(dim-1)) depends only on (i, dim) and is served
    // from a per-dim cache; the accumulation order/operands are unchanged.
    const std::vector<double>& ellipticPow = ellipticPowTable(dim);
    for (i = 0; i < dim; i++) {
        result += ellipticPow[static_cast<std::size_t>(i)] * x[i] * x[i];
    }

    return result;
}

double Benchmarks::rastrigin(double* x, int dim) const {
    double sum = 0;
    int i;

    // T_{osz}
    transform_osz(x, dim);

    // T_{asy}^{0.2}
    transform_asy(x, 0.2, dim);

    // lambda
    Lambda(x, 10, dim);

    for (i = dim - 1; i >= 0; i--) {
        sum += x[i] * x[i] - 10.0 * std::cos(2 * PI * x[i]) + 10.0;
    }

    return sum;
}

double Benchmarks::ackley(double* x, int dim) const {
    double sum1 = 0.0;
    double sum2 = 0.0;
    double sum;
    int i;

    // T_{osz}
    transform_osz(x, dim);

    // T_{asy}^{0.2}
    transform_asy(x, 0.2, dim);

    // lambda
    Lambda(x, 10, dim);

    for (i = dim - 1; i >= 0; i--) {
        sum1 += (x[i] * x[i]);
        sum2 += std::cos(2.0 * PI * x[i]);
    }

    sum = -20.0 * std::exp(-0.2 * std::sqrt(sum1 / dim)) - std::exp(sum2 / dim) + 20.0 + E;
    return sum;
}

double Benchmarks::schwefel(double* x, int dim) const {
    int j;
    double s1 = 0;
    double s2 = 0;

    // T_{osz}
    transform_osz(x, dim);

    // T_{asy}^{0.2}
    transform_asy(x, 0.2, dim);

    for (j = 0; j < dim; j++) {
        s1 += x[j];
        s2 += (s1 * s1);
    }

    return s2;
}

double Benchmarks::sphere(double* x, int dim) const {
    double sum = 0;
    int i;

    for (i = dim - 1; i >= 0; i--) {
        sum += x[i] * x[i]; // GROUP B: std::pow(x[i], 2) -> x[i]*x[i] (<=1 ULP)
    }

    return sum;
}

double Benchmarks::rosenbrock(double* x, int dim) const {
    int j;
    double oz, t;
    double s = 0.0;
    j = dim - 1;

    for (--j; j >= 0; j--) {
        oz = x[j + 1];
        t = ((x[j] * x[j]) - oz);
        s += (100.0 * t * t);
        t = (x[j] - 1.0);
        s += (t * t);
    }
    return s;
}

// --- rotation helpers (verbatim logic; buffers returned by value) ---

std::vector<double> Benchmarks::multiply(const double* z,
                                         const std::vector<std::vector<double>>& matrix,
                                         int dim) const {
    std::vector<double> result(static_cast<std::size_t>(dim));

    for (int i = dim - 1; i >= 0; i--) {
        result[i] = 0;

        for (int j = dim - 1; j >= 0; j--) {
            result[i] += z[j] * matrix[i][j];
        }
    }

    return result;
}

void Benchmarks::multiply_into(double* out, const double* z,
                               const std::vector<std::vector<double>>& matrix,
                               int dim) const {
    // Identical accumulation to multiply() (same i/j order, same operands);
    // only the destination differs (caller buffer instead of a fresh vector).
    for (int i = dim - 1; i >= 0; i--) {
        out[i] = 0;

        for (int j = dim - 1; j >= 0; j--) {
            out[i] += z[j] * matrix[i][j];
        }
    }
}

const std::vector<std::vector<double>>& Benchmarks::rotationMatrixFor(int subDimension) const {
    if (subDimension == 25) {
        return r25;
    }
    if (subDimension == 50) {
        return r50;
    }
    if (subDimension == 100) {
        return r100;
    }
    // Reference printed "size of rotation matrix out of range" and went on
    // with a stale buffer; surface it as an error instead.
    throw std::runtime_error("cec2013lsgo F" + std::to_string(ID) +
                             ": rotation matrix size out of range: " +
                             std::to_string(subDimension));
}

std::vector<double>& Benchmarks::rotateVector(int i, int& c) const {
    const std::size_t n = static_cast<std::size_t>(s[i]);
    if (z_scratch_.size() < n) z_scratch_.resize(n);
    if (rot_scratch_.size() < n) rot_scratch_.resize(n);

    // copy values into the scratch vector
    for (int j = c; j < c + s[i]; ++j) {
        z_scratch_[j - c] = anotherz[Pvector[j]];
    }

    multiply_into(rot_scratch_.data(), z_scratch_.data(), rotationMatrixFor(s[i]), s[i]);
    c = c + s[i];
    return rot_scratch_;
}

std::vector<double>& Benchmarks::rotateVectorConform(int i, int& c) const {
    const std::size_t n = static_cast<std::size_t>(s[i]);
    if (z_scratch_.size() < n) z_scratch_.resize(n);
    if (rot_scratch_.size() < n) rot_scratch_.resize(n);

    // copy values into the scratch vector
    for (int j = c - i * overlap; j < c + s[i] - i * overlap; ++j) {
        z_scratch_[j - (c - i * overlap)] = anotherz[Pvector[j]];
    }

    multiply_into(rot_scratch_.data(), z_scratch_.data(), rotationMatrixFor(s[i]), s[i]);
    c = c + s[i];
    return rot_scratch_;
}

std::vector<double>& Benchmarks::rotateVectorConflict(int i, int& c, const double* x) const {
    const std::size_t n = static_cast<std::size_t>(s[i]);
    if (z_scratch_.size() < n) z_scratch_.resize(n);
    if (rot_scratch_.size() < n) rot_scratch_.resize(n);

    // copy values into the scratch vector
    for (int j = c - i * overlap; j < c + s[i] - i * overlap; ++j) {
        z_scratch_[j - (c - i * overlap)] = x[Pvector[j]] - OvectorVec[i][j - (c - i * overlap)];
    }

    multiply_into(rot_scratch_.data(), z_scratch_.data(), rotationMatrixFor(s[i]), s[i]);
    c = c + s[i];
    return rot_scratch_;
}

} // namespace gskcec::cec2013lsgo
