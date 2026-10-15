cmake_minimum_required(VERSION 3.20)

project(gsk_family
    VERSION 1.0.0
    DESCRIPTION "CEC benchmark tooling for MATLAB GSK-family experiments"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(GNUInstallDirs)

option(GSKCEC_BUILD_TESTS "Build unit tests" ON)
option(GSKCEC_WERROR "Treat compiler warnings as errors (used in CI)" OFF)
option(GSKCEC_NATIVE "Optimize for the build host (-O3 -march=native); OFF by default for portability" OFF)

if(MINGW)
    # Link statically so the binaries need no libstdc++/libgcc/winpthread DLLs.
    add_link_options(-static)
endif()

# gskcec_apply_flags(target): adds the shared warning and optimization flags
# to one target; every target (library, CLIs, tests) calls it. GSKCEC_NATIVE
# must never change results: the tests check the same tolerances with it on,
# so any difference is a build bug, not an accepted trade-off.
function(gskcec_apply_flags target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive-)
        if(GSKCEC_WERROR)
            target_compile_options(${target} PRIVATE /WX)
        endif()
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
        if(GSKCEC_WERROR)
            target_compile_options(${target} PRIVATE -Werror)
        endif()
    endif()
    if(GSKCEC_NATIVE AND NOT MSVC)
        # -ffp-contract=off is required: -march=native enables FMA, and the
        # default -ffp-contract=fast would fuse multiply-adds, shift results by
        # a few ULP and break the exact ground-truth matches (the 1e-12
        # CEC2011/CEC2013 tests catch this). -O3 does not reorder FP math
        # without -ffast-math, which is never used. The native build must stay
        # bit-identical to the default build.
        target_compile_options(${target} PRIVATE -O3 -march=native -funroll-loops -ffp-contract=off)
    elseif(GSKCEC_NATIVE AND MSVC)
        # /fp:precise (the default) keeps IEEE semantics; /arch:AVX2 only
        # widens vectorization. Never use /fp:fast here.
        target_compile_options(${target} PRIVATE /O2 /arch:AVX2 /fp:precise)
    endif()
endfunction()

add_library(gskcec
    benchmarks/cec_suite_cpp/cec_tools/src/benchmark/data_loading.cpp
    benchmarks/cec_suite_cpp/cec_tools/src/benchmark/factory.cpp
    benchmarks/cec_suite_cpp/cec_tools/src/benchmark/reference_results.cpp
    benchmarks/cec_suite_cpp/cec_tools/src/experiment/config.cpp
    benchmarks/cec_suite_cpp/cec_tools/src/experiment/comparison.cpp
    benchmarks/cec_suite_cpp/cec2011/src/cec2011_problem.cpp
    benchmarks/cec_suite_cpp/cec2011/src/cec2011_problems_a.cpp
    benchmarks/cec_suite_cpp/cec2011/src/cec2011_problems_b.cpp
    benchmarks/cec_suite_cpp/cec2011/src/cec2011_problems_c.cpp
    benchmarks/cec_suite_cpp/cec2013/src/cec2013_problem.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/Benchmarks.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F1.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F2.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F3.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F4.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F5.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F6.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F7.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F8.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F9.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F10.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F11.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F12.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F13.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F14.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/F15.cpp
    benchmarks/cec_suite_cpp/cec2013lsgo/src/cec2013lsgo_problem.cpp
    benchmarks/cec_suite_cpp/cec2017/src/cec2017_problem.cpp
    benchmarks/cec_suite_cpp/cec2020/src/cec2020_problem.cpp
)

target_include_directories(gskcec
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/benchmarks/cec_suite_cpp/cec_tools/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/benchmarks/cec_suite_cpp/cec2011/src
)

target_compile_features(gskcec PUBLIC cxx_std_20)
gskcec_apply_flags(gskcec)

foreach(cli gsk_list gsk_validate gsk_run gsk_bench)
    add_executable(${cli} benchmarks/cec_suite_cpp/cec_tools/src/cli/${cli}.cpp)
    target_link_libraries(${cli} PRIVATE gskcec)
    gskcec_apply_flags(${cli})
endforeach()

if(GSKCEC_BUILD_TESTS)
    enable_testing()

    # gskcec_add_test(name source [args...]): builds a test and registers it
    # with CTest. Suite/data tests get the project root as argv[1], so nothing
    # depends on the current working directory.
    function(gskcec_add_test name source)
        add_executable(${name} ${source})
        target_link_libraries(${name} PRIVATE gskcec)
        gskcec_apply_flags(${name})
        add_test(NAME ${name} COMMAND ${name} ${ARGN})
    endfunction()

    gskcec_add_test(gskcec_core_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/core_tests.cpp)
    gskcec_add_test(gskcec_reference_results_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/reference_results_tests.cpp)
    gskcec_add_test(gskcec_experiment_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/experiment_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2011_wpa_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2011_wpa_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2011_wpb_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2011_wpb_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2011_wpc_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2011_wpc_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2011_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2011_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2013_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2013_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2013lsgo_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2013lsgo_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2017_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2017_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})
    gskcec_add_test(gskcec_cec2020_tests benchmarks/cec_suite_cpp/cec_tools/tests/unit/cec2020_tests.cpp ${CMAKE_CURRENT_SOURCE_DIR})

    # The WP tests include the internal CEC2011 header directly.
    target_include_directories(gskcec_cec2011_wpa_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/benchmarks/cec_suite_cpp/cec2011/src)
    target_include_directories(gskcec_cec2011_wpb_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/benchmarks/cec_suite_cpp/cec2011/src)
    target_include_directories(gskcec_cec2011_wpc_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/benchmarks/cec_suite_cpp/cec2011/src)

    # Runs gsk_bench with a tiny iteration count so it stays a real test; the
    # timings are not checked (see docs/research/performance.md).
    add_test(NAME gskcec_bench_smoke
             COMMAND gsk_bench --root ${CMAKE_CURRENT_SOURCE_DIR} --iterations 50)

    # CLI exit-code test: gsk_run verdict -> exit status (0 / 1 MATLAB failure
    # / 2 verification error / 3 DEVIATES), strict flag parsing, multi-optimizer
    # configs, gsk_validate --verify protocol detection and gsk_bench argument
    # checks. Stub executables stand in for MATLAB, so no MATLAB licence is
    # needed. The script writes only under the build tree.
    add_executable(gskcec_fake_matlab_ok benchmarks/cec_suite_cpp/cec_tools/tests/cli/fake_matlab.cpp)
    add_executable(gskcec_fake_matlab_fail benchmarks/cec_suite_cpp/cec_tools/tests/cli/fake_matlab.cpp)
    target_compile_definitions(gskcec_fake_matlab_fail PRIVATE FAKE_MATLAB_RC=1)
    gskcec_apply_flags(gskcec_fake_matlab_ok)
    gskcec_apply_flags(gskcec_fake_matlab_fail)
    add_test(NAME gskcec_cli_exit_codes
             COMMAND ${CMAKE_COMMAND}
                 -DGSK_RUN=$<TARGET_FILE:gsk_run>
                 -DGSK_VALIDATE=$<TARGET_FILE:gsk_validate>
                 -DGSK_BENCH=$<TARGET_FILE:gsk_bench>
                 -DFAKE_MATLAB_OK=$<TARGET_FILE:gskcec_fake_matlab_ok>
                 -DFAKE_MATLAB_FAIL=$<TARGET_FILE:gskcec_fake_matlab_fail>
                 -DPROJECT_ROOT=${CMAKE_CURRENT_SOURCE_DIR}
                 -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/cli_exit_codes
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/benchmarks/cec_suite_cpp/cec_tools/tests/cli/gsk_run_exit_codes.cmake)
endif()

# Install and export: `cmake --install <build> --prefix <dir>` installs the
# CLIs, the static library and the public headers. Other CMake projects can
# then call find_package(gskcec) and link gskcec::gskcec. The package config
# file only includes the exported targets, because the library has no external
# link dependencies to find.
install(TARGETS gskcec gsk_list gsk_validate gsk_run gsk_bench
        EXPORT gskcecTargets
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(DIRECTORY benchmarks/cec_suite_cpp/cec_tools/include/gskcec
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(EXPORT gskcecTargets
        NAMESPACE gskcec::
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/gskcec)

include(CMakePackageConfigHelpers)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/gskcecConfig.cmake
     "include(\"\${CMAKE_CURRENT_LIST_DIR}/gskcecTargets.cmake\")\n")
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/gskcecConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion)
install(FILES
        ${CMAKE_CURRENT_BINARY_DIR}/gskcecConfig.cmake
        ${CMAKE_CURRENT_BINARY_DIR}/gskcecConfigVersion.cmake
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/gskcec)
