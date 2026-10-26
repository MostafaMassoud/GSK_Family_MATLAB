# Licenses And Provenance

This project keeps a single provenance and license record for the committed
MATLAB/C++ implementation, imported benchmark data, and imported reference
result tables. CEC benchmark implementations in this project are C++. GSK-family
optimizer implementations are MATLAB. Implementations and wrappers in other
languages, and generated language bindings, are excluded.

## Project author and algorithm citations

**Code Author:** Mostafa Elsayed Ahmed Masoud, PhD Candidate in Operations
Research, Department of Operations Research, Faculty of Graduate Studies for
Statistical Research, Cairo University, Giza 12613, Egypt

**ORCID:** <https://orcid.org/0009-0003-8415-2158>

**Email:** <moustafa.masoud@gmail.com>

**Copyright:** Copyright (C) 2026 Mostafa Elsayed Ahmed Masoud. The design and
implementation of this framework (the C++ benchmark ports and tools, the
MATLAB runner, the optimizer ports, the analysis and figure tools, the tests,
the launchers and the documentation) are the author's work. Redistributions
and derivative works must keep this copyright notice and the author
attribution, and work that uses the framework should cite it (see
`CITATION.cff`) together with the original algorithm papers
below.

The project-original MATLAB runners, C++ tooling, build scripts, documentation,
tests, packaging metadata, and integration glue are maintained as this project's
software work. The optimizer implementations are reference-faithful MATLAB
ports/organization of the published GSK-family algorithms and should be cited
with their original papers when used in research.

