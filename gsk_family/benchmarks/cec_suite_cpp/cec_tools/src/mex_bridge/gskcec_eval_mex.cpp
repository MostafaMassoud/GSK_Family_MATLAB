// gskcec_eval: MATLAB MEX bridge to the standalone C++ CEC benchmark port.
//
// The CEC benchmark library itself is MEX-free (project contract); this
// OPTIONAL bridge exists so the MATLAB GSK optimizers evaluate the exact
// same ported C++ code that the C++ tools validate. Built by
// scripts/build_mex_bridge.ps1 into build/mex/gskcec_eval.mexw64.
//
// MATLAB API:
//   h = gskcec_eval('new', suite, function_id, dimension, data_root)
//   f = gskcec_eval('eval', h, X)   % X is D x NP (one candidate per column,
//                                   % the classic cec17_func orientation);
//                                   % returns 1 x NP fitness row.
//   s = gskcec_eval('info', h)      % struct: suite, function_id, dimension,
//                                   % lb (1xD), ub (1xD), optimum
//   gskcec_eval('free', h)
//   gskcec_eval('clear')            % drop every live problem handle

#include "gskcec/benchmark/factory.hpp"

#include "mex.h"

#include <cstring>
#include <map>
#include <memory>
#include <span>
#include <string>

namespace {

std::map<int, std::unique_ptr<gskcec::BenchmarkProblem>>& registry() {
    static std::map<int, std::unique_ptr<gskcec::BenchmarkProblem>> problems;
    return problems;
}

int& next_handle() {
    static int next = 1;
    return next;
}

std::string get_string(const mxArray* arr, const char* what) {
    if (!mxIsChar(arr)) {
        mexErrMsgIdAndTxt("gskcec:badInput", "%s must be a character vector.", what);
    }
    char* raw = mxArrayToString(arr);
    std::string value(raw != nullptr ? raw : "");
    mxFree(raw);
    return value;
}

double get_scalar(const mxArray* arr, const char* what) {
    if (!mxIsDouble(arr) || mxIsComplex(arr) || mxGetNumberOfElements(arr) != 1) {
        mexErrMsgIdAndTxt("gskcec:badInput", "%s must be a real double scalar.", what);
    }
    return mxGetScalar(arr);
}

gskcec::BenchmarkProblem& get_problem(double handle_value) {
    const int handle = static_cast<int>(handle_value);
    const auto it = registry().find(handle);
    if (it == registry().end()) {
        mexErrMsgIdAndTxt("gskcec:badHandle", "Unknown problem handle %d.", handle);
    }
    return *it->second;
}

void cleanup_at_exit() {
    registry().clear();
}

} // namespace

extern "C" __declspec(dllexport) void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
    mexAtExit(cleanup_at_exit);
    if (nrhs < 1) {
        mexErrMsgIdAndTxt("gskcec:usage",
                          "Usage: gskcec_eval('new'|'eval'|'info'|'free'|'clear', ...)");
    }
    const std::string command = get_string(prhs[0], "command");

    try {
        if (command == "new") {
            if (nrhs != 5 || nlhs > 1) {
                mexErrMsgIdAndTxt("gskcec:usage",
                                  "h = gskcec_eval('new', suite, function_id, dimension, data_root)");
            }
            const std::string suite = get_string(prhs[1], "suite");
            const int function_id = static_cast<int>(get_scalar(prhs[2], "function_id"));
            const int dimension = static_cast<int>(get_scalar(prhs[3], "dimension"));
            const std::string data_root = get_string(prhs[4], "data_root");
            auto problem = gskcec::make_problem(suite, function_id, dimension, data_root);
            const int handle = next_handle()++;
            registry().emplace(handle, std::move(problem));
            plhs[0] = mxCreateDoubleScalar(static_cast<double>(handle));
            return;
        }
        if (command == "eval") {
            if (nrhs != 3 || nlhs > 1) {
                mexErrMsgIdAndTxt("gskcec:usage", "f = gskcec_eval('eval', h, X)  %% X is D x NP");
            }
            auto& problem = get_problem(get_scalar(prhs[1], "handle"));
            if (!mxIsDouble(prhs[2]) || mxIsComplex(prhs[2])) {
                mexErrMsgIdAndTxt("gskcec:badInput", "X must be a real double matrix.");
            }
            const auto dim = static_cast<int>(mxGetM(prhs[2]));
            const auto np = mxGetN(prhs[2]);
            if (dim != problem.dimension()) {
                mexErrMsgIdAndTxt("gskcec:badInput",
                                  "X has %d rows but problem dimension is %d (one candidate per column).",
                                  dim, problem.dimension());
            }
            const double* x = mxGetPr(prhs[2]);
            plhs[0] = mxCreateDoubleMatrix(1, np, mxREAL);
            double* out = mxGetPr(plhs[0]);
            for (std::size_t k = 0; k < np; ++k) {
                out[k] = problem.evaluate(std::span<const double>(x + k * static_cast<std::size_t>(dim),
                                                                  static_cast<std::size_t>(dim)));
            }
            return;
        }
        if (command == "info") {
            if (nrhs != 2 || nlhs > 1) {
                mexErrMsgIdAndTxt("gskcec:usage", "s = gskcec_eval('info', h)");
            }
            const auto& problem = get_problem(get_scalar(prhs[1], "handle"));
            const auto bounds = problem.bounds();
            const char* fields[] = {"suite", "function_id", "dimension", "lb", "ub", "optimum"};
            plhs[0] = mxCreateStructMatrix(1, 1, 6, fields);
            mxSetField(plhs[0], 0, "suite", mxCreateString(problem.suite_name().c_str()));
            mxSetField(plhs[0], 0, "function_id", mxCreateDoubleScalar(problem.function_id()));
            mxSetField(plhs[0], 0, "dimension", mxCreateDoubleScalar(problem.dimension()));
            mxArray* lb = mxCreateDoubleMatrix(1, bounds.dimension(), mxREAL);
            mxArray* ub = mxCreateDoubleMatrix(1, bounds.dimension(), mxREAL);
            std::memcpy(mxGetPr(lb), bounds.lower().data(), bounds.dimension() * sizeof(double));
            std::memcpy(mxGetPr(ub), bounds.upper().data(), bounds.dimension() * sizeof(double));
            mxSetField(plhs[0], 0, "lb", lb);
            mxSetField(plhs[0], 0, "ub", ub);
            mxSetField(plhs[0], 0, "optimum", mxCreateDoubleScalar(problem.optimum()));
            return;
        }
        if (command == "free") {
            if (nrhs != 2) {
                mexErrMsgIdAndTxt("gskcec:usage", "gskcec_eval('free', h)");
            }
            registry().erase(static_cast<int>(get_scalar(prhs[1], "handle")));
            return;
        }
        if (command == "clear") {
            registry().clear();
            return;
        }
    } catch (const std::exception& ex) {
        mexErrMsgIdAndTxt("gskcec:error", "%s", ex.what());
    }
    mexErrMsgIdAndTxt("gskcec:usage", "Unknown command '%s'.", command.c_str());
}
