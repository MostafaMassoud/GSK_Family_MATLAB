# CEC2011 C++ Source

Standalone C++20 port of the 22 CEC2011 real-world benchmark problems.

The implementation is split by work package:

```text
cec2011_problem.cpp      public dispatch and suite metadata
cec2011_problems_a.cpp   problems 1-8 and 10
cec2011_problems_b.cpp   problems 9 and 11-20
cec2011_problems_c.cpp   problems 21-22 and committed text-asset loaders
cec2011_detail.hpp       shared internal helpers
```

Keep this folder C++-only. Input data belongs in `../input_data/`; validation
probes and expected values belong in `benchmarks/cec_suite_cpp/cec_tools/tests/data/`.