| Implemented optimizer or method | Reference publication |
|---|---|
| GSK | Mohamed, A. W.; Hadi, A. A.; Mohamed, A. K. "Gaining-sharing knowledge based algorithm for solving optimization problems: a novel nature-inspired algorithm." *International Journal of Machine Learning and Cybernetics*, 11, 1501-1529, 2020. DOI: [10.1007/s13042-019-01053-x](https://doi.org/10.1007/s13042-019-01053-x). |
| AGSK | Mohamed, A. W.; Hadi, A. A.; Mohamed, A. K.; Awad, N. H. "Evaluating the performance of adaptive gaining-sharing knowledge based algorithm on CEC 2020 benchmark problems." *2020 IEEE Congress on Evolutionary Computation (CEC)*, 1-8, 2020. DOI: [10.1109/CEC48606.2020.9185901](https://doi.org/10.1109/CEC48606.2020.9185901). |
| APGSK | Mohamed, A. W.; Abutarboush, H. F.; Hadi, A. A.; Mohamed, A. K. "Gaining-sharing knowledge based algorithm with adaptive parameters for engineering optimization." *IEEE Access*, 9, 65934-65946, 2021. DOI: [10.1109/ACCESS.2021.3076091](https://doi.org/10.1109/ACCESS.2021.3076091). |
| ATMALS-GSK | Alfadli, N. M.; Oun, E. M.; Mohamed, A. W. "Auto-Tuning Memory-Based Adaptive Local Search Gaining-Sharing Knowledge-Based Algorithm for Solving Optimization Problems." *Algorithms*, 18(7), 398, 2025. DOI: [10.3390/a18070398](https://doi.org/10.3390/a18070398). |
| eGSK | Jawad, M. A.; Roshdy, H. S. M.; Mohamed, A. W. "Enhanced Gaining-Sharing Knowledge-based algorithm." *Results in Control and Optimization*, 19, 100542, 2025. DOI: [10.1016/j.rico.2025.100542](https://doi.org/10.1016/j.rico.2025.100542). |
| FDB-AGSK | Bakir, H.; Duman, S.; Guvenc, U.; Kahraman, H. T. "Improved adaptive gaining-sharing knowledge algorithm with FDB-based guiding mechanism for optimization of optimal reactive power flow problem." *Electrical Engineering*, 105, 3121-3160, 2023. DOI: [10.1007/s00202-023-01803-9](https://doi.org/10.1007/s00202-023-01803-9). |
| FDB selection method | Kahraman, H. T.; Aras, S.; Gedikli, E. "Fitness-distance balance (FDB): a new selection method for meta-heuristic search algorithms." *Knowledge-Based Systems*, 190, 105169, 2020. DOI: [10.1016/j.knosys.2019.105169](https://doi.org/10.1016/j.knosys.2019.105169). |
| DT-GSK | Masoud, M. E. A.; Roshdy, H. S. M.; Mohamed, A. W. "DT-GSK: Dimension-Tiered Adaptive Configuration Selection and Deterministic Refinement for Gaining-Sharing Knowledge-Based Optimization Algorithm." *Algorithms* (MDPI), 19(9), 769, 2026. Reference implementation: DT-GSK v2.46 (MIT license), <https://github.com/MostafaMassoud/DT-GSK>. |

## Imported data and tables

- `benchmarks/cec_reference_results/` - imported published reference result tables.
  Read-only comparison material (`provenance = imported_reference`). The
  `<suite>/dt-gsk/` tables, and the CEC2017 per-run `evidence/` files, were
  imported from the DT-GSK reference repository (MIT license); sources and
  commits are recorded in `cec2017/dt-gsk/PROVENANCE.md`.
- `benchmarks/cec_suite_cpp/*/input_data/` - CEC input data copied from the
  suite source material; CEC2011 additionally contains committed plain-text
  assets derived during the validated port.

## Ported source provenance

- **CEC2017** (`benchmarks/cec_suite_cpp/cec2017/src/cec2017_problem.cpp`):
  ported from `cec17_func.cpp` (CEC2017 competition code by N. H. Awad,
  M. Z. Ali, P. N. Suganthan et al., as shipped in the reference). The
  staged `cec17_func.cpp` and original `readme.txt` are kept verbatim as
  provenance.
- **CEC2020** (`.../cec2020/src/cec2020_problem.cpp`): ported from
  `cec20_func.cpp` (CEC2020 competition code, C. T. Yue, K. V. Price,
  P. N. Suganthan et al., as shipped). Staged copy kept verbatim.
- **CEC2013** (`.../cec2013/src/cec2013_problem.cpp`): converted from the
  CEC2013 R package sources (R wrapper and C implementation). The R
  package metadata (DESCRIPTION/NAMESPACE/NEWS, GPL-compatible notices by
  Mauricio Zambrano-Bigiarini and Yasser Gonzalez-Fernandez) is preserved
  under `benchmarks/cec_suite_cpp/cec2013/`; the underlying test functions are
  the CEC2013 competition definitions (J. J. Liang, B. Y. Qu,
  P. N. Suganthan, A. G. Hernandez-Diaz).
- **CEC2013LSGO** (`.../cec2013lsgo/src/`): adapted in place from the
  reference large-scale suite C++ (X. Li, K. Tang, M. N. Omidvar, Z. Yang,
  K. Qin; distributed via the `cec2013lsgo` package; only the C++ sources
  are kept). The original `README.rst` is
  preserved; per-file headers retain their origin notes.
- **CEC2011** (`.../cec2011/src/cec2011_problem*.cpp`): ported from the
  CEC2011 real-world optimization MATLAB package (S. Das and
  P. N. Suganthan, "Problem Definitions and Evaluation Criteria for CEC
  2011 Competition...") as shipped in the reference; trajectory problems
  derive from the ESA GTOP `mga_dsm` MATLAB code included there.
- **GSK-family MATLAB optimizers** (`src/optimizers/*`): organized from
  the reference implementations by Ali Wagdy Mohamed and co-authors
  (GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK archives). File headers
  keep short provenance breadcrumbs; behavioral details are recorded in
  `docs/reference/porting_notes.md`.
- **DT-GSK MATLAB optimizer** (`src/optimizers/dt-gsk/`): ported to MATLAB from
  the DT-GSK reference implementation v2.46 (MIT license),
  <https://github.com/MostafaMassoud/DT-GSK> (tag `v2.46`, commit
  `64c70bb54125c9361b821939802ee4810fb7af50`), by Mostafa Elsayed Masoud,
  Heba Sayed Mohamed Roshdy, and Ali Wagdy Mohamed. No reference-implementation
  code is included; the port and its validation are recorded in
  `src/optimizers/dt-gsk/README.md`.
  Upstream notice:

  ```text
  MIT License

  Copyright (c) 2026 Mostafa Elsayed Masoud, Heba Sayed Mohamed Roshdy, and Ali Wagdy Mohamed

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  ```

## Behavioral-compatibility note

The CEC2011 P3/P4 port re-implements MATLAB `ode45` stepping behavior
(published Dormand-Prince / Shampine mathematics). MATLAB's shipped
sources were consulted to pin behavioral constants; no MathWorks source
code was copied into this project.

When porting any additional source file, copy the relevant notice into
this file and into the ported source comments when appropriate.

## License Analysis

This section determines the license the combined `gsk_family`
distribution can carry, component by component, and records the reasoning.
It supersedes any earlier informal statement about licensing.

**Conclusion (recommended, pending human/legal confirmation): the project
is distributed under GPL-3.0-or-later (GNU General Public License v3.0 or
later).** This `LICENSES.md` file is the canonical project licensing and
provenance record. This conclusion is forced by the CEC2013 component (see
below); GPL-3.0-or-later is an OSI-approved, FSF-published license and is
therefore a valid open-source code license.

### Why GPL-3.0-or-later is required (the binding constraint)

The standard CEC2013 suite
(`benchmarks/cec_suite_cpp/cec2013/src/cec2013_problem.cpp`) was *converted
from* the `cec2013` R package. That package's own `DESCRIPTION` file -
preserved in this repo at `benchmarks/cec_suite_cpp/cec2013/DESCRIPTION` -
states `License: GPL (>=3)`, and its `NEWS` file records the deliberate
move from "GPL v2" to "GPL v3" at version 0.1-5. The C++ port is a
*derivative work* of that GPL-licensed source: it is a translation/adaptation
of the package's C implementation of the 28 benchmark functions. Under the
GPL, a derivative work, when distributed, must itself be licensed under the
GPL (the same or a later version, given the "or later" grant). Because that
derivative is compiled into the single `gskcec` library and the CLI tools
together with every other component, the *combined* distributed work must
be offered under GPL-3.0-or-later. No more-permissive license can be placed
on the whole, since doing so would relicense the GPL-derived CEC2013 code in
violation of its terms.

### Component-by-component origin and obligation

| Component | Origin (per provenance above) | Upstream license / status | Obligation it imposes on the combined work |
|---|---|---|---|
| **CEC2013 standard suite** (`cec_suite_cpp/cec2013`) | Converted from the `cec2013` R package (Zambrano-Bigiarini & Gonzalez-Fernandez; original C by J. J. Liang) | **GPL (>= 3)** - explicit in the package `DESCRIPTION` | **Copyleft: forces GPL-3.0-or-later on the whole distribution.** This is the binding constraint. Preserve the package `DESCRIPTION`/`NAMESPACE`/`NEWS` and the upstream copyright/author attribution. |
| **CEC2013LSGO suite** (`cec_suite_cpp/cec2013lsgo`) | Adapted from the C++ test suite of the `cec2013lsgo` package (only the C++ sources are kept); underlying suite by Li, Tang, Omidvar, Yang, Qin | No explicit OSI license in the shipped `README.rst`; the upstream packaging is commonly MIT, but the bundled README states only a **citation requirement** (cite the CEC2013 LSGO technical report) | Citation requirement; preserve the `README.rst` and per-file origin headers. A permissive/MIT upstream is GPL-compatible, so it can be redistributed inside a GPL-3.0 combined work. |
| **CEC2017 suite** (`cec_suite_cpp/cec2017`) | Ported from `cec17_func.cpp` (CEC2017 competition code; Awad, Ali, Suganthan et al.) | Competition/academic code; no explicit OSI license shipped | Academic-use / attribution. Compatible with redistribution inside a GPL-3.0 work; preserve the original `readme.txt` and provenance copy. |
| **CEC2020 suite** (`cec_suite_cpp/cec2020`) | Ported from `cec20_func.cpp` (CEC2020 competition code; Yue, Price, Suganthan et al.) | Competition/academic code; no explicit OSI license shipped | Same as CEC2017. |
| **CEC2011 suite** (`cec_suite_cpp/cec2011`) | Ported from the CEC2011 real-world MATLAB package (Das & Suganthan); trajectory problems derive from ESA GTOP `mga_dsm` MATLAB | Competition/academic code; ESA GTOP code is academic/research | Academic-use / attribution. The `ode45`-replica note (behavioral constants only, no MathWorks source copied) is documented above and does not add a license obligation. |
| **GSK-family MATLAB optimizers** (`src/optimizers`, except `dt-gsk`) | Organized from the reference implementations of Ali Wagdy Mohamed and co-authors (GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK) | Author reference code; no explicit OSI license accompanied the archives | Attribution to the original authors (given in headers and the paper Acknowledgements). Placing them under the project GPL-3.0-or-later is consistent with the authorship context; **confirm with the original authors** that GPL redistribution of their reference-derived code is acceptable. |
| **DT-GSK MATLAB optimizer** (`src/optimizers/dt-gsk`) | Ported to MATLAB from the DT-GSK reference implementation v2.46 by Masoud, Roshdy, and Mohamed | **MIT** - explicit `LICENSE` in the reference repository | Permissive and GPL-compatible: the MATLAB port is part of this project under GPL-3.0-or-later. Keep the upstream copyright and permission notice (reproduced above) and cite the DT-GSK paper. |
| **Imported reference tables** (`benchmarks/cec_reference_results`) | Published result tables copied verbatim (read-only comparison data); the `dt-gsk` tables and CEC2017 per-run evidence come from the MIT-licensed DT-GSK repository | Data/tables (facts), not program code | None material; these are comparison data, not licensable program code. Kept read-only. |
| **Project-original code** (CLI tools, `gskcec` core, tests, runners, build, scripts, documentation) | Written for this project by Mostafa Masoud (`moustafa.masoud@gmail.com`) | The author's own work | Freely licensable by the author; placed under GPL-3.0-or-later to match the combined work. |

### Alternatives considered

- **MIT / BSD / Apache-2.0 (permissive).** *Rejected for the combined
  distribution.* They cannot lawfully cover the GPL-derived CEC2013 code.
  (Individual project-original files could in principle be dual-offered,
  but the *distribution as a whole* still has to be GPL because it links in
  the CEC2013 derivative.)
- **LGPL-3.0.** *Rejected.* The CEC2013 upstream is full GPL, not LGPL;
  the weaker copyleft of LGPL would not satisfy the upstream's terms for a
  derivative work.
- **GPL-3.0-only (no "or later").** Possible, but the upstream grant is
  "GPL (>= 3)", so **GPL-3.0-or-later** is the faithful match and is
  recommended.
- **Removing the CEC2013 suite to relax the license.** Technically this
  would lift the GPL constraint, but CEC2013 is an intended, validated part
  of the toolkit; removing it to permit a permissive license is not
  recommended. If a future release drops CEC2013 (and CEC2013LSGO if its
  upstream is treated as copyleft), the license could be revisited.

### Action items for the author (human/legal confirmation)

1. Confirm with the GSK reference-code authors (Ali Wagdy Mohamed and
   co-authors) that GPL-3.0-or-later redistribution of the optimizer code
   organized from their archives is acceptable.
2. Confirm the upstream license actually shipped with the `cec2013lsgo`
   sources used (the README states only a citation requirement); if it is
   MIT/permissive, no change is needed (it is GPL-compatible).
3. Confirm that the CEC competition codes (CEC2011/2017/2020) carry no
   redistribution terms incompatible with inclusion in a GPL-3.0 work;
   their published evaluation criteria are academic-use and attribution
   based, which is compatible, but this should be checked against the exact
   notices.
4. Keep the version string, `CITATION.cff` `license:` field, and
   `codemeta.json` `license` field all reading `GPL-3.0-or-later`.
