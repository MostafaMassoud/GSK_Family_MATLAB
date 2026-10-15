# Contributor Guide

> **Orientation.** This page is the checklist for *submitting* a change: branch,
> edit, rebuild, update docs, run the gate, open a pull request. It is for
> anyone landing a contribution to `gsk_family`, large or small. After reading
> it you will know exactly which builds and tests the project expects to pass
> before review, and which changes require a documentation update. For the
> mechanics of the code itself, see the [Developer Guide](developer_guide.md);
> to add a whole new optimizer, suite, artifact, or CLI command, see the
> [Extension Guide](extension_guide.md).

The overriding rule: contributions must preserve reference-compatible behavior
and the reference evidence trail. "Reference" here means the upstream MATLAB or
CEC implementation each component ports (for DT-GSK, the Python DT-GSK
reference implementation v2.46); "evidence trail" means the imported
reference-result tables under `benchmarks/cec_reference_results` that generated
output is checked against. Preserved quirks are deliberate - read
[`porting_notes.md`](../reference/porting_notes.md) before changing port
behavior.

## Contribution Workflow

The end-to-end path from idea to pull request. Steps are ordered - do not push
before the local gate (step 4) is green.

1. Work on a branch. Keep commits small and focused, each with a clear message
   that explains the change. Stay inside the language boundary: MATLAB GSK code
   under `src/`, C++ CEC code under `benchmarks/`, no Python anywhere.
2. Update documentation alongside the code it describes. For example, an
   optimizer behavior change updates its help block and the relevant page under
   `docs/`.
3. Rebuild whatever the change touched. Rebuild the C++ tree after any
   C++/CMake/CLI change; rebuild the MEX bridge after any CEC-suite-source or
   `mex_bridge/` change; rebuild `docs/html` after any doc edit.

   ```powershell
   cmake --build build -j
   powershell -File scripts\build_mex_bridge.ps1   # only if CEC sources / bridge changed
   ```

4. Run the local gate before pushing:

   ```powershell
   ctest --test-dir build --output-on-failure
   matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
   ```

   After any docs, help-block, or header change, also regenerate the HTML site
   and commit it:

   ```powershell
   powershell -File scripts\build_docs.ps1 -Clean
   ```

5. Open a pull request once the gate is green.

## Before Changing Code

A short orientation pass so your change fits existing behavior and provenance.

1. Read the relevant reference document: [architecture](../reference/architecture.md)
   for the layer map, [`matlab_interface.md`](../reference/matlab_interface.md)
   for the optimizer contract, and
   [`porting_notes.md`](../reference/porting_notes.md) for the per-suite
   fidelity record and preserved quirks.
2. Check [`LICENSES.md`](../../LICENSES.md) for source provenance before
   touching any ported file's attribution or behavior.
3. Confirm the target file belongs to the correct language area (MATLAB under
   `src/`, C++ under `benchmarks/`).
4. Run the focused tests for the area you plan to change (see the
   [Developer Guide testing section](developer_guide.md#testing)).

## Before Submitting Changes

This is the minimum verification beyond the workflow gate above. Run both test
surfaces in full:

```powershell
ctest --test-dir build --output-on-failure
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
```

For runner, bridge, or benchmark changes, also run at least one end-to-end CLI
command. The bundled `configs/smoke.yml` runs one optimizer on one function at a
tiny budget, so it finishes in seconds:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

Every `gsk_run` auto-compares the run to the same optimizer's published
reference table and writes a `CONSISTENT`/`DEVIATES` verdict; `gsk_run` exits
nonzero on `DEVIATES`. Do not opt out (`--no-verify`) to make a submission pass.

## Documentation Expectations

Docs live next to the behavior they describe, and the Markdown under `docs/` is
the source of truth (the HTML site is generated). Update documentation in the
same pull request when you change:

- optimizer behavior;
- benchmark protocol metadata (budgets, targets, dimensions);
- config fields;
- output files or their schema;
- seed policy or RNG selection;
- validation thresholds or the verdict logic;
- CLI commands;
- parity decisions or a newly preserved quirk.

When you add a new page, link it from the docs index and register it in
`scripts/build_docs.ps1` so the HTML site stays complete, then rebuild with
`powershell -File scripts\build_docs.ps1 -Clean`.

## Evidence Policy

The separation between imported and generated data is what makes parity claims
trustworthy. The imported reference tables under
`benchmarks/cec_reference_results/` are source evidence: treat them as read-only
and never edit them to make a run pass. The curated benchmark-side
`curves/`, `curves/graphs/`, and `gen_logs/` assets there are preserved
reference material, not stale output. Generated experiment output belongs under
`results/` only, so the two never mix. The C++ ground-truth vectors under
`benchmarks/cec_suite_cpp/cec_tools/tests/data/` are the regression oracle for the
ports - they are checked, not adjusted. See
[`porting_notes.md`](../reference/porting_notes.md) for how this evidence is
used per suite.
