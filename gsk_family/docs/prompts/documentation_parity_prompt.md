# Documentation Parity Prompt (keep the MATLAB docs mirrored with the sibling project's docs)

Use this prompt when asking an LLM agent to AUDIT, MAINTAIN, REBUILD, or EXTEND
the `gsk_family` documentation set so it stays mirrored to the sibling
project's docs (`<sibling-project>\docs`) in
structure, page coverage, navigation, and style - while every fact stays correct
for this MATLAB + C++ project.

The INITIAL migration is DONE. The MATLAB docs already live in the sibling
project's five-folder taxonomy (`getting-started/`, `reference/`, `development/`,
`research/`, `algorithms/`) plus a MATLAB-side `prompts/` folder and a
`docs/index.html` redirect. So treat this as a parity MAINTENANCE-and-rebuild
prompt: it should keep the existing mirror true as either project drifts, and it
must still be usable to redo the mirror from scratch or to extend it when the
sibling side adds a page. Most pages exist, so the default verb is now ALIGN or
VERIFY, not MOVE or NEW.

This prompt is aligned with the current repository layout:

- The sibling project's docs use five themed folders plus root `index.md` and
  `LICENSES.md`, and keep their LLM prompts in `docs/prompt/`. The MATLAB docs
  use the plural `docs/prompts/` folder (this is a deliberate MATLAB-side
  divergence) and a `docs/index.html` that redirects into `docs/html/`.
- The MATLAB docs site is built by `scripts/build_docs.ps1` (PowerShell + Pandoc
  3.8+ primary + a built-in fallback renderer used when Pandoc is absent or older
  than 3.8 + Doxygen). The sibling project's own docs build script is NOT
  ported - only its OUTPUT features are matched.
- Facts (seed policy, budgets, paths, formulas) come from the MATLAB code and
  the existing MATLAB docs, never from the sibling project's wording.
- Generated folders (`build/`, `results/`, `docs/html/`) are not source of truth
  and are never hand-edited.

Copy everything inside the block below into the agent.

