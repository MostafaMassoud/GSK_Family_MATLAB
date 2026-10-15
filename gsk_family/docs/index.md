# Documentation Index

> **What this page is.** The map of all project documentation - grouped by
> folder, with goal-based reading paths to get you to the right page fast.
> **Who it is for.** Everyone; start here.

A verified hybrid **MATLAB + C++** toolkit for the Gaining-Sharing Knowledge
(GSK) optimizer family on five CEC benchmark suites. The CEC benchmark functions
are standalone C++20 ports (no MATLAB/R/MEX needed to evaluate them); the
seven optimizers are MATLAB implementations faithful to their reference sources
(six MATLAB reference releases, plus DT-GSK ported from its reference
implementation); and every experiment run is automatically checked against the
published reference results.

This site is generated from the Markdown sources in `docs/` by
`scripts/build_docs.ps1`. To browse the rendered site, open
`docs/html/index.html` in a web browser.

## Reading paths

Not sure where to start? Pick the goal that fits:

- **Just run it.** [Runbook](../../RUNBOOK.md) -> [Tutorial](getting-started/tutorial.md) -> [User Guide](getting-started/user_guide.md) -> [Command Reference](getting-started/command_reference.md).
- **Understand the algorithms.** [Explainer](getting-started/explainer.md) -> [GSK](algorithms/gsk.md) -> the variants ([AGSK](algorithms/agsk.md), [APGSK](algorithms/apgsk.md), [FDB-AGSK](algorithms/fdb-agsk.md), [ATMALS-GSK](algorithms/atmals-gsk.md), [eGSK](algorithms/egsk.md), [DT-GSK](algorithms/dt-gsk.md)) -> [Numerical Examples](research/numerical_examples.md).
- **Reproduce or validate results.** [Researcher Handbook](research/researcher_handbook.md) -> [Reproducibility](research/reproducibility.md) -> [Validation Report](research/validation_report.md).
- **Contribute code.** [Code Reading Guide](development/code_reading_guide.md) -> [Developer Guide](development/developer_guide.md) -> [Extension Guide](development/extension_guide.md) -> [Contributor Guide](development/contributor_guide.md).
- **Look something up.** [Configuration](getting-started/configuration.md), [MATLAB Optimizer Interface](reference/matlab_interface.md), [Result Schema](reference/result_schema.md), [Glossary](reference/glossary.md), [Diagrams](reference/diagrams.md), [C++ API (Doxygen)](api/index.html) (in the built site).

## Getting Started - `getting-started/`

- [Runbook](../../RUNBOOK.md): the beginner guide - prerequisites, your first run step by step, and parallel runs in MATLAB.
- [Explainer](getting-started/explainer.md): plain-language overview for any reader (no GSK/CEC/C++/MATLAB background needed).
- [Tutorial](getting-started/tutorial.md): one worked experiment end to end - build, test, validate, run, read output, interpret.
- [User Guide](getting-started/user_guide.md): install, list capabilities, run experiments, validate output, inspect results.
- [Command Reference](getting-started/command_reference.md): step-by-step run commands for every algorithm, from both the MATLAB IDE and Windows Terminal.
- [Configuration](getting-started/configuration.md): the YAML config subset, CLI overrides, and safe output paths.
- [Troubleshooting](getting-started/troubleshooting.md): common build, MEX-bridge, benchmark, and result issues.

## Reference - `reference/`

