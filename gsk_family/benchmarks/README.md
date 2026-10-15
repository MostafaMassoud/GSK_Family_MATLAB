# Benchmarks

All CEC-related artifacts live here.

```text
cec_reference_results/  imported reference tables plus curated convergence assets
cec_suite_cpp/              CEC benchmark C++ ports, input data, and C++ support tools
  cec_tools/            C++ CEC helper library, CLI tools, MEX bridge, and tests
```

Do not place CEC input files or CEC benchmark source under the root `data`
folder, under `src`, or under `src/benchmark/cec*`. Keep those artifacts inside
`benchmarks/cec_suite_cpp`. Keep CEC C++ support code inside
`benchmarks/cec_suite_cpp/cec_tools`.

Do not add Python code, Python wrappers, or generated Cython bindings under
`benchmarks`.

## Researcher mental model

| Folder | Contains | Mutability |
|---|---|---|
| `cec_suite_cpp/<suite>/src` | C++ source code for benchmark functions | Edit only when fixing or extending a benchmark port; rebuild and run CTest. |
| `cec_suite_cpp/<suite>/input_data` | Shift, rotation, shuffle, and converted problem data | Treat as benchmark data; do not edit during optimizer experiments. |
| `cec_suite_cpp/cec_tools` | Shared C++ APIs, CLIs, MEX bridge, tests | Edit for benchmark integration, validation, or tooling work. |
| `cec_reference_results` | Imported published optimizer result tables plus curated `curves/`, `curves/graphs/`, and `gen_logs/` convergence assets; for DT-GSK, tables imported from its Python reference implementation, with per-run `evidence/` and `PROVENANCE.md` under `cec2017/dt-gsk/` | Read-only evidence for comparison, verification, and future convergence-graph generation. |
| `../results` | Generated experiment outputs | Append/resume only; do not use as input reference data. |

Example: if a CEC2017 run (`run_all.ps1 -Configs configs\all_cec2017.yml`)
reports a result discrepancy, first inspect
`../results/<optimizer>/cec2017/summary/environment.json` and
`seed_schedule.csv`. Do not edit `cec_reference_results` to make the comparison
look better; its aggregate tables and curated convergence assets are the
baseline evidence being tested against. Fresh run outputs still belong under
`../results`, not under `benchmarks`, unless a future curation step explicitly
promotes them into the reference archive with documented provenance.
