# CLI exit-code test for gsk_run, gsk_validate and gsk_bench, run by ctest as
#   cmake -DGSK_RUN=<exe> -DGSK_VALIDATE=<exe> -DGSK_BENCH=<exe>
#         -DFAKE_MATLAB_OK=<exe> -DFAKE_MATLAB_FAIL=<exe>
#         -DPROJECT_ROOT=<dir> -DWORK_DIR=<dir> -P gsk_run_exit_codes.cmake
#
# No MATLAB is needed. The fake MATLAB stubs (fake_matlab.cpp) exit 0 or 1
# without writing anything; the summary tables that gsk_run then verifies are
# written here beforehand. Everything is written under WORK_DIR (in the build
# tree), never the source tree.
#
# Cases that make gsk_run actually launch "MATLAB" go through std::system and
# its cmd.exe quoting, so they run on Windows hosts only; the dry-run, parsing,
# gsk_validate and gsk_bench cases run everywhere.

cmake_minimum_required(VERSION 3.20)

foreach(var GSK_RUN GSK_VALIDATE GSK_BENCH FAKE_MATLAB_OK FAKE_MATLAB_FAIL PROJECT_ROOT WORK_DIR)
    if(NOT DEFINED ${var})
        message(FATAL_ERROR "gsk_run_exit_codes.cmake: -D${var}=... is required")
    endif()
endforeach()

set(W "${WORK_DIR}")
file(REMOVE_RECURSE "${W}")
file(MAKE_DIRECTORY "${W}/elsewhere")

set(failures 0)
set(hdr "Function,Best,Median,Mean,Worst,SD\n")

# expect_rc(<label> <expected_rc> <cwd> <command...>): runs the command and
# records a failure when its exit code differs. The combined stdout+stderr is
# left in LAST_OUTPUT for content checks.
function(expect_rc label expected cwd)
    execute_process(COMMAND ${ARGN}
                    WORKING_DIRECTORY "${cwd}"
                    RESULT_VARIABLE rc
                    OUTPUT_VARIABLE out
                    ERROR_VARIABLE err)
    set(LAST_OUTPUT "${out}${err}" PARENT_SCOPE)
    if(NOT "${rc}" STREQUAL "${expected}")
        message(SEND_ERROR "FAIL: ${label}: exit ${rc}, expected ${expected}\n${out}${err}")
        math(EXPR n "${failures} + 1")
        set(failures ${n} PARENT_SCOPE)
    else()
        message(STATUS "ok: ${label} (exit ${rc})")
    endif()
endfunction()

# expect_output(<label> <needle>): LAST_OUTPUT must contain the needle.
function(expect_output label needle)
    string(FIND "${LAST_OUTPUT}" "${needle}" pos)
    if(pos EQUAL -1)
        message(SEND_ERROR "FAIL: ${label}: output lacks '${needle}'\n${LAST_OUTPUT}")
        math(EXPR n "${failures} + 1")
        set(failures ${n} PARENT_SCOPE)
    else()
        message(STATUS "ok: ${label}")
    endif()
endfunction()

# --- Fixtures -------------------------------------------------------------
# Reference: F1 mean 1e-7 (non-trivial), F3 mean 700.
file(WRITE "${W}/refs/cec2017/gsk/gsk_cec2017_D10.csv"
     "${hdr}F1,0,0,1e-7,0,0\nF3,500,600,700,800,100\n")
# Clean run, and a run whose negative best error is a hard failure even at a
# reduced budget (sign check).
set(ok_row "1,1e-8,2e-8,3e-8,4e-8,1e-8\n")
set(dev_row "1,-5,2e-8,3e-8,4e-8,1e-8\n")
file(WRITE "${W}/ok/gsk/cec2017/summary/gsk_cec2017_D10.csv" "${hdr}${ok_row}")
file(WRITE "${W}/dev/gsk/cec2017/summary/gsk_cec2017_D10.csv" "${hdr}${dev_row}")
# "MATLAB" exited 0 but left no per-dimension summary table behind.
file(WRITE "${W}/empty/gsk/cec2017/summary/per_run.csv" "optimizer,suite,function\n")

# Multi-optimizer config with relative roots (resolved under --root, not the
# working directory): gsk deviates, agsk (no reference table) is clean.
file(WRITE "${W}/multi.yml"
     "optimizers: [gsk, agsk]\nsuite: cec2017\nfunctions: [1]\ndimensions: [10]\nruns: 1\n"
     "output_root: multi\nreference_root: refs\n")
