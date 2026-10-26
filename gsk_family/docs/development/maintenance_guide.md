# Maintenance Guide

> **Orientation.** This page is for the maintainer keeping a healthy checkout
> over time: periodic health checks, toolchain bumps, and care of the reference
> evidence. It is not about writing features - for that see the
> [Developer Guide](developer_guide.md) and
> [Extension Guide](extension_guide.md). After reading it you will know which
> commands to run on a schedule, what to verify when the toolchain changes, and
> how to record new reference evidence. The CLI tools used below
> (`gsk_list`, `gsk_validate`, `gsk_run`) are built C++ executables under
> `build/`.

## Regular Checks

A quick recurring pass to catch breakage early. Build the C++ tree, run both
test surfaces, confirm the registries are intact, and run a tiny end-to-end
experiment.

```powershell
cmake --build build -j
ctest --test-dir build --output-on-failure
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"

build\gsk_list.exe --optimizers
build\gsk_list.exe --benchmarks
build\gsk_list.exe --references benchmarks\cec_reference_results
build\gsk_run.exe --config configs\smoke.yml --root .
```

`gsk_list --optimizers` should list all seven optimizers (`dt-gsk` last);
`--benchmarks` should list all five suites with their functions and dimensions;
`--references` should load the imported tables (currently 165 files / 1411 rows)
and confirm the reference data is reachable. `ctest` should report 13 suites and
the MATLAB smoke runner 16 tests. Use the per-suite smoke validators to confirm each port still matches
its ground truth:

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
build\gsk_validate.exe --suite cec2020 --smoke
build\gsk_validate.exe --suite cec2013 --smoke
build\gsk_validate.exe --suite cec2013 --against saved_vectors
build\gsk_validate.exe --suite cec2013lsgo --smoke
build\gsk_validate.exe --suite cec2011 --smoke
```

After generating benchmark evidence, use `gsk_validate --compare` to score a
results directory against the imported reference tables:

```powershell
build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
```

## Toolchain and Dependency Updates

This project has no package dependencies - its "dependencies" are the host
toolchain (the WinLibs MinGW-w64 compiler, CMake, and MATLAB). A compiler,
standard-library, or MATLAB version change can shift floating-point results, so
treat every bump as a parity event. When you change the g++/CMake toolchain or
the MATLAB version:

1. Do a clean rebuild of the C++ tree
   (`cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release`) and
   rebuild the MEX bridge (`scripts\build_mex_bridge.ps1`).
2. Run all `ctest` suites and the MATLAB smoke tests.
3. Run at least one smoke experiment per optimizer and inspect convergence
   traces for non-finite values.
4. Re-run `gsk_validate --suite <s> --smoke` for every suite and confirm each
   still matches ground truth at its documented tolerance.
5. Record any compiler, math-library, or MATLAB behavior change in
   [`porting_notes.md`](../reference/porting_notes.md). The current toolchain of
   record (WinLibs GCC, `-std=c++20 -static`; MATLAB R2025b) is documented in
   its Toolchain Record section.

Never weaken a tolerance to absorb a toolchain shift; investigate the source of
the deviation first.

## Reference Evidence

The imported reference tables are the ground truth for parity, so their
provenance must be traceable. Keep `benchmarks/cec_reference_results/`
read-only, and keep the C++ ground-truth vectors under
`benchmarks/cec_suite_cpp/cec_tools/tests/data/` as the port regression oracle.
If new external evidence is added, document in
[`porting_notes.md`](../reference/porting_notes.md) and the reference inventory:

- source project, paper, or run;
- date generated or imported;
- optimizer, suite, dimensions, and functions;
- budget and run count;
- any format-conversion steps.

Per-run evidence that comes with a reference (for example
`cec2017/dt-gsk/evidence/per_run.csv`, `seed_schedule.csv`, and the run's JSON
metadata) goes in an `evidence/` subfolder, which the table loader ignores, with
a `PROVENANCE.md` beside the tables recording sources and commits, as for
`cec2017/dt-gsk/`.

The imported-reference loader already tolerates `-`, `nan`, `n/a`, and `na` as
missing statistics (for example the AGSK CEC2020 D=5 table reports `N/A` for
functions 6-7); record such gaps rather than fabricating values.

## Documentation Upkeep

Keep the Markdown sources and their generated HTML in step. The Markdown under
`docs/` is the source of truth; `docs/html` is rebuildable and must never be
hand-edited. When a new document is added, link it from the docs index and add
it to `scripts/build_docs.ps1`; after any Markdown, help-block, header, or
Doxygen change, rebuild the site:

```powershell
powershell -File scripts\build_docs.ps1 -Clean
```

## Long-Term Maintenance

Slower-moving upkeep that keeps the evidence base broad and current.

- Keep the reference-comparison coverage current as new campaigns complete.
- Rebuild the C++ tree, the MEX bridge, and the HTML docs after their respective
  source changes; a stale `build\*.exe` or stale `build\mex\gskcec_eval.mexw64`
  can mask current behavior.
- Keep generated outputs under `results/` separate from imported references and
  curated benchmark-side convergence assets.
- Keep the two CEC2013 suites (`cec2013`, `cec2013lsgo`) separate; never merge
  them.
- Expand imported reference-comparison tables for `cec2013`, `cec2013lsgo`, and
  `cec2020`, which are currently thinner than `cec2011` and `cec2017` (beyond
  `gsk` on `cec2013` and `agsk` on `cec2020`, only `dt-gsk` has tables there).
- When a DT-GSK campaign completes, record its `compare_reference_runs.m`
  summary in `src/optimizers/dt-gsk/README.md`, the one place that holds the
  DT-GSK validation numbers.
