# Changelog

All notable changes to `gsk_family` are recorded here. The format follows
Keep a Changelog; this project uses semantic versioning.

## [Unreleased]

### Documentation
- Synchronized Markdown build instructions to distinguish C++ CLI rebuilds from
  MATLAB MEX bridge rebuilds.
- Updated CTest examples to use `ctest --test-dir build --output-on-failure` for
  clearer failure diagnostics.

### Changed
- Console result tables now keep resume/stale-seed notices out of the table body
  and print them afterward as compact `Resume notes`.

## [1.0.0] - 2026-06-13

First public, publication-grade release.

### Benchmarks (standalone C++20, no MATLAB/R/MEX/Python at runtime)
- Ported all five CEC suites and validated each against ground truth from the
  original reference implementations:
  - CEC2017 (30 functions) - max relative deviation 4.8e-15 vs the original MEX.
  - CEC2020 (10 functions, internal mapping preserved) - 2.8e-16.
  - CEC2013 (standard 28-function suite, converted from the R package; runs
    without R) - analytic + optimum-at-shift + self-regression at 0.
  - CEC2013LSGO (15 large-scale functions; Cython glue removed) - bit-exact vs
    the untouched reference.
  - CEC2011 (22 real-world problems; `.mat` assets converted to text) - WP-A/WP-B
    bit-exact, WP-C (MGA-DSM trajectories) ~1.9e-13, including a behavioural
    `ode45` replica for the ODE problems.

### Optimizers (MATLAB, faithful to the reference)
- GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK under `src/optimizers`, with the
  shared helpers, runners, and the deterministic seed policy. GSK/AGSK/APGSK
  reproduce the reference algorithm bodies bit-identically.

### Tooling
- `gsk_list`, `gsk_validate`, `gsk_run` CLIs; the strict YAML-subset config
  parser; the imported-reference loader; the results-vs-reference comparison.
- Optional `gskcec_eval` MEX bridge so MATLAB optimizers evaluate the exact C++
  ports (verified against ground truth at 0 deviation).
- `gsk_bench` micro-benchmark harness for the C++ hot paths.

### Quality, performance, docs (publication preparation)
- **Automatic post-run verification (Mandate c):** every `gsk_run` compares the
  result against the same optimizer's published table and writes a
  `CONSISTENT`/`DEVIATES` verdict (`verification.json`); exposed as
  `gsk_validate --verify`. Exits nonzero on `DEVIATES`.
- **Folder clarity (Mandate b):** imported reference tables live in
  `benchmarks/cec_reference_results`, while CEC ports, input data, and nested
  C++ tools live in `benchmarks/cec_suite_cpp`; `configs/`, `scripts/` READMEs; a
  folder-structure decision guide; `.gitignore`.
- **Code readability (Mandate a):** `docs/development/code_reading_guide.md` guided tour;
  every ported file cites its reference source.
- **Engineering:** warnings-as-errors clean (GCC 16, `-Werror`); `.clang-format`,
  `.clang-tidy`; CMake `install`/`export` rules; `GSKCEC_NATIVE` and
  `GSKCEC_WERROR` options; GitHub Actions CI (Linux GCC/Clang + Windows MSVC,
  sanitizers, language-contract checks).
- **Performance:** `GSKCEC_NATIVE` gives a numerically-identical ~15-36% speedup
  on the heavy configurations (`-ffp-contract=off` keeps it bit-exact); baseline
  and method in `docs/research/performance.md`.
- **Fixed a latent test bug:** `core_tests`/`reference_results_tests` used raw
  `assert`, a no-op under Release/NDEBUG; replaced with always-on checks so the
  tests really run in Release.
- **Documentation:** plain-language `explainer.md`, end-to-end `tutorial.md`,
  `glossary.md`, Doxygen config (`docs/Doxyfile`, `docs/reference/api.md`), and the full
  `docs/` reference set.
- **Metadata and licensing:** `CITATION.cff`, `codemeta.json`, and a
  GPL-3.0-or-later license resolution (forced by the CEC2013 derivative) with a
  full component-by-component analysis in `LICENSES.md`.

### Known follow-ups (human / compute)
- Optimizer-vs-reference statistics in the paper are pipeline-generated
  placeholders pending a full-protocol experiment run.
- Author ORCID/affiliation, repository DOI, and Zenodo archival are placeholders
  for the author to complete.
- License conclusion (GPL-3.0-or-later) is recommended pending the original
  authors' confirmation.
