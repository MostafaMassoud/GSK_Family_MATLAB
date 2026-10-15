# GSK Family (MATLAB)

Seven Gaining-Sharing Knowledge (GSK) optimization algorithms in MATLAB (GSK,
AGSK, APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK), run on the standard CEC
benchmark suites (CEC2011, CEC2013, CEC2013-LSGO, CEC2017, CEC2020). The
benchmark functions are C++ ports that MATLAB calls through a small compiled
bridge (a MEX file).

## Start here

- **[RUNBOOK.md](RUNBOOK.md)** (or open **RUNBOOK.html** in a web browser):
  prerequisites, one-time setup, your first run, and running in parallel.
- **[gsk_family/README.md](gsk_family/README.md)**: what the project contains,
  in more detail.

## What is where

```text
README.md, RUNBOOK.md, RUNBOOK.html   start here
run_all_cec2011.m ... run_all_cec2020.m   launchers: open one in MATLAB, press Run
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

Code author: Mostafa Masoud.
