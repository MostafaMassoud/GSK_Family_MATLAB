// CEC2013-LSGO problem wrapper: exposes the F1..F15 classes through the
// BenchmarkProblem interface (native D, bounds, optimum 0, size checks).

#include "gskcec/benchmark/cec2013lsgo.hpp"

#include "Header.h"

#include <stdexcept>
#include <string>
#include <utility>

namespace gskcec::cec2013lsgo {

namespace {

std::unique_ptr<Benchmarks> make_suite_function(int function_id,
                                                const std::filesystem::path& data_root) {
    switch (function_id) {
    case 1: return std::make_unique<F1>(data_root);
    case 2: return std::make_unique<F2>(data_root);
    case 3: return std::make_unique<F3>(data_root);
    case 4: return std::make_unique<F4>(data_root);
    case 5: return std::make_unique<F5>(data_root);
    case 6: return std::make_unique<F6>(data_root);
    case 7: return std::make_unique<F7>(data_root);
    case 8: return std::make_unique<F8>(data_root);
    case 9: return std::make_unique<F9>(data_root);
    case 10: return std::make_unique<F10>(data_root);
    case 11: return std::make_unique<F11>(data_root);
    case 12: return std::make_unique<F12>(data_root);
    case 13: return std::make_unique<F13>(data_root);
    case 14: return std::make_unique<F14>(data_root);
    case 15: return std::make_unique<F15>(data_root);
    default:
        throw std::invalid_argument("cec2013lsgo: unsupported function id " +
                                    std::to_string(function_id) + " (supported: 1..15).");
    }
}

class Cec2013LsgoProblem final : public BenchmarkProblem {
public:
    Cec2013LsgoProblem(int function_id, const std::filesystem::path& data_root)
        : impl_(make_suite_function(function_id, data_root)) {}

    std::string suite_name() const override {
        return "cec2013lsgo";
    }

    int function_id() const override {
        return static_cast<int>(impl_->getID());
    }

    int dimension() const override {
        return impl_->getDimension();
    }

    Bounds bounds() const override {
        return Bounds::uniform(static_cast<Index>(impl_->getDimension()),
                               static_cast<Real>(impl_->getMinX()),
                               static_cast<Real>(impl_->getMaxX()));
    }

    Real optimum() const override {
        return 0.0;
    }

    /// Not thread-safe: evaluate() is const but changes the scratch buffers
    /// inside *impl_ (the pointee is not const). Never share one problem
    /// across threads.
    Real evaluate(std::span<const Real> x) const override {
        if (x.size() != static_cast<std::size_t>(impl_->getDimension())) {
            throw std::invalid_argument(
                "cec2013lsgo f" + std::to_string(impl_->getID()) + " expects dimension " +
                std::to_string(impl_->getDimension()) + ", got " + std::to_string(x.size()) + ".");
        }
        return impl_->compute(x.data());
    }

private:
    std::unique_ptr<Benchmarks> impl_; // its scratch buffers change during evaluate()
};

} // namespace

std::unique_ptr<BenchmarkProblem> make_problem(int function_id,
                                               const std::filesystem::path& data_root) {
    return std::make_unique<Cec2013LsgoProblem>(function_id, data_root);
}

const std::vector<int>& supported_functions() {
    static const std::vector<int> ids{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
    return ids;
}

int native_dimension(int function_id) {
    if (function_id < 1 || function_id > 15) {
        throw std::invalid_argument("cec2013lsgo: unsupported function id " +
                                    std::to_string(function_id) + " (supported: 1..15).");
    }
    // F13/F14: 20 subcomponents with sizes summing to 1000 overlap by 5,
    // which leaves D = 905. All other functions have D = 1000.
    return (function_id == 13 || function_id == 14) ? 905 : 1000;
}

} // namespace gskcec::cec2013lsgo