- [Architecture](reference/architecture.md): the layered MATLAB/C++ design and execution model.
- [MATLAB Optimizer Interface](reference/matlab_interface.md): the problem/options/result struct contract for optimizers.
- [C++ API (how-to)](reference/api.md): how to generate and read the Doxygen C++ API reference.
- [Module Dependencies](reference/module_dependencies.md): dependency direction between the MATLAB and C++ layers.
- [Workflows](reference/workflows.md): end-to-end execution paths from CLI/MATLAB to artifacts.
- [Result Schema](reference/result_schema.md): every file and column written below `results/`.
- [Seed Policy](reference/seed_policy.md): deterministic seed formulas, RNG generators, and fair starts.
- [Benchmark Protocol](reference/benchmark_protocol.md): the five suites, their functions, dimensions, budgets, and statistics.
- [Benchmark Mapping](reference/benchmark_mapping.md): how the MATLAB runner reaches the C++ benchmarks through the MEX bridge.
- [Diagrams](reference/diagrams.md): architecture, workflow, seed, validation, and testing flowcharts.
- [Project Structure](reference/project_structure.md): directory and file ownership map.
- [Provenance Inventory](reference/reference_inventory.md): provenance for every ported source and reference asset.
- [Porting Notes](reference/porting_notes.md): per-suite fidelity record and preserved reference quirks.
- [CEC2011 Port Plan](reference/cec2011_port_plan.md): the MATLAB-to-C++ porting dossier for the CEC2011 suite.
- [Glossary](reference/glossary.md): project terminology.
- [License and Provenance](../LICENSES.md): licensing and component provenance.

## Algorithm Guides - `algorithms/`

- [GSK](algorithms/gsk.md)
- [AGSK](algorithms/agsk.md)
- [APGSK](algorithms/apgsk.md)
- [FDB-AGSK](algorithms/fdb-agsk.md)
- [ATMALS-GSK](algorithms/atmals-gsk.md)
- [eGSK](algorithms/egsk.md)
- [DT-GSK](algorithms/dt-gsk.md) (port record and validation: `src/optimizers/dt-gsk/README.md`)

## Development - `development/`

- [Developer Guide](development/developer_guide.md): day-to-day development guide.
- [Contributor Guide](development/contributor_guide.md): contribution rules and evidence policy.
- [Maintenance Guide](development/maintenance_guide.md): routine upkeep.
- [Extension Guide](development/extension_guide.md): adding an optimizer, suite, artifact, or CLI command.
- [Code Reading Guide](development/code_reading_guide.md): how to inspect the codebase.

## Prompts - `prompts/`

Copy-paste LLM prompts for reviewing and maintaining the repository (each is a self-contained block):

- [Full Project Review Prompt](prompts/REVIEW_PROMPT.md): whole-repository production review for MATLAB, C++, CMake, MEX, runners, configs, tests, performance, and docs.
- [Deep Documentation Review Prompt](prompts/DOCS_DEEP_REVIEW_PROMPT.md): publication-quality documentation expansion with examples, diagrams, and researcher guidance.
- [Documentation Review Prompt](prompts/documentation_review_prompt.md): final documentation consistency, stale-reference, generated-HTML, and text-quality gate.
- [Inline Documentation Review Prompt](prompts/INLINE_DOCUMENTATION_REVIEW_PROMPT.md): MATLAB help text, `%` comments, C++ Doxygen, script comments, config comments, and test comments.
- [Documentation Parity Prompt](prompts/documentation_parity_prompt.md): keep these docs mirrored with the sibling project's docs structure while preserving MATLAB/C++ facts.
- [Legacy LLM Review Prompt](prompts/llm_review_prompt.md): compatibility entry for the earlier broad review prompt.

## Research - `research/`

- [Researcher Handbook](research/researcher_handbook.md): reproducible experiment procedure and interpretation.
- [Reproducibility](research/reproducibility.md): environment, seeds, deterministic settings, and the serial/parallel baseline.
- [Performance](research/performance.md): parallel execution, native MEX, profiling, and measurement status.
- [Validation Report](research/validation_report.md): current parity evidence and remaining validation work.
- [Numerical Examples](research/numerical_examples.md): small worked examples of init, seeds, bounds, fitness, statistics, and scheduling.

## C++ API

- [C++ API reference](api/index.html) (Doxygen; available after building the site with
  `scripts/build_docs.ps1`). The how-to page is [C++ API (how-to)](reference/api.md).
