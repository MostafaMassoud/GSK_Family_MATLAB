# Deep Documentation Review And Upgrade Prompt

> **What this page is.** A paste-ready prompt for deeply upgrading the
> `gsk_family` documentation into a publication-quality research handbook.
> **For.** Maintainers, researchers, graduate students, and LLM/coding agents
> assigned to improve explanation depth. **Prerequisites.** The reviewer has
> access to the repository and can read MATLAB, C++, CMake, PowerShell, and the
> existing Markdown docs. **After using it** the docs should be richer, more
> teachable, better cross-linked, and still faithful to the current code.

This is the MATLAB/C++ counterpart of the Python project's
`DOCS_DEEP_REVIEW_PROMPT.md`. Use it when the goal is not merely to remove stale
text, but to make the documentation genuinely useful as a user guide, developer
guide, researcher handbook, implementation reference, and reproducibility
manual.

Run [documentation_review_prompt.md](documentation_review_prompt.md) after this
prompt as the final consistency gate.

---

```text
You are a coordinated panel of experts improving the documentation for the
hybrid MATLAB + C++ `gsk_family` project. Your expertise covers GSK-family
metaheuristics, CEC benchmark protocols, MATLAB runners, C++20/MEX integration,
reproducible experiments, numerical examples, scientific writing, and static
documentation sites.

Mission:

Transform the documentation into a professional, publication-quality research
package. A new researcher should be able to understand the system, reproduce
experiments, modify algorithms safely, rebuild the C++/MEX components, inspect
outputs, validate results, and extend the code without reading source first.

Do not change algorithm behavior, benchmark behavior, seed behavior, output
schemas, result folders, or evaluation budgets as part of this documentation
pass. If source code and docs disagree, verify the code and update docs unless
you have proven a code bug.

===============================================================================
1. CURRENT FACTS THAT DOCUMENTATION MUST PRESERVE
===============================================================================

Repository and build:

- Project root for source docs: `<workspace>\gsk_family`.
- Root MATLAB launchers live one level up: `run_all_cec2011.m`,
  `run_all_cec2013.m`, `run_all_cec2013lsgo.m`, `run_all_cec2017.m`,
  `run_all_cec2020.m`.
- CEC C++ ports and data live under `benchmarks/cec_suite_cpp`.
- C++ helper library, CLIs, tests, and MEX source live under
  `benchmarks/cec_suite_cpp/cec_tools`.
- Imported reference results live under `benchmarks/cec_reference_results` and
  are read-only evidence.
- Documentation source lives under `docs/`; generated HTML lives under
  `docs/html/` and is rebuilt by `scripts/build_docs.ps1`.
- `docs/index.html` is a hand-maintained redirect into `docs/html/index.html`.
- Do not add Python tooling to this project.

Algorithms:

- `gsk`, `agsk`, `apgsk`, `fdb-agsk`, `atmals-gsk`, `egsk`, `dt-gsk` (seven).
- Display names: GSK, AGSK, APGSK, FDB-AGSK, ATMALS-GSK, eGSK, DT-GSK
  (Dimension-Tiered GSK; its behavior and validation are summarized in
  `src/optimizers/dt-gsk/README.md`).
- Hyphenated slugs are user-facing identifiers. Underscore names are MATLAB
  function/file names where required.

Suites:

- CEC2011, CEC2013, CEC2013LSGO, CEC2017, CEC2020, plus internal `sphere`.
- CEC2017 F2 is implemented but excluded from default comparisons.
- CEC2013 and CEC2013LSGO are separate suites.
- CEC2011 and CEC2013LSGO use native dimensions (`dimensions=0`).

Reproducibility:

- Default `base_seed = 20240620`.
- `run_experiment.m` and root `run_all_cec*.m` launchers default to unified
  seed policy and requested `threefry`.
- `gsk_run`, shipped YAML configs, and `scripts/run_all.ps1` default to
  reference seed policy and requested `threefry`.
- Unified seed:

  seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1

- Unified mode is optimizer-independent and draws one fair-start `X0` in the
  runner for every algorithm except DT-GSK, which samples its own NP = 5*D
  population (documented fair-start exception).
- Reference mode uses:
  - `base_seed + 9973*func + run - 1` for GSK, eGSK, ATMALS-GSK.
  - `D*func*run` for AGSK, APGSK, FDB-AGSK.
  - the unified seed + `threefry` for DT-GSK, which is unified-only under
    every seed policy.
- `write_graphs=false` by default: numeric curves and generation logs are still
  written; PNG convergence graphs are opt-in.
- `overwrite=false` resumes/appends; `overwrite=true` moves the old active tree
  to `_overwrite_archive/<suite>_<timestamp>/` and starts clean.

Output:

- Root launchers write to `results/_run_all/<optimizer>/<suite>/`.
- `gsk_run` writes to `results/<optimizer>/<suite>/` unless overridden.
- Standard layout: `summary/`, `curves/`, optional `curves/graphs/`, `gen_logs/`.
- Generated results must never overwrite `benchmarks/cec_reference_results`.

===============================================================================
2. QUALITY BAR
===============================================================================

Every documentation page should be:

- Accurate: every factual claim can be traced to code, config, or imported
  evidence.
- Layered: start with orientation, then intuition, then precise mechanics, then
  edge cases.
- Beginner-friendly: define terms before using them.
- Research-grade: include equations, variable definitions, assumptions,
  limitations, and references to provenance where appropriate.
- Concrete: include numerical examples with intermediate values.
- Visual: use Mermaid diagrams for workflows, state transitions, data flow, and
  optimizer update cycles when diagrams reduce cognitive load.
- Skimmable: short paragraphs, tables for structured facts, clear headings,
  callouts, warnings, tips, FAQs, and troubleshooting links.
- Consistent: same names, same paths, same seed formulas, same suite facts, same
  result schema everywhere.

Math rendering rule:

- Use plain text code fences or inline backticks for formulas unless the current
  docs build demonstrably supports MathJax/LaTeX. Do not introduce syntax that
  renders poorly in `docs/html/`.

Mermaid rule:

- Use stable node IDs with quoted labels: `cfg["Configuration"]`.
- Avoid bare quoted nodes and unquoted labels containing spaces/punctuation.
- Every diagram must be checked against the current implementation.

===============================================================================
3. PHASED WORK
===============================================================================

Phase A - Inventory and gap table:

Produce a table for every source Markdown file:

  file | audience | current depth 1-5 | examples | diagrams | math | stale items | needed upgrade

Review at least:

- README.md, SKILL.md, LICENSES.md, CHANGELOG.md
- docs/index.md
- docs/getting-started/*.md
- docs/reference/*.md
- docs/algorithms/*.md
- docs/development/*.md
- docs/research/*.md
- docs/prompts/*.md
- configs/README.md
- scripts/README.md

Phase B - Numerical examples:

Add or improve worked examples for:

1. Population initialization: `X = lb + U .* (ub - lb)`.
2. Unified seed calculation with a concrete `(base_seed, dim, func, run)`.
3. Reference seed calculation for both seed families.
4. Fair-start `X0` sharing across optimizers.
5. Junior/senior gained-sharing updates in GSK.
6. AGSK/APGSK parameter adaptation and population reduction.
7. FDB-AGSK fitness-distance balance ranking.
8. ATMALS-GSK two-mode adaptive local search.
9. eGSK parameter/control logic and fmincon-dependent refinement.
10. DT-GSK dimension tiers (which mechanisms switch on at D >= 20, 50, 100).
11. Bounds repair and why it preserves feasibility.
12. CEC checkpoint logs and convergence curves.
13. Summary statistics, including the standard-deviation convention actually
    used by the code.

Each example must show inputs, formula, intermediate values, and final output.

Phase C - Algorithm guide depth:

For each algorithm page, verify or add:

- intuition;
- mathematical formulation;
- pseudocode;
- parameters;
- worked example;
- update cycle;
- bounds, budget, and determinism;
- complexity;
- when to use;
- source and validation notes.

Do not invent equations. Cite code or provenance notes when uncertain.

Phase D - Workflow and reproducibility depth:

Improve explanations of:

- root `run_all_cec*.m` launchers;
- direct `run_experiment(...)`;
- `gsk_run`, `gsk_list`, `gsk_validate`;
- YAML configs;
- CMake build;
- MEX build;
- docs build;
- result folders;
- overwrite vs resume;
- graph CSVs vs optional PNG rendering;
- serial vs process-pool `parfor`;
- reference vs unified seed mode.

Phase E - Diagrams:

Add or refresh diagrams for:

- project architecture;
- MATLAB runner to C++ MEX bridge;
- experiment lifecycle;
- seed policy;
- overwrite/resume output lifecycle;
- result artifact flow;
- CEC validation flow;
- per-optimizer update cycle;
- testing/build pipeline.

Phase F - Research and extension guidance:

Add clear guidance for:

- designing a fair cross-family experiment;
- reproducing a publication-style reference comparison;
- interpreting raw objectives on CEC2011/CEC2013LSGO;
- deciding when to enable `write_graphs`;
- safely adding an optimizer;
- safely adding a benchmark suite;
- profiling without changing RNG order.

Phase G - Rebuild and final gate:

After source Markdown edits:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_docs.ps1 -Clean

Then run the strongest feasible checks:

  rg -n "reference_gsk_code|cec_benchmarks|[c]ompatibility flag|[d]oes not delete" docs README.md configs scripts src benchmarks
  rg -n "write_graphs|overwrite|_overwrite_archive|cec_suite_cpp" docs README.md configs scripts
  matlab -batch "cd('src/tests'); run_matlab_smoke_tests"

If a command is too expensive, state what was skipped and why.

===============================================================================
4. FINAL DELIVERABLE
===============================================================================

Return:

1. Summary of documentation improvements.
2. Files changed.
3. New examples/diagrams added.
4. Stale or misleading text removed.
5. Source facts verified from code.
6. Commands run and results.
7. Remaining gaps and recommended next documentation work.
```