file(WRITE "${W}/multi/gsk/cec2017/summary/gsk_cec2017_D10.csv" "${hdr}${dev_row}")
file(WRITE "${W}/multi/agsk/cec2017/summary/agsk_cec2017_D10.csv" "${hdr}${ok_row}")

set(cli --root "${W}" --optimizer gsk --suite cec2017 --dimension 10 --function 1 --runs 1)

# --- gsk_run: strict flag parsing (exit 2 = bad value, 1 = bad request) ----
expect_rc("gsk_run --function 1,3 rejected" 2 "${W}"
          "${GSK_RUN}" --root "${W}" --optimizer gsk --suite cec2017 --dimension 10 --function 1,3 --dry-run)
expect_output("--function message names the flag" "--function expects one integer")
expect_rc("gsk_run --runs 2.9 rejected" 2 "${W}" "${GSK_RUN}" ${cli} --runs 2.9 --dry-run)
expect_rc("gsk_run --function abc rejected" 2 "${W}"
          "${GSK_RUN}" --root "${W}" --optimizer gsk --suite cec2017 --function abc --dry-run)
expect_rc("gsk_run --seed -5 rejected (no 2^64 wrap)" 2 "${W}" "${GSK_RUN}" ${cli} --seed -5 --dry-run)
expect_rc("gsk_run --max-evaluations -7 rejected" 2 "${W}"
          "${GSK_RUN}" ${cli} --max-evaluations -7 --dry-run)
expect_rc("gsk_run --config + --runs 0 rejected" 1 "${W}"
          "${GSK_RUN}" --config "${PROJECT_ROOT}/configs/smoke.yml" --root "${PROJECT_ROOT}" --runs 0 --dry-run)
expect_rc("gsk_run --np-init 11 rejected" 2 "${W}" "${GSK_RUN}" ${cli} --np-init 11 --dry-run)
expect_output("--np-init message names the flag" "--np-init must be 0")
expect_rc("gsk_run --np-init abc rejected" 2 "${W}" "${GSK_RUN}" ${cli} --np-init abc --dry-run)
expect_rc("gsk_run --min-pop-size 10 rejected" 2 "${W}" "${GSK_RUN}" ${cli} --min-pop-size 10 --dry-run)
expect_output("--min-pop-size message names the flag" "--min-pop-size must be 0")

# --- gsk_run: dry-run command construction ---------------------------------
expect_rc("gsk_run dry-run with an apostrophe in the output path" 0 "${W}"
          "${GSK_RUN}" ${cli} --output "${W}/O'Brien" --dry-run)
expect_output("apostrophe doubled in the MATLAB literal" "O''Brien/gsk/cec2017'")
expect_rc("gsk_run multi-optimizer dry-run from another directory" 0 "${W}/elsewhere"
          "${GSK_RUN}" --config "${W}/multi.yml" --root "${W}" --dry-run)
expect_output("relative output_root resolves under --root" "${W}/multi/gsk/cec2017")
expect_output("dry-run lists every optimizer" "${W}/multi/agsk/cec2017")
expect_rc("gsk_run dry-run with population overrides" 0 "${W}"
          "${GSK_RUN}" ${cli} --np-init 100 --min-pop-size 20 --dry-run)
expect_output("--np-init reaches run_experiment" ",'np_init',100")
expect_output("--min-pop-size reaches run_experiment" ",'min_pop_size',20")

