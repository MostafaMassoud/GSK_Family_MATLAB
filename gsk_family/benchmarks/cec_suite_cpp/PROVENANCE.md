# CEC Suite Provenance

Files in this directory are committed ports, input data, and provenance copies
for the supported CEC benchmark suites.

Imported mapping:

| Local path | Reference source |
|---|---|
| `cec2017/src/` | `cec_suite_cpp/cec2017/cec17_func.cpp`, `readme.txt` |
| `cec2017/input_data/` | `cec_suite_cpp/cec2017/input_data/` |
| `cec2020/src/` | `cec_suite_cpp/cec2020/cec20_func.cpp` |
| `cec2020/input_data/` | `cec_suite_cpp/cec2020/input_data/` |
| `cec2013/src/` | current standalone C++ CEC2013 port |
| `cec2013/input_data/` | CEC2013 R package `inst/extdata/` |
| `cec2013lsgo/src/` | `cec_suite_cpp/cec2013lsgo/cec2013lsgo/*.cpp`, `*.h`, excluding generated language-binding files |
| `cec2013lsgo/input_data/` | `cec_suite_cpp/cec2013lsgo/cec2013lsgo/cdatafiles/` |
| `cec2011/src/` | current standalone C++ CEC2011 port |
| `cec2011/input_data/` | committed CEC2011 text assets and suite data |

Excluded from this staging copy:

- MEX binaries such as `*.mexw64`.
- PDF reports.
- Wrappers for CEC2013LSGO in other languages.
- Generated binding files such as `cec2013.cpp`.
- CEC2013 C/R source copies not needed by the current standalone C++ port.
- CEC2011 MATLAB source copies not needed by the current standalone C++ port.
- Build-system helper files unless needed by the standalone C++ port.
