// Fake MATLAB executable for the gsk_run exit-code test
// (tests/cli/gsk_run_exit_codes.cmake). It ignores the -batch command and
// exits with FAKE_MATLAB_RC, a compile definition: 0 for the "MATLAB
// succeeded" stub, nonzero for the "MATLAB failed" stub. This lets the test
// run gsk_run's post-run checks and exit-code mapping without MATLAB, using
// summary tables the test script writes first.

#ifndef FAKE_MATLAB_RC
#define FAKE_MATLAB_RC 0
#endif

int main() {
    return FAKE_MATLAB_RC;
}
