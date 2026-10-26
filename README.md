# GSK Family (MATLAB)

Seven Gaining-Sharing Knowledge (GSK) optimization algorithms in MATLAB (GSK,
AGSK, APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK), run on the standard CEC
benchmark suites (CEC2011, CEC2013, CEC2013-LSGO, CEC2017, CEC2020). The
benchmark functions are C++ ports that MATLAB calls through a small compiled
bridge (a MEX file).

## Start here

- **[RUNBOOK.md](RUNBOOK.md)** (or open **RUNBOOK.html** in a web browser):
  prerequisites, one-time setup, your first run, full campaigns, running in
  parallel, and convergence figures and statistics.
- **[NEW_VARIANT_GUIDE.md](NEW_VARIANT_GUIDE.md)** (or **NEW_VARIANT_GUIDE.html**):
  build your own GSK variant, run it next to the family, and get the figures
  and tables for a paper.
- **[gsk_family/README.md](gsk_family/README.md)**: what the project contains,
  in more detail.

## What is where

```text
README.md, RUNBOOK.md, RUNBOOK.html   start here
NEW_VARIANT_GUIDE.md, .html           build and compare your own GSK variant
run_all_cec2011.m ... run_all_cec2020.m   launchers: open one in MATLAB, press Run
run_compare_algorithms.m              convergence figures and statistics, press Run
algorithms.ini                        aliases: algorithms with changed settings
build.txt                             build commands (also in RUNBOOK.md)
gsk_family/                           the project: code, benchmarks, docs, tests
```

The full documentation is a website built from `gsk_family/docs/`: run
`gsk_family/scripts/build_docs.ps1`, then open `gsk_family/docs/html/index.html`.

## License and citation

The project is distributed under GPL-3.0-or-later. Third-party parts (the CEC
benchmark code and the reference algorithms) keep their own terms; the full
record is in [gsk_family/LICENSES.md](gsk_family/LICENSES.md). To cite the
project, use [gsk_family/CITATION.cff](gsk_family/CITATION.cff).

## Author

**Mostafa Elsayed Ahmed Masoud**, PhD Candidate in Operations Research,
Department of Operations Research, Faculty of Graduate Studies for Statistical
Research, Cairo University, Giza 12613, Egypt.
ORCID: <https://orcid.org/0009-0003-8415-2158> · Email:
<moustafa.masoud@gmail.com>

Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud. The notice covers this
framework's own code, tools and documentation. Each algorithm it runs (GSK,
AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, DT-GSK) and each benchmark suite
remains the work of its original authors; licensing and provenance are in
[gsk_family/LICENSES.md](gsk_family/LICENSES.md). Please keep this notice
and the author attribution.

**How to cite.** If you use this framework in a paper or thesis, please cite
it (see [gsk_family/CITATION.cff](gsk_family/CITATION.cff)), together with
the paper of every algorithm you use (listed in
[gsk_family/LICENSES.md](gsk_family/LICENSES.md)). For DT-GSK: Masoud, M. E.
A.; Roshdy, H. S. M.; Mohamed, A. W. "DT-GSK: Dimension-Tiered Adaptive
Configuration Selection and Deterministic Refinement for Gaining-Sharing
Knowledge-Based Optimization Algorithm." *Algorithms*, 19(9), 769, 2026.
DOI: [10.3390/a19090769](https://doi.org/10.3390/a19090769).
