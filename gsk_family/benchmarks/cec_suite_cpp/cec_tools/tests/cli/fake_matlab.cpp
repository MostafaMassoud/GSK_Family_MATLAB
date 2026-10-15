// Stand-in for the MATLAB executable in the gsk_run exit-code test
// (tests/cli/gsk_run_exit_codes.cmake). It ignores the -batch command and
// exits with FAKE_MATLAB_RC (a compile definition: 0 for the "MATLAB
// succeeded" stub, nonzero for the "MATLAB failed" stub), so gsk_run's
// post-run verification and exit-code mapping run without MATLAB against
// summary tables the test script writes beforehand.

#ifndef FAKE_MATLAB_RC
#define FAKE_MATLAB_RC 0
#endif

int main() {
    return FAKE_MATLAB_RC;
}