```text
# Expert Documentation Parity Prompt (maintenance + rebuild)
# Goal: keep gsk_family/docs mirrored to <sibling-project>/docs,
#       with every fact correct for the MATLAB + C++ project.

You are working directly in (the TARGET, and the source of truth for FACTS):

  <repo>\gsk_family

The STRUCTURAL TEMPLATE to mirror (source of truth for layout/style ONLY):

  <sibling-project>\docs

Act as a multidisciplinary documentation board with expertise in:

- technical documentation and information architecture
- MATLAB documentation and help text
- C++20 / Doxygen API documentation
- GSK-family metaheuristics and CEC benchmark protocols
- reproducible research, RNG, and seed-policy design
- research software engineering
- PowerShell build tooling and static-site generation with Pandoc
- Markdown writing, technical editing, B2-level English
- accessibility and eye-friendly reading design
- developer onboarding

Mission:
The MATLAB docs are ALREADY reorganized into the sibling project's five-folder
taxonomy (plus a MATLAB-side prompts/ folder). Your job is to KEEP them mirrored:
audit the existing set against the sibling template, fix every drift in
STRUCTURE, PAGE COVERAGE, NAVIGATION, and STYLE, and prove that every FACT,
command, path, formula, and code citation is correct for THIS MATLAB + C++
project. If the sibling side has added or renamed a page, mirror that change
here. If a page is missing or off-template, repair it. Preserve all algorithm,
benchmark, seed, evaluation-budget, and result-schema behavior. This is a
documentation + docs-build-script task only - do not change any code behavior.

## Two Sources Of Truth (read this twice)

1. STRUCTURE / TAXONOMY / STYLE come from the sibling project's docs (the
   template): the five-folder layout, the set of pages, the per-page section
   skeletons, the mandatory opening callout, the goal-based index, the diagrams
   gallery, the numerical-examples hub, and the grouped sidebar.

2. FACTS come from the MATLAB code and the existing MATLAB docs (the ground
   truth). NEVER copy a statement from the sibling project's docs that is false
   for this project. Translate every sibling-specific detail to its MATLAB/C++
   equivalent (see "Sibling -> MATLAB Translation Rules"). When the two disagree
   on a fact, the MATLAB CODE wins; cite the .m or .cpp line as file.m:line.

When the template and the target conflict on STRUCTURE, the template wins and you
change the MATLAB docs to match (unless the difference is an explicit MATLAB-side
divergence listed under "Intentional MATLAB-Side Divergences"). When they
conflict on a FACT, the MATLAB code wins and you change the prose.

## First Read These Files

Template (sibling project's docs - for STRUCTURE and FEATURES only, never for
facts):
1. <sibling-project>\docs\index.md
2. that project's docs\getting-started\*, reference\*, development\*, research\*,
   and algorithms\* pages. Note the folder taxonomy, every page's section
   skeleton, the opening-callout dialects, and where the sibling side keeps its
   LLM prompts (in docs\prompt\, e.g. documentation_parity_prompt). Build a list
   of sibling pages and diff it against the MATLAB tree below: any sibling page
   with no MATLAB counterpart is a parity gap to mirror (unless it is a
   sibling-only page such as its docs-build-script walkthrough).
3. that project's own docs build script - study only the FEATURES it
   produces (grouped sidebar, per-page TOC, nav filter, mermaid, callouts,
   copy buttons, light/dark toggle), then IGNORE it as an implementation. You
   keep the PowerShell build. Do NOT port it.

Target and ground truth (MATLAB):
4. README.md, RUNBOOK.md (top-level beginner runbook), SKILL.md, LICENSES.md
   (LICENSES.md is root-level; there is NO docs\LICENSES.md - the build pulls
   the root file)
5. docs\index.md, docs\index.html (the redirect), and every page under
   docs\getting-started\, docs\reference\, docs\algorithms\, docs\development\,
   docs\research\, docs\prompts\
6. scripts\build_docs.ps1  (the build script you will UPDATE; PowerShell only)
7. docs\prompts\REVIEW_PROMPT.md, docs\prompts\DOCS_DEEP_REVIEW_PROMPT.md,
   docs\prompts\documentation_review_prompt.md,
   docs\prompts\INLINE_DOCUMENTATION_REVIEW_PROMPT.md,
   docs\prompts\documentation_parity_prompt.md, and
   docs\prompts\llm_review_prompt.md
   (the prompt-family style, language rules, and preservation rules to keep)
8. Code anchors for facts (verify, do not assume - line numbers below are the
   current anchors; re-confirm them, code moves):
   - src\runners\run_experiment.m   (base seed, policy switch, generator
     selection, fair-start X0, F2 exclusion, ATMALS reporting exception)
   - src\runners\get_cec_seed.m     (the unified seed formula)
   - src\runners\derive_run_seed.m  (the native/derived fallback path)
   - src\common\gsk_set_rng.m, src\runners\choose_cec_rng_generator.m
     (threefry/twister/mcg16807 stream selection and the threefry fallback)
   - src\runners\gskcec_make_problem.m  (per-suite evaluation budgets)
   - the seven src\optimizers\<slug>\<stem>_optimize.m entry points (DT-GSK
     adds dt_gsk_config.m and dt_gsk_graph.m; its README.md is the
     authoritative behavior and validation summary)
   - benchmarks\cec_suite_cpp\cec_tools\src\cli\gsk_run.cpp
   - benchmarks\cec_suite_cpp\cec_tools\src\experiment\comparison.cpp
   - benchmarks\cec_suite_cpp\cec_tools\src\mex_bridge\gskcec_eval_mex.cpp

## Repository Contract And Non-Negotiable Preservation Rules

- MATLAB and C++ only (no other languages or generated bindings) in code;
  the scripts\ helpers are MATLAB or PowerShell, and the docs build is PowerShell.
  The site is built by scripts\build_docs.ps1 (PowerShell + Pandoc 3.8+ primary,
  a built-in fallback renderer Convert-MarkdownFallback used when Pandoc is
  absent or older than 3.8, and Doxygen for the C++ API). DO NOT port the
  sibling project's own docs build script. Mirror its OUTPUT features; keep the
  toolchain.
- Preserve reference behavior and documented quirks. Read
  reference\porting_notes.md before describing any benchmark; never "fix" a quirk
  in prose.
- Public optimizer slugs are hyphenated everywhere they are identifiers
  (atmals-gsk, fdb-agsk, dt-gsk); MATLAB function and file names use underscores
  (atmals_gsk_optimize.m, fdb_agsk_optimize.m, dt_gsk_optimize.m). Keep both
  forms correct.
- The two CEC2013 suites (cec2013, cec2013lsgo) are separate and never merged.
- SEED POLICY FACTS must be MATLAB-correct - verify against code, do not trust
  the sibling project's wording:
    * base_seed default = 20240620, centralized in run_experiment.m
      (run_experiment.m ~:56, also the parameter default ~:64).
    * The policy switch (pick_run_seed, run_experiment.m ~:1356) handles
      'reference' and 'unified' explicitly; the only other values
      check_seed_policy accepts, 'native' and 'derived', fall through to
      derive_run_seed, so they are ALIASES of that same fallback path, not two
      distinct policies. Say "reference, unified, and the native/derived fallback
      (aliases)" - do not imply native and derived behave differently.
    * unified seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run,
      2147483646) + 1  (get_cec_seed.m ~:35-39; the constant is MAX_SAFE_SEED =
      2147483646). It is optimizer-independent.
    * reference per-optimizer seeds (run_experiment.m ~:1356-1370): gsk, egsk, and
      atmals-gsk use base_seed + 9973*func + (run-1); agsk, apgsk, fdb-agsk use
      D*func*run. dt-gsk is unified-only (is_unified_only ~:1402): it gets the
      unified seed and 'threefry' under EVERY seed_policy, mirroring the
      reference implementation's UNIFIED_ONLY_OPTIMIZERS.
    * effective_rand_generator (run_experiment.m ~:1377-1400): dt-gsk always
      'threefry'; otherwise, under reference,
      agsk/apgsk/fdb-agsk/egsk/atmals-gsk use the legacy 'seed' stream (mcg16807)
      and gsk (plus any fallback) uses 'twister'; under unified the whole family
      resolves to threefry-or-twister; under native/derived the requested
      rand_generator is honored. gsk_set_rng.m maps 'threefry'->rng threefry
      (fallback twister on older MATLAB), 'twister'->rng twister, 'seed'->
      mcg16807 RandStream, 'state'->swb2712 RandStream.
    * Default policy DIFFERS by entry point: run_experiment(...) defaults to
      seed_policy='unified' + rand_generator='threefry' (run_experiment.m
      ~:70-71), and the root run_all_cec*.m launchers follow it; the gsk_run CLI,
      the shipped configs, and run_all.ps1 default to seed_policy='reference' +
      'threefry' (run_all.ps1 ~:15-19 defers to each config).
    * Fair-start X0 (unified only): the runner draws the NP=100 population once
      via make_unified_initial_population (run_experiment.m ~:1267), captures the
      post-initialization RNG state, and each optimizer restores it so the first
      random decision is identical across the six runner-X0 algorithms. DT-GSK
      is the documented exception (unified_initialization_enabled ~:1258): it
      samples its own NP = 5*D population and the runner draws no X0 for it.
- CEC2017 F2 is implemented and validated but excluded from the default sweep
  (run_experiment.m ~:180).
- ATMALS-GSK on CEC2017 is the single reporting exception: it reports
  abs(best_fitness - optimum) (curve_value, run_experiment.m ~:1230, and the
  uses_atmals_cec2017_reference_reporting guard ~:1299); every other case reports
  the signed best_fitness - optimum. The 1e-8 zero cutoff is applied uniformly
  across optimizers.
- Evaluation budgets (gskcec_make_problem.m ~:68-84): cec2017 and cec2013 =
  10000*D; cec2011 = 150000; cec2013lsgo = 3000000; cec2020 is a per-dimension
  ladder D5->50000, D10->1000000, D15->3000000, D20->10000000. State these
  identically wherever they appear.
- Wall-clock seeding is forbidden project-wide; every seed is recorded.
- Generated outputs (build/, results/, docs/html/) are not source of truth and
  are never hand-edited. docs\index.html is a hand-maintained redirect into
  docs\html\ and IS source (the build does not generate or overwrite it).

## Intentional MATLAB-Side Divergences (do NOT "fix" these toward the sibling project)

These are deliberate and must be preserved, not reconciled away:

- A sixth docs folder, docs\prompts\, holds the MATLAB prompt family:
  REVIEW_PROMPT, DOCS_DEEP_REVIEW_PROMPT, INLINE_DOCUMENTATION_REVIEW_PROMPT,
  llm_review_prompt, documentation_review_prompt, and documentation_parity_prompt.
  The sibling project keeps its prompt set under docs\prompt\. Keep the MATLAB
  prompts under docs\prompts\ and the sidebar "Prompts" group.
- docs\index.html is a meta-refresh redirect into docs\html\index.html; the
  sibling project has no such redirect. Keep it and keep it accurate (its
  fallback text lists the sidebar groups).
- The API tier is C++ Doxygen, not the sibling project's generated autodoc.
  reference\api.md is a Doxygen how-to and reference\matlab_interface.md is the
  MATLAB optimizer contract; together they replace the sibling project's
  auto-generated api\ tree.
- MATLAB-only pages with no sibling counterpart stay (see KEEP tags below).

## Target Documentation Tree (current state - mirror of the sibling taxonomy)

The folders and pages below ALREADY EXIST. Tags now mean:
  ALIGN  = page exists; re-check its sections against the template and rewrite
           any drift (this is the common case).
  VERIFY = page exists; confirm its FACTS against code and its links resolve, but
           it has no sibling section template to track (MATLAB-specific content).
  KEEP   = MATLAB-only page with no sibling equivalent; preserve it in place.
  NEW    = author from scratch (only if the sibling side adds a page and the
           MATLAB tree is missing the counterpart).
  REMOVE = delete only if the sibling template drops it AND nothing here needs it.

  docs/
    index.md                       ALIGN  (goal-based map; reading paths + folders)
    index.html                     VERIFY (redirect into html/index.html; keep the
                                          group list in its fallback text current)
    getting-started/
      explainer.md                 ALIGN
      tutorial.md                  ALIGN
      user_guide.md                ALIGN
      command_reference.md         VERIFY (Command Reference; MATLAB-specific)
      configuration.md             ALIGN  (YAML config subset + configs/README link)
      troubleshooting.md           VERIFY (MEX/build/validation failure catalogue)
      (RUNBOOK.md is at the repository root, one level above gsk_family
       (../RUNBOOK.md, with RUNBOOK.html beside it): the short beginner
       runbook - prerequisites, first run, parallel runs in MATLAB; VERIFY it;
       there is no docs/getting-started/RUNBOOK.md)
    reference/
      architecture.md              ALIGN
      matlab_interface.md          ALIGN  (MATLAB analogue of the sibling project's
                                          optimizer-interface page - keep name)
      api.md                       VERIFY (C++ Doxygen how-to; MATLAB-only flavor)
      module_dependencies.md       ALIGN  (MATLAB src/ + C++ layer dep direction)
      workflows.md                 ALIGN
      result_schema.md             ALIGN
      seed_policy.md               ALIGN
      benchmark_protocol.md        ALIGN
      benchmark_mapping.md         VERIFY (runner -> gskcec_eval MEX bridge -> C++;
                                          the D x NP column-major shape contract)
      diagrams.md                  ALIGN  (mermaid gallery; MATLAB/C++ reality)
      project_structure.md         ALIGN  (sibling name is project_structure)
      reference_inventory.md       KEEP   (MATLAB-only provenance inventory)
      porting_notes.md             KEEP   (MATLAB-only C++ port fidelity record)
      cec2011_port_plan.md         KEEP   (MATLAB-only port dossier)
      glossary.md                  ALIGN
      (LICENSES.md is root-level, built into this group as "License and
       Provenance"; there is no docs/LICENSES.md to edit)
    algorithms/
      gsk.md agsk.md apgsk.md fdb-agsk.md atmals-gsk.md egsk.md dt-gsk.md
                                   ALIGN all seven to the section skeleton below
                                   (DT-GSK's validation record stays in
                                   src/optimizers/dt-gsk/README.md; dt-gsk.md
                                   summarizes it and links there)
    development/
      developer_guide.md           ALIGN
      contributor_guide.md         ALIGN
      maintenance_guide.md         ALIGN
      extension_guide.md           ALIGN  (add-an-optimizer / suite / artifact / CLI)
      code_reading_guide.md        ALIGN
    prompts/                       (MATLAB-side plural folder; the sibling project
                                    keeps its prompt set in docs/prompt/)
      REVIEW_PROMPT.md             ALIGN  (canonical whole-project review prompt)
      DOCS_DEEP_REVIEW_PROMPT.md   ALIGN  (deep docs/pedagogy prompt)
      documentation_review_prompt.md  VERIFY (final consistency gate)
      INLINE_DOCUMENTATION_REVIEW_PROMPT.md  ALIGN (inline comment/help prompt)
      documentation_parity_prompt.md  VERIFY (this prompt)
      llm_review_prompt.md         KEEP   (legacy-compatible broad review prompt)
    research/
      researcher_handbook.md       ALIGN
      reproducibility.md           ALIGN
      performance.md               ALIGN  (sibling name is performance)
      validation_report.md         VERIFY (automated validation, verification.json
                                          verdicts; pull from porting_notes status)
      numerical_examples.md        ALIGN  (hand-checkable arithmetic hub; see below)

  Also present and kept where the build expects it: docs/Doxyfile (Doxygen
  config). The performance page documents how to GENERATE perf data with
  gsk_bench; it is not backed by committed CSVs.

## Per-Page Requirements

- EVERY page opens with one H1, then a mandatory blockquote callout. Match the
  sibling project's dialect exactly:
    * getting-started, reference, research, and algorithms pages use the
      four-field form:
      "> **What this is:** ... **For:** ... **Prerequisites:** ... **After reading:** ..."
    * development pages use the orientation form:
      "> **Orientation.** ..."
    * prompts pages: keep the MATLAB house style already in use (a one- or
      two-line "what this prompt is / when to use it" lead); these have no sibling
      template.

- index.md: a "## Reading paths" section with the five goal-based routes
  (Just run it; Understand the algorithms; Reproduce or validate results;
  Contribute code; Look something up), each an arrow chain of relative links;
  then one H2 per folder (Getting Started, Reference, Algorithm Guides,
  Development, Prompts, Research) listing its pages with one-line descriptions.
  Point readers to the rendered site at html/index.html. Mirror the sibling
  project's index structure, with the MATLAB pages and the extra Prompts group.

- index.html: keep it a zero-delay meta-refresh to html/index.html, and keep its
  visible fallback text listing the current sidebar groups (Getting Started,
  Reference, Algorithm Guides, Development, Prompts, Research, C++ API) and the
  build command. Update it if the group set changes.

- Algorithm pages: adopt the sibling project's section skeleton, in this exact
  order: Intuition; Mathematical formulation; Pseudocode; Parameters; Worked
  example; Update cycle (a mermaid flowchart TD of one generation); Bounds,
  budget, and determinism; Complexity; When to use; Source and validation. The
  MATLAB pages additionally carry a "Preserved reference quirks" H2 placed just
  before "Source and validation" - keep that section; it is where the documented
  reference-fidelity quirks live and has no harm to parity. GSK is the canonical
  base; the five variants document only their delta and cross-link gsk.md. The
  Parameters table has six columns:
  Option | Symbol | Default | Valid range | Meaning | Code, with the Code cell
  citing the MATLAB source as file.m:line. Keep the H1 em-dash form
  "SHORT - Long Name". The Worked example section MUST sit under a heading whose
  GitHub slug is "worked-example" (i.e. "## Worked example") so that
  ../algorithms/<opt>.md#worked-example resolves. End every algorithm page
  pointing back to ../research/validation_report.md and
  ../research/numerical_examples.md.

- reference/diagrams.md: a gallery of mermaid flowcharts, one per H2, covering at
  least: full project architecture; algorithm execution flow; benchmark
  evaluation pipeline (through the gskcec_eval MEX bridge); experiment lifecycle;
  configuration loading; seed and RNG flow; parallel (parfor) execution; logging
  and reporting; optimizer update cycle; validation workflow; testing workflow.
  Every diagram must depict the MATLAB + C++ reality (run_experiment.m, the MEX
  bridge, parfor, gsk_run.exe), not the sibling project's design.

- research/numerical_examples.md: the shared hand-checkable hub - small, tiny-D
  worked arithmetic for the mechanics every optimizer shares (population init =
  one rand(NP,D) draw; unified seed + fair start; midpoint bound repair; greedy
  selection; best-so-far tracking; sample standard deviation; the linear
  population-size reduction schedule for AGSK/APGSK/FDB-AGSK; parallel
  determinism). End with a table linking each algorithm page's #worked-example
  anchor for the per-variant distinctive operator.

- Use plain-text math only (no LaTeX or MathJax), inside fenced blocks tagged
  text, as both projects already do. Mermaid is the only rendered diagram tech.
  Use no raster images.

## Sibling -> MATLAB Translation Rules (apply to every page you port or audit)

- Commands: the sibling project's console scripts gsk-run / gsk-list /
  gsk-validate and its module-style gsk_family.cli.* invocations become the C++
  CLIs build\gsk_run.exe / gsk_list.exe / gsk_validate.exe AND the MATLAB
  launchers run_all_cec*.m plus direct run_experiment(...).
- Install and environment: the sibling project's package install, virtual
  environment, and JIT compiler become MATLAB R2025b + MinGW-w64
  g++ (C++20) + CMake; cmake --build build; scripts\build_mex_bridge.ps1; ctest.
- Code snippets: fences in the sibling project's language become matlab (or
  cpp), rewritten to the real MATLAB structs and C++ APIs - never left in the
  sibling's language.
- API tier: the sibling project's auto-generated api/ pages become the C++
  Doxygen api/ tree (reference/api.md + docs/Doxyfile) PLUS
  reference/matlab_interface.md for the MATLAB optimizer contract. Do NOT
  invent a sibling-style autodoc for MATLAB.
- Performance: the sibling project's JIT-compiled kernels, process pool, and
  warmup become MATLAB parfor + native MEX, plus the -ffp-contract=off fidelity
  note (use the performance.md facts).
- RNG: the sibling project's threefry_rng / reference_rng modules become
  gsk_set_rng.m, choose_cec_rng_generator.m, and the threefry RandStream (which
  controls rand, randi, AND randperm).
- Result paths: launcher output is results/_run_all/<optimizer>/<suite>; direct
  runs write results/<optimizer>/<suite> (match result_schema.md exactly).
- Reruns: overwrite=false resumes/appends; overwrite=true archives the previous
  active tree under _overwrite_archive/<suite>_<timestamp>/ and starts clean.
- Graphs: write_graphs=false is the default; numeric curves and gen_logs are
  still written, while PNG files under curves/graphs are opt-in.
- Mandatory callout dialect (above) is itself a translation rule: the sibling
  project's four-field and orientation callouts must appear on the MATLAB pages,
  reworded for MATLAB, not dropped.
- Keep the MATLAB seed story native: in THIS project the reference and
  native/derived paths ARE the platform-compatibility story, not an exception
  bolted onto a sibling-project default.

## Build Script Maintenance (scripts\build_docs.ps1) - PowerShell only

The script is already on the five-folder + prompts taxonomy. Keep it that way:

- $pages is an ordered array of hashtables, each
  @{ Src = "<repo-relative .md>"; Out = "<flat .html>"; Title = "..."; Group = "..." }.
  Out names are FLAT and folder-prefixed with an UNDERSCORE separator, e.g.
  docs/getting-started/tutorial.md -> getting-started_tutorial.html;
  docs/reference/seed_policy.md   -> reference_seed_policy.html;
  docs/algorithms/gsk.md          -> algorithms_gsk.html;
  docs/index.md                   -> index.html (no prefix);
  LICENSES.md (root)              -> LICENSES.html.
  When a doc page is added, renamed, or moved, add or update its $pages entry in
  the right Group, in reading order; the flat Out name keeps every page at the
  top of docs/html so cross-links need no ../ depth juggling.
- $srcToOut maps each absolute source path (lower-cased) to its Out name;
  $baseToOut maps each unique source basename to its Out name as a fallback.
  Both are derived from $pages, so adding a $pages entry updates them
  automatically - do not hand-edit the maps.
- Repair-Html rewrites every href="...something.md[#anchor]" in the rendered
  HTML: it resolves the link relative to the source directory, looks the absolute
  path up in $srcToOut, and on a miss falls back to the basename in $baseToOut;
  the #anchor is preserved. This is the basename-fallback rewriter that lets a
  link like ../algorithms/gsk.md#worked-example or
  ../reference/seed_policy.md resolve to the flat html name. Keep this two-tier
  behavior; if you add cross-folder links, no rewriter change is needed as long
  as the target is in $pages.
- Sidebar nav is built into $navSb by looping $pages and emitting a
  <div class="navgroup">GroupName</div><ul>...</ul> per Group, in first-seen
  order, then APPENDING a hardcoded final group:
    <div class="navgroup">C++ API</div>
    <ul><li><a href="api/index.html">C++ API (Doxygen)</a></li></ul>
  So the rendered group order is: Getting Started; Reference; Algorithm Guides;
  Development; Prompts; Research; C++ API. This mirrors the sibling project's
  sidebar and replaces its language-specific API group with "C++ API". Keep the
  Prompts group and the appended C++ API group. Group labels come from the Group
  field; the Title field is the visible link text (e.g. "MATLAB Optimizer Interface",
  "C++ API (how-to)", "Provenance Inventory", "License and Provenance").
- Rendering: Pandoc is primary (gfm -> html5, standalone, --toc --toc-depth=3,
  shared template); Convert-MarkdownFallback is the built-in renderer used when
  Pandoc is absent or older than 3.8 (the build passes
  --syntax-highlighting=none, a Pandoc 3.8 option); Doxygen (if present, with
  docs/Doxyfile) emits the C++ API into docs/html/api with
  OUTPUT_DIRECTORY=docs/html, HTML_OUTPUT=api. The
  -Clean switch wipes docs/html first. Keep the light/dark toggle, per-page TOC,
  copy buttons, mermaid, table wrapping, and no-BOM assets. Add no build
  dependency outside the PowerShell + Pandoc + Doxygen toolchain.
- The script does NOT touch docs/index.html (the redirect). Leave that file to be
  maintained by hand; do not add it to $pages.
- If you relocate configs/README.md content into getting-started/configuration.md,
  update the Src so the page is sourced from its new location.

## Language And Style Rules

- Follow docs\prompts\documentation_review_prompt.md: clear B2-level English,
  short paragraphs, ASCII punctuation, no mojibake, terms defined in the
  glossary, no vague filler. Keep the algorithm H1 em-dash form.
- Code fences use: matlab, cpp, text, powershell, yaml, json, mermaid. PowerShell
  is the shell convention, not bash. Use inline backticks for identifiers, paths,
  and filenames.
- Cross-links are relative .md paths with #anchor; dense interlinking is expected.
- Cite the implementing source as file.m:line or file.cpp:line for every formula
  and behavioral claim.

## Consistency Matrix (cross-check before finishing)

- Optimizer display names GSK / AGSK / APGSK / FDB-AGSK / ATMALS-GSK / eGSK /
  DT-GSK are identical on every page; slugs stay hyphenated and file names stay
  underscored.
- One canonical base seed (20240620) and one unified formula, verbatim, on every
  page that states them.
- The native/derived alias is described consistently (one fallback path, two
  names) wherever the policy set is listed; no page implies they differ.
- The two default entry points are stated the same everywhere: MATLAB
  run_experiment / run_all_cec*.m default unified+threefry; the gsk_run CLI /
  configs / run_all.ps1 default reference+threefry.
- Result paths, budgets (10000*D for cec2017 and cec2013; the cec2020 ladder
  D5->50000/D10->1000000/D15->3000000/D20->10000000; 150000 for cec2011;
  3000000 for cec2013lsgo), suite function counts, and the F2 exclusion are
  identical across index, benchmark_protocol, result_schema, benchmark_mapping,
  and the algorithm pages.
- The ATMALS-GSK-on-CEC2017 abs() reporting exception is stated identically
  wherever reporting is described, and nowhere generalized to other cases.
- Every sidebar entry resolves; every source .md renders to exactly one html;
  no link points at a moved or old path; the prompts/ pages and the appended
  C++ API entry are present in the nav.
- Every algorithm page has a heading slugged worked-example, and every page that
  links #worked-example resolves to it.
- No page claims a sibling-project tooling fact (its package install, JIT
  kernels, gsk-run, its source modules, its process pool) for THIS project.

## Suggested Order Of Work

1. Read the template and the ground truth; diff the sibling page list against the
   MATLAB tree and list any parity gaps (added/renamed/removed sibling pages).
2. For each existing MATLAB page, ALIGN its sections and opening callout to the
   template; VERIFY MATLAB-only pages for fact-correctness and live links.
3. Re-confirm the seven algorithm pages against the section skeleton (incl. the
   worked-example slug and the back-links to validation_report and
   numerical_examples).
4. Author any genuinely missing counterpart pages (NEW) with MATLAB-correct
   facts and the mandatory callout; REMOVE a page only if the template dropped it
   and nothing here needs it.
5. Re-check index.md (reading paths + per-folder groups) and index.html (redirect
   + group list).
6. Update scripts\build_docs.ps1 only if pages were added/renamed/moved (a $pages
   entry per change; nav groups and link rewriting then follow automatically).
7. Rebuild the site, fix every broken link, then run the validation block.

## Required Validation

Run and report the output of each:
- powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_docs.ps1 -Clean
- Test-Path docs\html\index.html        (must return True)
- Confirm one rendered html per source md, the prompts_*.html pages exist, and the
  Doxygen api\ tree built (docs\html\api\index.html).
- Search docs\html for unresolved links: there must be 0 occurrences of href to a
  .md file (every .md link must have been rewritten to a flat .html name).
- Search the sources and the built site for stale sibling-project tokens that
  would describe THIS project: the sibling's language name, its package-manager,
  JIT-compiler, and process-pool names, gsk-run, and its source-file extension -
  none should remain in prose about this project (a token inside the parity
  prompt's own translation rules is allowed, and so is a provenance citation of
  the DT-GSK reference implementation).
- Spot-check at least ten cross-links per folder in docs\html, including several
  #worked-example links.
- git status must show NO changes under src\ or benchmarks\ - this is docs-only,
  plus at most scripts\build_docs.ps1.

## Deliverables

1. A parity-gap report: the sibling page list diffed against the MATLAB tree, with
   each gap classified ALIGN / VERIFY / NEW / REMOVE / KEEP.
2. The maintained docs/ tree: every page on the template's section skeleton and
   opening callout, every MATLAB-only page fact-checked, any missing counterpart
   authored.
3. The seven algorithm pages confirmed on the section skeleton, with the
   worked-example slug and the validation/numerical-examples back-links.
4. An updated scripts\build_docs.ps1 IF and only if pages changed (page list, and
   the nav/rewriting that follows), PowerShell only.
5. index.md (goal-based reading paths + per-folder groups) and index.html
   (redirect + current group list) confirmed.
6. A page-by-page status report: page -> tag (ALIGN/VERIFY/KEEP/NEW/REMOVE) ->
   what changed.
7. A consistency report against the matrix above.
8. A severity-tagged change log (P0-P3).
9. The rebuilt docs\html and the validation evidence (commands plus output).

## Severity Scheme

- P0: a wrong or contradictory fact (seed, budget, path, formula, the
  native/derived alias, the ATMALS reporting exception, a default entry point), a
  broken build, a broken link, or any sibling-project tooling claim made about
  this project.
- P1: a missing required page or required section; an algorithm page off the
  skeleton or missing the worked-example slug; a sibling page added with no MATLAB
  counterpart; wrong nav grouping or order; a missing Prompts or C++ API nav group.
- P2: callout-dialect, terminology, or style drift; a weak worked example; thin
  diagram coverage; an outdated index.html group list.
- P3: polish, wording, and minor cross-link additions.

## Final Requirement

Every fact must match the MATLAB code and the existing MATLAB docs - cite the
line. Mirror the sibling project's STRUCTURE, never its language-specific facts,
and preserve the intentional MATLAB-side divergences (the prompts/ folder, the
index.html redirect, the C++ Doxygen API tier). Keep the project's MATLAB and
C++ only contract: the site is built only by scripts\build_docs.ps1. Rebuild
docs\html and confirm docs\html\index.html exists, the Doxygen api\ tree built,
and 0 unresolved .md links remain before declaring done.
```