# --- gsk_run: verdict -> exit code (needs std::system -> cmd.exe) -----------
if(CMAKE_HOST_WIN32)
    file(TO_NATIVE_PATH "${FAKE_MATLAB_OK}" fake_ok)
    file(TO_NATIVE_PATH "${FAKE_MATLAB_FAIL}" fake_fail)
    set(refs --reference "${W}/refs")
    expect_rc("gsk_run CONSISTENT -> 0" 0 "${W}"
              "${GSK_RUN}" ${cli} ${refs} --matlab "${fake_ok}" --output "${W}/ok")
    expect_output("verdict printed" "-> CONSISTENT (reduced budget)")
    expect_rc("gsk_run DEVIATES -> 3" 3 "${W}"
              "${GSK_RUN}" ${cli} ${refs} --matlab "${fake_ok}" --output "${W}/dev")
    expect_output("DEVIATES reported" "DEVIATES from the reference")
    if(NOT EXISTS "${W}/dev/gsk/cec2017/summary/verification.json")
        message(SEND_ERROR "FAIL: DEVIATES run wrote no verification.json")
        math(EXPR failures "${failures} + 1")
    endif()
    expect_rc("gsk_run with no summary produced -> 3" 3 "${W}"
              "${GSK_RUN}" ${cli} ${refs} --matlab "${fake_ok}" --output "${W}/empty")
    expect_rc("gsk_run MATLAB failure -> 1" 1 "${W}"
              "${GSK_RUN}" ${cli} ${refs} --matlab "${fake_fail}" --output "${W}/ok")
    expect_rc("gsk_run verification error -> 2" 2 "${W}"
              "${GSK_RUN}" ${cli} --reference "${W}/no_such_refs" --matlab "${fake_ok}" --output "${W}/ok")
    expect_rc("gsk_run --no-verify skips the verdict" 0 "${W}"
              "${GSK_RUN}" ${cli} ${refs} --matlab "${fake_ok}" --output "${W}/dev" --no-verify)

    # Multi-optimizer: gsk DEVIATES but agsk still runs and is verified.
    expect_rc("gsk_run multi-optimizer config -> first nonzero (3)" 3 "${W}/elsewhere"
              "${GSK_RUN}" --config "${W}/multi.yml" --root "${W}" --matlab "${fake_ok}")
    expect_output("later optimizer still verified" "agsk on cec2017: CONSISTENT (exit 0)")
    expect_output("failing optimizer named" "not clean: gsk (DEVIATES)")
    if(NOT EXISTS "${W}/multi/agsk/cec2017/summary/verification.json")
        message(SEND_ERROR "FAIL: agsk was not verified after gsk DEVIATES")
        math(EXPR failures "${failures} + 1")
    endif()
else()
    message(STATUS "skipped: gsk_run MATLAB-launch cases (Windows-only std::system quoting)")
endif()

# --- gsk_validate ----------------------------------------------------------
expect_rc("gsk_validate --full alone prints usage" 1 "${W}" "${GSK_VALIDATE}" --full)
expect_rc("gsk_validate --root alone prints usage" 1 "${W}" "${GSK_VALIDATE}" --root .)
# Reduced-budget run with a gross F3 gap: without a flag the protocol comes
# from environment.json (reduced -> informational), --full forces strict.
file(WRITE "${W}/vred/gsk/cec2017/summary/environment.json"
     "{\n  \"runs\": 1,\n  \"max_nfes_override\": 3000\n}\n")
file(WRITE "${W}/vred/gsk/cec2017/summary/gsk_cec2017_D10.csv" "${hdr}3,5e2,6e2,9e12,9e12,1e2\n")
expect_rc("gsk_validate --verify reads environment.json (reduced)" 0 "${W}"
          "${GSK_VALIDATE}" --verify "${W}/vred/gsk/cec2017" "${W}/refs")
expect_output("protocol source reported" "protocol from: ${W}/vred/gsk/cec2017/summary/environment.json")
expect_rc("gsk_validate --verify --full overrides environment.json" 3 "${W}"
          "${GSK_VALIDATE}" --verify "${W}/vred/gsk/cec2017" "${W}/refs" --full)
# README demo layout (output_dir results/demo): the suite comes from the file
# name, so the cec2017 sign check still fires instead of a vacuous CONSISTENT.
file(WRITE "${W}/results/demo/summary/gsk_cec2017_D10.csv" "${hdr}${dev_row}")
expect_rc("gsk_validate --verify on a non-standard output_dir" 3 "${W}"
          "${GSK_VALIDATE}" --verify "${W}/results/demo" "${W}/refs")
expect_output("demo layout judged as gsk on cec2017" "Verification: gsk on cec2017 -> DEVIATES")

# --- gsk_bench -------------------------------------------------------------
expect_rc("gsk_bench --iterations 0 rejected" 1 "${W}"
          "${GSK_BENCH}" --root "${PROJECT_ROOT}" --iterations 0)
expect_rc("gsk_bench --iterations -5 rejected" 1 "${W}"
          "${GSK_BENCH}" --root "${PROJECT_ROOT}" --iterations -5)
expect_rc("gsk_bench unopenable --csv rejected" 1 "${W}"
          "${GSK_BENCH}" --root "${PROJECT_ROOT}" --iterations 1 --cell cec2017 1 10
          --csv "${W}/no_such_dir/out.csv")

if(failures GREATER 0)
    message(FATAL_ERROR "gsk_run_exit_codes: ${failures} failure(s)")
endif()
message(STATUS "gsk_run_exit_codes passed")
