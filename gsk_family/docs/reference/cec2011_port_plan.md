# CEC2011 Real-World Suite - MATLAB -> C++ Porting Dossier

> **What this is:** The line-by-line porting dossier for the CEC2011 suite -- all
> 22 real-world problems, their MATLAB dispatch chains, embedded data, and every
> quirk the C++ port must reproduce bit-compatibly (flagged `[PRESERVE]`). It is
> the working map behind the `cec2011` C++ port in `benchmarks/cec_suite_cpp/`.
> **For:** anyone auditing or modifying the CEC2011 port. **Prerequisites:**
> [porting_notes.md](porting_notes.md) for the suite-level summary and validation
> results. **After reading:** you can locate the source math and the preserved
> quirk behind any CEC2011 problem.

Historical source set: CEC2011 benchmark suite material and the ATMALS-GSK
CEC2011 duplicate source layout used during the original port.

Scope: the 22 problems as dispatched by `Calc_Fitx_2011.m` and bounded by
`define_boundaries.m`; i.e. exactly what the GSK MATLAB experiments evaluate.
Where the original CEC2011 code contains bugs/typos, the port must reproduce
them bit-compatibly; they are flagged `[PRESERVE]` below.
---

## 1. File inventory (one-line roles)

### Benchmark dispatch core (port these)
| File | Role |
|---|---|
| `define_boundaries.m` | `[n,xmax,xmin] = define_boundaries(I_fno)` — dimension + bounds for problems 1..22 |
| `Calc_Fitx_2011.m` | `fitx = Calc_Fitx_2011(x,fun_num,PopSize)` — per-row dispatch to the 22 objectives + global NaN→0 rule (lines 57–61) |
| `bench_func.m` | `f = bench_func(x,fun_num)` — objectives for problems 1–8 (switch on fun_num) |

### Problem-specific dependencies (port these)
| File | Used by problem | Role |
|---|---|---|
| `diffsolv.m` | 3 | ODE right-hand side (7 states); `load c_bifunc_data` for rate-constant matrix `c` (10×4) |
| `intgrl.m` | 4 | ODE right-hand side (2 states, CSTR) |
| `data6Bus.m` | 8 | script: Garver 6-bus data (`Linedata` 7×8, `Candidate` 15×8, `Pgen`, `Pload` 1×6) |
| `cost_fn.m` | 9 | EBE transmission-pricing objective (126 vars) |
| `EBEinputfile.m` | 9 | script: IEEE 30-bus data (`bus_spec` 30×11, `linedata` 41×6 complex col 3, `basemva`, `tc` unused) |
| `EBEformybus.m` | 9 | builds imaginary-part Ybus from linedata (function name inside is `formybus`) |
| `antennafunccircular.m` | 10 | circular antenna array objective (writes `global directivity`, never read) |
| `array_factorcir.m` | 10 | array factor |AF(phi)| for 12-element circular array |
| `trapezoidalcir.m` | 10 | trapezoidal integration of AF² (for directivity term) |
| `MY_FUNCTION_10_1.m` / `_10_2.m` | 11 / 12 | wrappers: round x to 4 decimals, call `fn_DED_5` / `fn_DED_10` |
| `MY_FUNCTION_11_1..5.m` | 13–17 | wrappers → `fn_ELD_6`, `fn_ELD_13`, `fn_ELD_15`, `fn_ELD_40`, `fn_ELD_140` |
| `MY_FUNCTION_12_1..3.m` | 18–20 | wrappers → `fn_HT_ELD_Case_1/2/3` |
| `fn_DED_5.m`, `fn_DED_10.m` | 11, 12 | dynamic economic dispatch, 24 h × 5/10 units |
| `fn_ELD_6.m`, `fn_ELD_13.m`, `fn_ELD_15.m`, `fn_ELD_40.m`, `fn_ELD_140.m` | 13–17 | static economic load dispatch, 6/13/15/40/140 units |
| `fn_HT_ELD_Case_1/2/3.m` | 18–20 | hydrothermal scheduling, 4 hydro + 1 thermal, 24 h |
| `messengerfull.m`, `cassini2.m` | 21, 22 | one-line wrappers: `J = mga_dsm(t,problem)` |
| `mga_dsm.m` | 21, 22 | ESA ACT MGA-DSM trajectory cost (1274 lines: Lambert solver, analytic ephemerides, swingby) |

### Data files
| File | Status |
|---|---|
| `c_bifunc_data.mat` | needed by problem 3 — single variable `c` (10×4 double); full-precision values embedded in §Problem 3 below, so no MATLAB export is strictly required |
| `messengerfull.mat` | needed by problem 21 — struct `MGADSMproblem`; fields enumerated in §Problem 21 (embedded) |
| `cassini2.mat` | needed by problem 22 — struct `MGADSMproblem`; fields enumerated in §Problem 22 (embedded) |
| `matlab.mat` (145 KB) | ORPHAN — loaded by nothing in the folder (verified by grep for `load`); no export needed; kept in `input_data/` for provenance only |

### GSK-optimizer / driver files — NOT part of the benchmark port
- `GSK.m` — GSK optimizer driver (25 runs × 150,000 FEs, pop 100, loops func 1..22; historical source used a clock-based RNG seed, see §3)
- `Gained_Shared_Junior_R1R2R3.m`, `Gained_Shared_Senior_R1R2R3.m` — GSK index-selection helpers
- `boundConstraint.m` — L-SHADE-style bound repair `(pop+bound)/2`, used by GSK on offspring (optimizer-side, not in the objective)
- `Calc_All_Results.m` — post-processing of saved `Results\*.mat` (loop `[1 2 5:21]`, file pattern says `CEC2017` — copy-paste leftover)
- `display_plot.m` — antenna gain plot utility (calls `array_factorcir`, plotting only)
- `My_Solutions.m` — near-empty comment script

### Dev leftovers / unused (do NOT port; listed so nobody chases them)
- `MY_FUNCTION.m` — wrapper template (calls `fn_HT_ELD_Case_1`); never dispatched by `Calc_Fitx_2011`
- `angle3d.m` — 3-point angle helper; called by nothing
- `tersoff.m` — broken standalone draft of problem 5 (`NP` undefined); `bench_func` has its own inline copy
- `hsdrf.m` — Hausdorff-like distance (uses `pdist`/`squareform`, Statistics Toolbox); unused
- `fourth.m`, `fourthh.m`, `intgrl1.m` — broken/dev variants for problem 4 (`intgrl1` even contains `pause`); unused
- `bounds.m` — dev script duplicating the problem-9 bound computation; unused
- `test2.m`, `test3.m` — DE/PSO toy drivers for problem 1 (`test3` calls nonexistent `benchmark_func`; `test2` needs `randint` = Communications Toolbox); unused
- `bench_func.asv`, `intgrl.asv` — MATLAB editor autosaves
- `getlimit_messenger.m`, `getlimit_cassini2.m` — alternative bound tables, NOT used by the GSK driver (see §3 bound-discrepancy note)

### MATLAB toolbox / builtin dependencies spotted
- `ode45` + `odeset` (problems 3, 4) — core MATLAB, but an adaptive RK45 (Dormand–Prince) that the C++ port must replicate (see §3).
- `pdist`/`squareform` (Statistics & ML Toolbox) — only in unused `hsdrf.m`.
- `randint` (Communications Toolbox) — only in unused `test2.m`.
- Everything else is core MATLAB (`inv`, `linspace`, `realpow`, `reshape`, `repmat`, ...).

### Global variables shared between files
- `global directivity` — written by `antennafunccircular.m` (line 3/82), read by NOTHING. Safe to drop in C++ (document only).
- `global AU mu` — declared in `mga_dsm.m` line 1192 inside `CUSTOMeph`; `CUSTOMeph` is only reached when a sequence entry ≥ 10 (custom object). Messenger/cassini sequences are all ≤ 6, so these globals are never touched at runtime. Safe to drop.
- `global initial_flag` — only in unused `test2.m`/`test3.m` (in `define_boundaries` case 9 `initial_flag=0` is a plain local). Irrelevant.

---

## 2. Suite map: dispatch table and numbering

`Calc_Fitx_2011(x, fun_num, PopSize)` loops `i=1:PopSize` over rows of `x` and dispatches:

| GSK # | Dispatch chain | Native D | Official CEC2011 TR # |
|---|---|---|---|
| 1 | `bench_func(x,1)` | 6 | T01 FM sound waves |
| 2 | `bench_func(x,2)` | 30 | T02 Lennard-Jones |
| 3 | `bench_func(x,3)` → `ode45(diffsolv)` → `c_bifunc_data.mat` | 1 | T03 bifunctional catalyst |
| 4 | `bench_func(x,4)` → `ode45(intgrl)` | 1 | T04 stirred tank reactor |
| 5 | `bench_func(x,5)` | 30 | T05 Tersoff Si(B) |
| 6 | `bench_func(x,6)` | 30 | T06 Tersoff Si(C) |
| 7 | `bench_func(x,7)` | 20 | T07 spread-spectrum radar polyphase |
| 8 | `bench_func(x,8)` → `data6Bus` | 7 | T08 TNEP |
| 9 | `cost_fn(x)` → `EBEinputfile`, `EBEformybus` | 126 | T09 transmission pricing (EBE) |
| 10 | `antennafunccircular(x,[50 120],180,0.5)` → `array_factorcir`, `trapezoidalcir` | 12 | T10 circular antenna array |
| 11 | `MY_FUNCTION_10_1` → `fn_DED_5` | 120 | T11.1 DED 5-unit |
| 12 | `MY_FUNCTION_10_2` → `fn_DED_10` | 240 | T11.2 DED 10-unit |
| 13 | `MY_FUNCTION_11_1` → `fn_ELD_6` | 6 | T11.3 ELD 6-unit |
| 14 | `MY_FUNCTION_11_2` → `fn_ELD_13` | 13 | T11.4 ELD 13-unit |
| 15 | `MY_FUNCTION_11_3` → `fn_ELD_15` | 15 | T11.5 ELD 15-unit |
| 16 | `MY_FUNCTION_11_4` → `fn_ELD_40` | 40 | T11.6 ELD 40-unit |
| 17 | `MY_FUNCTION_11_5` → `fn_ELD_140` | 140 | T11.7 ELD 140-unit (Korean system) |
| 18 | `MY_FUNCTION_12_1` → `fn_HT_ELD_Case_1` | 96 | T11.8 hydrothermal case 1 |
| 19 | `MY_FUNCTION_12_2` → `fn_HT_ELD_Case_2` | 96 | T11.9 hydrothermal case 2 |
| 20 | `MY_FUNCTION_12_3` → `fn_HT_ELD_Case_3` | 96 | T11.10 hydrothermal case 3 |
| 21 | `load('messengerfull.mat')` → `messengerfull(x, MGADSMproblem)` → `mga_dsm` | 26 | T12 Messenger (full) |
| 22 | `load('cassini2.mat')` → `cassini2(x, MGADSMproblem)` → `mga_dsm` | 22 | T13 Cassini 2 |

Numbering note: GSK uses a flat 1..22; the official technical report has 13 problems with T11 split into 10 sub-cases. The `MY_FUNCTION_10_x/11_x/12_x` file names and the `%% Problem 10_1` comments in `define_boundaries.m` reflect an intermediate numbering (10_x = DED, 11_x = ELD, 12_x = hydrothermal). Comments in `define_boundaries.m` also mislabel case 4 as "Problem 3" and case 9 as "TNEP" — ignore the comments, trust the case numbers.

---

## 3. Global quirks to preserve / document

1. **NaN→0 fitness rule** — `Calc_Fitx_2011.m` lines 57–61: after EVERY evaluation (all 22 problems, although the comment claims it is only for Tersoff), `if isnan(fitx(i)), fitx(i)=0; end`. `[PRESERVE]` exactly; note `Inf` is NOT caught (`isnan(Inf)==0`), so e.g. problem 2 can legitimately return `+Inf`.
2. **4-decimal rounding of x** — all ten `MY_FUNCTION_*` wrappers (problems 11–20) do `x = round(x*10000)/10000` before evaluating. MATLAB `round` = half away from zero (C++ `std::round`). Problems 1–10, 21, 22 do NOT round.
3. **Historical clock-based RNG seeding** — `GSK.m` line 17: `rand('seed', sum(100*clock));` (legacy generator). The current project does not expose wall-clock seeding; reference comparisons use deterministic scheduled seeds instead.
4. **Per-call .mat reload** — problems 21/22 `load(...)` the .mat INSIDE the per-individual loop (Calc_Fitx_2011 lines 49, 53) — a pure performance bug. C++ should load/initialize once; numerically identical.
5. **ode45 fidelity (problems 3 & 4)** — `odeset('RelTol',1e-1)` (AbsTol default 1e-6), `tspan=[0 0.78]`, Dormand–Prince RK5(4) with MATLAB's specific initial-step heuristic, error controller, and refine=4 output interpolation. Problem 4's objective SUMS over the rows of the solver OUTPUT (`f=sum(sum(Y.^2,2)+0.1*u.^2)` — value depends on the NUMBER of output points, not on an integral!). Problem 3 only uses the final state (less sensitive, but the loose RelTol makes the trajectory solver-dependent too). A faithful C++ port must re-implement MATLAB's `ode45` stepping exactly (including refine=4: 3 interpolated points between steps via the 4th-order dense-output polynomial). This is the single biggest numerical-fidelity risk of the whole suite.
6. **Bound-table discrepancies (use `define_boundaries.m` as canonical)**:
   - Problem 22 element 9: `define_boundaries` lower bound = **400**, while both `getlimit_cassini2.m` and the `bounds` field inside `cassini2.mat` say **800** (official GTOP value). GSK results were produced with 400. `[PRESERVE 400]`
   - Problem 21 elements 1–2: `define_boundaries` upper = 2300 / 4.05 (matches `getlimit_messenger.m`), but the `bounds` field inside `messengerfull.mat` says 2200 / 5.0. The .mat `bounds` field is never read by any dispatched code — ignore it.
7. **Problem 12 degenerate variable** — unit 10 has Pmin=Pmax=55, so 24 of the 240 variables have lower==upper bound (range 0). Random init still works (`0.55*rand` ... actually `lo + rand*0` = 55). C++ bound code must tolerate zero-width ranges.
8. **`define_boundaries` case 9 computes bounds from data** — it runs the `EBEinputfile` script and computes `xmax(c)=GD_max(i,j)` (see §Problem 9); bounds are NOT constants and must be computed by the C++ side the same way (or precomputed as a 126-vector and frozen).
9. **GSK driver expects `Figures\` and `Results\` subdirectories** to exist for `save` (driver-side note only).

---

## 4. Ground-truth probe plan (stated once, applies to every problem)

Convention: **3 deterministic probe vectors per problem**, elementwise over the native bounds `lo`, `hi` from `define_boundaries`:
1. `mid = (lo+hi)/2`
2. `q1 = lo + 0.25*(hi-lo)`
3. `q3 = lo + 0.75*(hi-lo)`

Evaluate each through `Calc_Fitx_2011` (i.e. INCLUDING the wrapper rounding for 11–20 and the NaN→0 rule) in MATLAB once, store `(problem, probe, f)` with `%.17g`, and require the C++ port to match to a stated tolerance (suggest exact-to-1e-12-relative for all problems except 3/4, where matching depends on the ode45 re-implementation and should be exact only once that is bit-faithful).

Probe-risk flags (problems where probes are NOT plain finite numbers):
- **Problem 2 (Lennard-Jones), `mid` probe → `+Inf`**: variables 4..30 have symmetric bounds, so `mid` places atoms 2..10 all at the origin → `r=0` → `1/r^12 = Inf`. NOT converted by the NaN rule. Keep the probe (Inf is a legitimate reference value) but compare specially. `q1`/`q3` are finite (atoms sit at distinct positions because the per-atom bound width grows with index).
- **Problems 5/6 (Tersoff), `mid` probe → NaN → 0**: same coincident-atom geometry gives `ctheta = 0/0 = NaN`, which propagates and is then zeroed by the NaN rule. Expected reference value: exactly `0`. `q1`/`q3` finite.
- **Problems 3/4**: finite, but solver-dependent (see §3.5).
- **Problem 8**: probes are safe (`ceil` of 3.75/7.5/11.25). The published lower bound includes `x_i = 0`, while raw MATLAB `ceil(0)` would give `Candidate(0,:)`. The maintained C++ port maps the resulting discrete index into `1..15`, so the inclusive lower bound is usable by optimizers that legitimately land on `lb`.
- **Problems 21/22**: probes are finite in practice, but `IC2par`'s `acos` calls can exceed [-1,1] by rounding for edge geometries → complex intermediates in MATLAB (silently absorbed by `norm`). The C++ port should clamp acos arguments to [-1,1] ONLY after verifying the MATLAB probe values, and flag any |imag| > 0 observed. Also `lambertI` returns NaN velocities if a transfer time ≤ 0 were ever requested (cannot happen within bounds: tof ≥ 30, alpha ≤ 0.99).

---

## 5. Per-problem dossier

### Problem 1 — FM sound-wave parameter estimation (T01) — difficulty S
- **D=6**; bounds: `lo = -6.4`, `hi = 6.35` for all j (note asymmetry).
- **Chain**: `Calc_Fitx_2011` → `bench_func.m` case 1.
- **Math** (bench_func lines 29–35): `theta = 2*pi/100`; for `t = 0..100` (101 integer samples):
  - `y(t)   = x1*sin(x2*t*theta + x3*sin(x4*t*theta + x5*sin(x6*t*theta)))`
  - `y0(t)  = 1*sin(5*t*theta - 1.5*sin(4.8*t*theta + 2*sin(4.9*t*theta)))`
  - `f = sum_t (y(t)-y0(t))^2`.
- If D>6 only the first six entries are used (prints a notice); D<6 only prints a notice (then would error). Port assumes D=6.
- **Data**: none. **Probe risk**: none.

### Problem 2 — Lennard-Jones potential, 10 atoms (T02) — difficulty S
- **D=30** (=3×10). Bounds (define_boundaries case 2): j=1: [0,4]; j=2: [0,4]; j=3: [0,pi]; j≥4: `hi = 4 + 0.25*floor((j-4)/3)`, `lo = -hi`.
- **Chain**: `bench_func.m` case 2.
- **Math** (lines 42–58): `x` reshaped column-major as `reshape(x,3,n)'` → atom i = `(x(3i-2), x(3i-1), x(3i))`. For all pairs i<j: `r = ||atom_i - atom_j||`; `v += 1/r^12 - 2/r^6` (a=1, b=2 matrices). `f = v`.
- **Data**: none. **Probe risk**: `mid` → `+Inf` (see §4).

### Problem 3 — Bifunctional catalyst blend optimal control (T03) — difficulty M
- **D=1**; bounds [0.6, 0.9].
- **Chain**: `bench_func.m` case 3 → `ode45(@(t,y) diffsolv(t,y,u), [0 0.78], y0, odeset('RelTol',0.1))` → `diffsolv.m` (loads `c_bifunc_data.mat` on every RHS call — hoist in C++).
- **Math**: `y0 = [1 0 0 0 0 0 0]`. Rate constants: `ml = [1 u u^2 u^3]` (u = the scalar decision variable); `k(i) = sum_j c(i,j)*ml(j)`, i=1..10. ODE (diffsolv lines 6–13):
  ```
  dy1 = -k1*y1
  dy2 =  k1*y1 - (k2+k3)*y2 + k4*y5
  dy3 =  k2*y2
  dy4 = -k6*y4 + k5*y5
  dy5 =  k3*y2 + k6*y4 - (k4+k5+k8+k9)*y5 + k7*y6 + k10*y7
  dy6 =  k8*y5 - k7*y6
  dy7 =  k9*y5 - k10*y7
  ```
  Objective: `f = Y(end,end) * 1e3` — i.e. the LAST state component (y7) at the final output row, ×1000.
- **Data**: `c_bifunc_data.mat`, variable `c` (10×4), consumed as above. Full precision (rows 1..10, columns = coefficients of 1, u, u², u³):
  ```
  0.002918487          -0.0080457870000000004  0.0067499470000000001  -0.001416647
  9.5099769999999992   -35.00994               42.833289999999998     -17.33333
  26.820930000000001   -95.560789999999997     113.0398               -44.299970000000002
  208.72409999999999   -719.80520000000001     827.74659999999994     -316.66550000000001
  1.3500049999999999   -6.8500269999999999     12.16671               -6.6666889999999999
  0.01921995           -0.079453200000000002   0.110566               -0.050333330000000003
  0.13235959999999999  -0.46925499999999998    0.55393230000000004    -0.21666640000000001
  7.3399809999999999   -25.27328               29.93329               -11.99999
  -0.3950534           1.6793530000000001      -1.7778290000000001    0.49749870000000002
  -2.5046649999999998e-05  0.010058539999999999  -0.019866959999999999  0.0098334700000000004
  ```
- **Quirk**: ode45 with RelTol=0.1 (see §3.5). The final row of `Y` is the t=0.78 state regardless of step count, so this problem is less step-count sensitive than problem 4, but still solver-dependent at this loose tolerance.

### Problem 4 — Optimal control of nonlinear stirred tank reactor (T04) — difficulty M (fidelity XL — see §3.5)
- **D=1**; bounds [0, 5].
- **Chain**: `bench_func.m` case 4 → `ode45(@(t,y) intgrl(t,y,u), [0 0.78], [0.09;0.09], odeset('RelTol',0.1))` → `intgrl.m`.
- **Math**: ODE:
  ```
  dy1 = -(2+u)*(y1+0.25) + (y2+0.5)*exp(25*y1/(y1+2))
  dy2 = 0.5 - y2 - (y2+0.5)*exp(25*y1/(y1+2))
  ```
  Objective: `f = sum( sum(Y.^2, 2) + 0.1*u^2 )` — sum over ALL ode45 OUTPUT ROWS of (y1²+y2²) plus `0.1*u²` PER ROW. The value therefore scales with the number of output points (refine=4 interpolated grid). `[PRESERVE]` — must match MATLAB's step sequence exactly.
- **Data**: none.

### Problem 5 — Tersoff potential, Si(B) parameterization (T05) — difficulty M
- **D=30**; bounds identical to problem 2.
- **Chain**: `bench_func.m` case 5 (self-contained; ignore the broken standalone `tersoff.m`).
- **Math** (lines 85–144). Constants: `R1=3.0, R2=0.2, A=3.2647e3, B=9.5373e1, lambda1=3.2394, lambda2=1.3258, lambda3=1.3258, c=4.8381, d=2.0417, n1=22.956, gamma=0.33675, h=0`. Atoms as in problem 2 (`reshape(x,3,NP)'`, NP=10).
  - Pass 1 (all ordered pairs i,j including i==j): `r(i,j)=||xi-xj||`; cutoff `fcr(i,j) = 1` if `r<R1-R2`; `0` if `r>R1+R2`; else `0.5 - 0.5*sin(pi/2*(r-R1)/R2)`; `VRr=A*exp(-lambda1*r)`, `VAr=B*exp(-lambda2*r)`.
  - Pass 2 (i≠j): `jeta = zeros(NP,NP)` REINITIALIZED for every (i,j); accumulate over k≠i,k≠j:
    - `rd1=||xi-xk||, rd3=||xk-xj||, rd2=||xi-xj||`
    - `ctheta = (rd1^2 + rd2^2 - rd3^3) / (2*rd1*rd2)` — `[PRESERVE]` rd3 is CUBED (famous typo; law of cosines would use rd3²)
    - `G = 1 + c²/d² - c²/(d² + (h-ctheta)²)`
    - `jeta(i,j) += fcr(i,k) * G * exp( lambda3^3 * (r(i,j)-r(i,k))^3 )`
  - `Bij = (1 + (gamma*jeta(i,j))^n1)^(-0.5/n1)`; `E(i) += fcr(i,j) * (VRr(i,j) - Bij*VAr(i,j)) / 2`; `f = sum(E)`.
- **Data**: none. **Probe risk**: `mid` → NaN → 0 (§4). Negative base in `(...)^n1` with non-integer n1 can produce complex `Bij` for gamma*jeta < 0 — MATLAB silently goes complex and `f=sum(E)` may carry a tiny imaginary part; `fitx` then stores `real`? (MATLAB keeps complex; assigning into a real array drops imag with a warning only in old versions — actually it errors in new MATLAB; with jeta≥0*G... G≥... in practice values stay real). C++ porter: compute `pow` only after verifying sign; flag if encountered during probe verification.

### Problem 6 — Tersoff potential, Si(C) parameterization (T06) — difficulty M
- Identical structure/code to problem 5 (bench_func case 6) with constants: `R1=2.85, R2=0.15, A=1.8308e3, B=4.7118e2, lambda1=2.4799, lambda2=1.7322, lambda3=1.7322, c=1.0039e5, d=1.6218e1, n1=7.8734e-1, gamma=1.0999e-6, h=-5.9826e-1`.
- **D=30**, bounds as problem 2. Same probe risk (mid → NaN → 0).

### Problem 7 — Spread-spectrum radar polyphase code design (T07) — difficulty S
- **D=20**; bounds [0, 2π] all.
- **Chain**: `bench_func.m` case 7.
- **Math** (lines 207–234): `var = 2*d-1 = 39`; for `kk = 1..2*var = 78`:
  - odd kk: `i=(kk+1)/2`; `hsum(kk) = sum_{j=i..d} cos( sum_{i1=|2i-j-1|+1..j} x(i1) )` (empty j-range → 0 for i>d)
  - even kk: `i=kk/2`; `hsum(kk) = 0.5 + sum_{j=i+1..d} cos( sum_{i1=|2i-j|+1..j} x(i1) )`
  - `f = max(hsum)`.
- Note for odd kk with i > d the sum is empty → `hsum(kk)=0`; for even kk with i ≥ d the sum is empty → `hsum(kk)=0.5`. These entries participate in the max. `[PRESERVE]`
- **Data**: none. **Probe risk**: none.

### Problem 8 — Transmission Network Expansion Planning, Garver 6-bus (T08) — difficulty M
- **D=7**; bounds [0, 15] all (continuous; discretized by `ceil` inside).
- **Chain**: `bench_func.m` case 8 → `data6Bus.m` (script defines `Linedata` 7×8 `[No from to X num_Line Pijmax cost Overloads]`, `Candidate` 15×8 same columns, `Pgen=[0.5 0 1.65 0 0 5.45]`, `Pload=[0.8 2.4 0.4 1.6 2.4 0]`). Original lines 6/7 have finite costs 20/30; lines 1–5 cost `inf` (never summed).
- **Math** (lines 240–290):
  1. `sw = clamp(ceil(x), 1, 15)` → 7 candidate indices in 1..15. This keeps the published inclusive `[0,15]` bounds usable; `x=0` maps to candidate 1.
  2. Append `Candidate(sw(k),:)` k=1..7 to `Linedata` (duplicates allowed) → 14 lines total.
  3. DC power flow: `B` 6×6 susceptance matrix from `bline=1/X` per line (`B(k,m)-=b; B(m,k)=B(k,m); B(k,k)+=b; B(m,m)+=b`); then `B(1,1)=1e7` (slack regularization `[PRESERVE]`), `X=inv(B)`, `delta = X*(Pgen-Pload)'`, line flow `pij(k) = (delta(i)-delta(j))/Xline(k)`.
  4. Objective: `f = sum(Linedata(8:14,7)) + 30` (cost of the 7 added candidate lines + constant 30)
     `+ 5000*sum_k max(|pij(k)| - Pijmax(k), 0)` (overload penalty over ALL 14 lines)
     `+ 1000` for EVERY candidate index chosen MORE THAN 3 times (`length(find(sw==i))>3`).
- **Data**: inline in `data6Bus.m` (transcribe the two tables). **Probe risk**: none for the three probes.

### Problem 9 — Large-scale transmission pricing / EBE bilateral transactions, IEEE 30-bus (T09) — difficulty L
- **D=126** (= 6 generators × 21 loads).
- **Bounds** (define_boundaries case 9, computed from data): runs `EBEinputfile`; `Pg=bus_spec(:,7)/100`, `Pd=bus_spec(:,5)/100`; `g=find(Pg>0)` → buses {1,2,5,8,11,13} (6 gens); `d=find(Pd>0)` → 21 load buses {2,3,4,5,7,8,10,12,14,15,16,17,18,19,20,21,23,24,26,29,30}. `BT` 6×21 sparse table (MW/100): `BT(1,4)=5, BT(1,5)=10, BT(1,6)=5, BT(2,3)=5, BT(3,21)=2.5, BT(4,21)=2.5, BT(4,16)=15, BT(5,12)=2.5, BT(6,8)=2.5`, all `/100`. Then for each (i,j) flattened with j fastest (c = (i-1)*21+j): `xmin(c)=0`, `xmax(c)=min(Pg(g(i))-BT(i,j), Pd(d(j))-BT(i,j))`. NOTE: BT indices are positions in the g/d lists, not bus numbers.
- **Chain**: `Calc_Fitx_2011` → `cost_fn.m` → `EBEinputfile.m` (data script), `EBEformybus.m`.
- **Math** (`cost_fn.m`):
  1. `Kp=100`. Decision vars: `GD(i,:) = x((i-1)*21+1 : i*21)` (6×21 transaction matrix), same layout as the bounds.
  2. Ybus: `EBEformybus(linedata, 30)` — uses ONLY `imag(linedata(:,3))` (series reactance): `YI=1./ZI`, assembled per line into 30×30 `YIbus`. Then delete row 1 & column 1, `Xt=inv(YIbus(2:30,2:30))`, re-pad into 30×30 `X` with zeros in row/col 1.
  3. PTDF tensor (6×21×41): `PTDF(i,j,k) = (X(na(k),g(i)) - X(nb(k),g(i)) - X(na(k),d(j)) + X(nb(k),d(j))) / xij(k)` where `na/nb = linedata(:,1:2)`, `xij = imag(linedata(:,3))`, 41 lines.
  4. `FC = 100*xij/sum(xij)`; per line `flows(k) = sum_ij ( |PTDF(i,j,k)*GD(i,j)| + |PTDF(i,j,k)*BT(i,j)| )`; `cost_line(k) = FC(k)/flows(k)`. (`flows`/`cost_line` are allocated `zeros(41)` i.e. 41×41 but used as linear-indexed vectors — harmless. `[PRESERVE semantics, not allocation]`)
  5. `cost_l(i,j) = sum_k |cost_line(k)*PTDF(i,j,k)|`; `cost_gen(i) = sum_j GD(i,j)*cost_l(i,j)`; `cost_load(j) = sum_i GD(i,j)*cost_l(i,j)`.
  6. `pg = Pg(g) - sum(BT,2)`; `pd = Pd(d) - sum(BT,1)'`. Targets: `Rg = [32.7290 32.1122 30.3532 33.6474 64.1156 66.8729]`; `Rd = [7.5449 10.7964 10.9944 11.0402 11.7990 15.3803 42.6800 41.4551 73.1939 57.0430 45.5920 43.6553 61.8002 59.6409 57.0279 51.0749 67.1070 60.6623 198.6744 178.9956 199.9483]`.
  7. `rate_d = sum_i (cost_gen(i)/pg(i) - Rg(i))^2 + sum_j (cost_load(j)/pd(j) - Rd(j))^2`.
  8. Constraints: `Pg_x = sum(GD,2)+sum(BT,2)`, `Pd_x = sum(GD,1)+sum(BT,1)`; `PENALTY = sum_i 100*|Pg_x(i)-Pg(i)| + sum_j 100*|Pd_x(j)-Pd(j)|` (Pg/Pd here are the 6/21-element reduced vectors).
  9. **`fitness = rate_d + 50*Kp*PENALTY`** (= rate_d + 5000*PENALTY). Returns `[fitness PENALTY rate_d]`; dispatch keeps only fitness.
- **Data**: inline in `EBEinputfile.m` — transcribe `bus_spec` (30×11; only columns 5 [load MW] and 7 [gen MW] are consumed) and `linedata` (41 rows; only columns 1, 2 and the IMAGINARY part of the complex column 3 are consumed; half-line charging col 4, tap col 5, limit col 6 unused). `basemva`, `accuracy`, `maxiter`, `tc` unused.
- **Probe risk**: none expected (flows>0 because BT-terms are nonzero; pg,pd > 0 fixed).

### Problem 10 — Circular antenna array design (T10) — difficulty M
- **D=12**; bounds: j=1..6 (element amplitudes) [0.2, 1]; j=7..12 (phases, degrees) [-180, 180].
- **Chain**: `Calc_Fitx_2011` (passes `null=[50 120]`, `phi_desired=180`, `distance=0.5`) → `antennafunccircular.m` → `array_factorcir.m`, `trapezoidalcir.m`.
- **Math**:
  - `array_factorcir(x1, phi, 180, 0.5, 12)`: local `pi=3.141592654` `[PRESERVE — NOT built-in pi; used in delphi, deg→rad and the pi/2 of trapezoidalcir's sin]`. For i1=1..6: `delphi=2*pi*(i1-1)/12`; `shi = (cos(phi-delphi) - cos(phi_desired*(pi/180)-delphi)) * 12 * 0.5`; real part `y += x1(i1)*cos(shi + x1(6+i1)*(pi/180))`; for i1=7..12: `delphi=2*pi*(i1-1)/12` (continues around the circle) and `y += x1(i1-6)*cos(shi - x1(i1)*(pi/180))` (same amplitudes mirrored, phase NEGATED). Two analogous loops with `sin` accumulate `y1`. Return `sqrt(y^2+y1^2)`.
  - `antennafunccircular`: scan `phi = linspace(0,360,300)` evaluating `AF((pi/180)*phi(i))` → find global max `maxi` and its angle `phizero` (deg) / index `phi_ref`; collect ALL local maxima (plus endpoints if locally max) as sidelobes; sort descending; `sllreturn = 20*log10(sidelobes(2)/maxi)`.
  - Beamwidth `bwfn`: walk up/down from `phi_ref` until first local minimum on each side (default 180 each side if none/edge) — upper walk breaks with 180 if `phi_ref+i > 299`; lower walk breaks with 180 if `phi_ref-i < 2`; `bwfn = upper+lower`.
  - Null term: `y1 = sum_i AF(null(i))/maxi` with `null = [50, 120]` passed RAW — i.e. evaluated at 50 and 120 RADIANS (the scan uses degrees→radians, the nulls do not). `[PRESERVE]` (this is the original CEC2011 behavior).
  - Directivity (computed, only used via global): `uavg = trapezoidalcir(x1, 0, 2*pi, 50, ...)` — note arguments named (upper=0, lower=2π) so the step `h=(0-2π)/50` is NEGATIVE and the trapezoid runs backwards; integrand `|AF(t)^2 * sin(t - π/2)|` via `realpow`; `y2 = |2π*maxi²/uavg|`; `global directivity = 10*log10(y2)` (write-only).
  - Pointing term: `y3 = |phizero - 180|` (degrees); if `y3 < 5` → `y3 = 0`.
  - Beamwidth penalty: `y = (bwfn>80) ? |bwfn-80| : 0`.
  - **Return `y = sllreturn + y + y1 + y3`.** (Directivity does NOT enter the objective.)
- **Data**: none. **Probe risk**: none expected (≥2 local maxima guaranteed in practice; verify during probe generation).

### Problems 11–20 — power-dispatch family: shared penalty engine
All ten go through identical wrappers (`MY_FUNCTION_*`): round x to 4 decimals → call `fn_*` → return `Total_Value` (first output) only. The recurring penalty primitive is the one-sided violation written as `sum(abs(v-lo)-(v-lo)) + sum(abs(hi-v)-(hi-v))` = `2*sum(max(lo-v,0)) + 2*sum(max(v-hi,0))` — note the **factor 2** relative to a plain hinge. POZ primitive: `sum over zones z and units u of (POZlo<x & x<POZhi) .* min(x-POZlo, POZhi-x)` (depth-of-intrusion, strictly-inside test).

### Problem 11 — Dynamic Economic Dispatch, 5 units × 24 h (T11.1) — difficulty M
- **D=120**; bounds: `repmat(Pmin,1,24)` / `repmat(Pmax,1,24)` with `Pmin=[10 20 30 40 50]`, `Pmax=[75 125 175 250 300]` (ordering: 5 units of hour 1, then hour 2, ...).
- **Chain**: `MY_FUNCTION_10_1` → `fn_DED_5.m`.
- **Math** (`fn_DED_5`): `Input_Generations = reshape(x,5,24)'` (row j = hour j; consistent with bound layout).
  - Data (inline): `Power_Demand` (24 values: 410 435 475 530 558 608 626 654 690 704 720 740 704 690 654 580 558 608 654 704 680 605 527 463); `Data1=[Pmin Pmax a b c e f]` per unit (rows as in file lines 18–22); `Data2`: Po=NaN, UR=DR=[30 30 40 50 50], degenerate POZ columns (Zone1min=Zone1max etc. → POZ penalty always 0 but code path must exist); `B1` 5×5 loss matrix (lines 31–35), `B2=0`, `B3=0`.
  - Per hour j: `Power_Loss = x*B1*x' + B2*x' + B3`, then **rounded to 4 decimals** (`round(PL*10000)/10000`). `PB_pen(j) = |Demand(j) + PL - sum(x)|`. Capacity pen (primitive above vs Pmin/Pmax). Ramp pen for j>1: `UpLim=min(Pmax, prev+UR)`, `DownLim=max(Pmin, prev-DR)`, primitive vs [DownLim,UpLim]; `prev` initialized NaN (so j=1 skipped) and set to current x each hour. POZ pen per hour (degenerate → 0).
  - Cost per hour: `sum( a.*x.^2 + b.*x + c + |e.*sin(f.*(Pmin-x))| )` (valve-point).
  - **Total = sum(cost) + sum( 1e3*PB + 1e3*Cap + 1e5*Ramp + 1e5*POZ )**.
- **Data**: all inline (transcribe tables from fn_DED_5 lines 16–35). **Probe risk**: none.

### Problem 12 — Dynamic Economic Dispatch, 10 units × 24 h (T11.2) — difficulty M
- **D=240**; bounds `repmat` of `Pmin=[150 135 73 60 73 57 20 47 20 55]`, `Pmax=[470 460 340 300 243 160 130 120 80 55]` (unit 10 fixed: 55..55, see §3.7).
- **Chain**: `MY_FUNCTION_10_2` → `fn_DED_10.m`.
- **Differences vs problem 11**: `reshape(x,10,24)'`; `Power_Demand` = (1036 1110 1258 1406 1480 1628 1702 1776 1924 2072 2146 2220 2072 1924 1776 1554 1480 1628 1776 2072 1924 1628 1332 1184); `Data1` rows in file lines 18–27; `Data2` has ONLY Po/UR/DR columns (UR=DR=[80 80 80 50 50 50 30 30 30 30]) → POZ table is EMPTY (0×10) → POZ penalty 0; `B1=B2=B3=0` and `Power_Loss` is NOT rounded (no rounding line — irrelevant since PL=0, but `[PRESERVE]`); penalty weights **1e3·PB + 1e3·Cap + 1e3·Ramp + 1e5·POZ** (ramp weight 1e3 here vs 1e5 in DED_5 `[PRESERVE]`).
- **Data**: inline. **Probe risk**: none.

### Problem 13 — Static ELD, 6 units (T11.3) — difficulty S/M (shared engine)
- **D=6**; bounds per-unit `[100 500;50 200;80 300;50 150;50 200;50 120]`.
- **Chain**: `MY_FUNCTION_11_1` → `fn_ELD_6.m` (population-capable; called with one row).
- **Math**: demand 1263 MW. `Data1=[Pmin Pmax a b c]` (file lines 13–18; quadratic cost only, NO valve point). `Data2=[Po UR DR Zone1min Zone1max Zone2min Zone2max]` (lines 20–25, real POZ zones). Loss: full 6×6 `B1*1e-5` (lines 27–32; NOTE row 6 col 1 is **+0.2** while row 1 col 6 is −0.2 — asymmetric typo `[PRESERVE]`), `B2=[-0.3908 -0.1297 0.7047 0.0591 0.2161 -0.6635]*1e-5`, `B3=0.0056e-2`. `Power_Loss` rounded to 4 decimals.
  - Ramp limits computed ONCE from `Po=[440 170 200 150 190 150]` (static, not chained over hours): `UpLim=min(Pmax,Po+UR)`, `DownLim=max(Pmin,Po-DR)`.
  - **Total = cost + 1e3·PB + 1e3·Cap + 1e5·Ramp + 1e5·POZ** with `PB = |1263 + PL - sum(x)|`.
- **Data**: inline. **Probe risk**: none.

### Problem 14 — Static ELD, 13 units (T11.4) — difficulty S/M
- **D=13**; bounds `[0,680;0,360;0,360;60,180;…;55,120]` (define_boundaries case 14 = Data1 cols 1–2).
- **Chain**: `MY_FUNCTION_11_2` → `fn_ELD_13.m`.
- **Math**: demand 1800 MW; `Data1=[Pmin Pmax a b c e f]` (lines 13–25, WITH valve point `|e.*sin(f.*(Pmin-x))|`); NO ramp, NO POZ (`Data2=[]`); `B1=B2=B3=0` but loss still computed+rounded (=0).
  - **Total = cost + 1e5·PB + 1e3·Cap** (`[PRESERVE]` PB weight 1e5 here).
- **Data**: inline. **Probe risk**: none.

### Problem 15 — Static ELD, 15 units (T11.5) — difficulty M
- **D=15**; bounds = Data1 cols 1–2 (define_boundaries case 15).
- **Chain**: `MY_FUNCTION_11_3` → `fn_ELD_15.m`.
- **Math**: demand 2630 MW; quadratic cost (no valve point); `Data2` with Po/UR/DR + THREE POZ zones per unit (`[Zone1min Zone1max Zone2min Zone2max Zone3min Zone3max]`, lines 29–43; many degenerate rows); full 15×15 `B1*1e-5` (lines 45–59), `B2` (line 62) `*1e-5`, `B3=0.0055e-2`; loss rounded. Static ramp limits from Po as in ELD_6.
  - **Total = cost + 1e3·PB + 1e3·Cap + 1e5·Ramp + 1e5·POZ**.
- **Data**: inline (largest small-table transcription: B1 15×15). **Probe risk**: none.

### Problem 16 — Static ELD, 40 units (T11.6) — difficulty M
- **D=40**; bounds = Data1 cols 1–2 (define_boundaries case 16).
- **Chain**: `MY_FUNCTION_11_4` → `fn_ELD_40.m`.
- **Math**: demand 10500 MW; `Data1=[Pmin Pmax a b c e f]` (lines 13–52) WITH valve point; no ramp/POZ (`Data2=[]`); `B=0` (loss computed+rounded =0).
  - **Total = cost + 1e5·PB + 1e3·Cap**.
- **Data**: inline (40 rows × 7). **Probe risk**: none.

### Problem 17 — Static ELD, 140 units / Korean grid (T11.7) — difficulty L
- **D=140**; bounds = Data1 cols 1–2 (define_boundaries case 17 — long literal list, must equal Data1).
- **Chain**: `MY_FUNCTION_11_5` → `fn_ELD_140.m`.
- **Math / structure** (`fn_ELD_140.m`):
  - `Data1` (lines 13–153): **column order [Pmin Pmax c b a]** — cost coefficients REVERSED vs other ELD files; unpacked as `a=col5, b=col4, c=col3` `[PRESERVE]`.
  - `Data2` (lines 156–296): `[Po UR DR]` per unit.
  - `Data3` (lines 304–316): valve-point `[unit e f]` for 12 units only {5,10,15,22,33,40,52,70,72,84,119,121}; spliced via `Data1(Data3(:,1),6:7)=Data3(:,2:3)` — all OTHER units implicitly get e=f=0 (matrix auto-expansion with zeros) `[PRESERVE]`.
  - `Data4` (lines 327–331): POZ `[unit z1lo z1hi z2lo z2hi z3lo z3hi]` for 4 units {8,32,74,136} (unit 136 zone 3 = 0,0); spliced via `Data2(Data4(:,1),4:9)=...` — other units get all-zero zones → no penalty.
  - Demand 49342 MW; `B=0`; loss computed+rounded (=0). Static ramp limits from Po.
  - **QUIRK `[PRESERVE]`**: `Capacity_Limits_Penalty` and `Ramp_Limits_Penalty` are kept as 140-vectors (the file omits the outer `sum` at computation, lines 354–356) and summed inside the weight line: `Total_Penalty = 1e7*PB + 1e5*sum(Cap) + 1e7*sum(Ramp) + 1e5*POZ` (weights differ from all other ELD files).
  - Cost with valve point: `sum(a.*x.^2 + b.*x + c + |e.*sin(f.*(Pmin-x))|)`.
- **Porter must transcribe**: Data1 140×5 (lines 13–153), Data2 140×3 (lines 156–296), Data3 12×3, Data4 4×7, and the bounds list in `define_boundaries` case 17 (cross-check bounds == Data1 cols 1–2).
- **Probe risk**: none.

### Problems 18, 19, 20 — Hydrothermal scheduling, 4 hydro + 1 thermal, 24 h (T11.8–T11.10) — difficulty M (one engine, 3 variants)
- **D=96** each; bounds: `repmat(Qmin,1,24)` / `repmat(Qmax,1,24)` with `Qmin=[5 6 10 13]`, `Qmax=[15 15 30 25]` (4 reservoir discharge rates per hour).
- **Chains**: `MY_FUNCTION_12_1/2/3` → `fn_HT_ELD_Case_1/2/3.m`. The three files are byte-similar; differences listed at the end.
- **Shared math** (`fn_HT_ELD_Case_*`):
  - `Input_Discharges = reshape(x,4,24)` (NO transpose — column j = hour j; consistent with the bound layout: x(1:4)=hour-1 discharges).
  - Inline data: `Power_Demand` 24 values (1370 1390 1360 1290 1290 1410 1650 2000 2240 2320 2230 2310 2230 2200 2130 2070 2130 2140 2240 2280 2240 2120 1850 1590); hydro power coefficients `C_Coefficients` 4×6 (c1..c6 per plant, file lines 16–19); `Inflow_Rate` 4×24 (lines 20–23); `Spillages = 0`.
  - Constants: `Ptmin=500, Ptmax=2500; PHmin=[0 0 0 0]; PHmax=[500 500 500 500]; Delay_Time=[2 3 4 0]; No_of_Upstreams=[0 0 2 1]; Vmin=[80 60 100 70]; Vmax=[150 120 240 160]; V_Initial=[100 80 170 120]; V_Final=[120 70 170 140]; Qmin/Qmax` as above.
  - Reservoir network (cascade): plant 3 receives plants 1,2; plant 4 receives plant 3. `Max_Delay=4`; `All_Discharges = [zeros(4,4), Input_Discharges]` (4 zero-history columns, same for spillages). Volume recursion for i=1..4, j=1..24:
    `Upstream(i,j) = sum_{k=i-Nup(i)}^{i-1} [ All_Discharges(k, j+4-Delay(k)) + All_Spillages(k, j+4-Delay(k)) ]`
    `V(i,j+1) = V(i,j) + Upstream(i,j) - Q(i,j) - Spill(i,j) + Inflow(i,j)`, with `V(:,1)=V_Initial`.
  - Per hour j (with `q = Q(:,j)'`, `v = V(:,j+1)'`):
    - Discharge-limit penalty: primitive vs [Qmin,Qmax] (with bound-respecting x this is 0).
    - Storage-limit penalty: primitive vs [Vmin,Vmax].
    - Hydro generation: `Ph = c1.*v.^2 + c2.*q.^2 + c3.*(v.*q) + c4.*v + c5.*q + c6`, then `Ph = Ph.*(Ph>0)` (negative→0 `[PRESERVE]`).
    - Hydro capacity penalty: primitive vs [PHmin,PHmax].
    - Thermal: `P_T = Demand(j) - sum(Ph)` (Power_Loss ≡ 0); thermal capacity penalty primitive vs [500,2500] (computed but see weights!); power-balance penalty `|Demand + 0 - sum(Ph) - P_T|` ≡ 0 by construction `[PRESERVE]`.
    - Cost: `5000 + 19.2*P_T + 0.002*P_T^2` (valve-point term `abs(700*sin(0.085*(Ptmin-P_T)))` is COMMENTED OUT in all three cases, despite Case 3's banner claiming valve-point `[PRESERVE]`).
  - **`[PRESERVE]` weight bugs (all three cases)**: `All_Penalty = 1e4*PB + 1e4*CLP_H + 1e4*CLP_H + 1e4*Discharge + 1e5*Storage (+ POZ term)` — the hydro capacity penalty is added TWICE and the THERMAL capacity penalty is computed but NEVER added.
  - End-volume penalty: `Reservoir_End = sum(|V(:,1)-V_Initial'|) + sum(|V(:,25)-V_Final'|)` (first term ≡ 0). **Total = sum(cost) + sum(All_Penalty) + 1e6*Reservoir_End**.
- **Case differences**:
  - Case 1 (P18): no POZ at all.
  - Case 2 (P19): POZ on discharges, zones per plant `[8,9] [7,8] [22,27] [16,18]`, weight **1e5**.
  - Case 3 (P20): same POZ computed but weight **0** (`0*POZ_Penalty`) → numerically identical to Case 1 for identical x `[PRESERVE — P18 and P20 should return the same values; good cross-check]`.
- **Data**: all inline. **Probe risk**: none.

### Problem 21 — Messenger (full mission) MGA-DSM trajectory (T12) — difficulty XL (shared with 22)
- **D=26**; bounds (define_boundaries case 21):
  `lo = [1900 2.5 0 0 100 100 100 100 100 100 0.01 0.01 0.01 0.01 0.01 0.01 1.1 1.1 1.05 1.05 1.05 -pi -pi -pi -pi -pi]`
  `hi = [2300 4.05 1 1 500 500 500 500 500 600 0.99 0.99 0.99 0.99 0.99 0.99 6 6 6 6 6 pi pi pi pi pi]`
  (matches `getlimit_messenger.m`; the `bounds` field inside the .mat differs and is unused — §3.6).
- **Chain**: `Calc_Fitx_2011` case 21 → `load('messengerfull.mat')` → `messengerfull(x, a.MGADSMproblem)` → `mga_dsm(t, problem)`.
- **Problem struct (from messengerfull.mat — embed as constants in C++)**:
  - `sequence = [3 2 2 1 1 1 1]` (Earth, Venus, Venus, Mercury×4) → N=7
  - `objective.type = 'orbit insertion'`, `objective.rp = 2640` (km), `objective.e = 0.704`
  - `yplot = 0`; `bounds` (lower/upper, unused at runtime)
  - Objective: `J = DVtot = sum(DV(1:7))` where `DV(7) = DVarr = |DVper − DVper2|`, `DVper = sqrt(DVrel² + 2·mu_Mercury/rp)`, `DVper2 = sqrt(2·mu_Mercury/rp − mu_Mercury/rp·(1−e))`. VINF is NOT added for 'orbit insertion'.
- **Decision vector semantics** (N=7): t1 departure epoch (MJD2000); t2 = VINF (km/s); t3,t4 = u,v sphere-point for escape direction; t5..t10 = 6 leg times-of-flight (days); t11..t16 = 6 DSM fractions alpha; t17..t21 = 5 non-dimensional flyby perigee radii (planets 2..6 of the sequence); t22..t26 = 5 b-plane rotation angles gamma.
- **Probe risk**: see §4 (complex-intermediate guard; verify probes in MATLAB).

### Problem 22 — Cassini 2 MGA-DSM trajectory (T13) — difficulty XL (shared engine)
- **D=22**; bounds (define_boundaries case 22):
  `lo = [-1000 3 0 0 100 100 30 400 400 0.01 0.01 0.01 0.01 0.01 1.05 1.05 1.15 1.7 -pi -pi -pi -pi]`
  `hi = [0 5 1 1 400 500 300 1600 2200 0.9 0.9 0.9 0.9 0.9 6 6 6.5 291 pi pi pi pi]`
  **`[PRESERVE]` element 9 lower bound = 400 in define_boundaries (GSK-canonical), although getlimit_cassini2.m and the .mat bounds field say 800 (official GTOP).**
- **Chain**: `Calc_Fitx_2011` case 22 → `load('cassini2.mat')` → `cassini2(x, a.MGADSMproblem)` → `mga_dsm`.
- **Problem struct (from cassini2.mat)**: `sequence = [3 2 2 3 5 6]` (E V V E J S) → N=6; `objective.type = 'total DV rndv'` → **`J = DVtot + VINF`** with `DV(6) = DVarr = DVrel` (relative arrival speed at Saturn); `yplot=0`.
- **Decision vector** (N=6): t1 epoch; t2 VINF; t3,t4 u,v; t5..t9 = 5 ToF; t10..t14 = 5 alpha; t15..t18 = 4 flyby radii; t19..t22 = 4 gamma.

---

## 6. `mga_dsm.m` internal structure (1274 lines) — what WP-C must transcribe

Only the code paths for `'orbit insertion'` (P21) and `'total DV rndv'` (P22) are live; `gtoc1`/`deflection demo`/`time to AUs`/`rndv`/`total DV orbit insertion` branches and `CUSTOMeph`/`time2distance` are dead for this suite (port optional).

| Lines | Unit | Notes |
|---|---|---|
| 1–81 | header & decision-vector doc | keep as reference |
| 86–103 | objective unpack | only `rp_target`/`e_target` (P21) needed |
| 113–131 | constants | `mu(1..6) = [22321, 324860, 398601.19, 42828.3, 126.7e6, 37.93951970883e6]` km³/s²; `muSUN = 1.32712428e11`; planet radii `RPL = [2440 6052 6378 3397 71492 60330]` km |
| 137–173 | decision-vector unpack | non-'time to AUs' branch: `tof(i)=t(i+4)`, `alpha(i)=t(N+i+3)`, `rp_non_dim(i)=t(i+2N+2)` (i=1..N−2), `gamma(i)=t(3N+i)` |
| 179–222 | planet states | loop over sequence: `[r(:,i),v(:,i)] = pleph_an(T, seq(i))` at cumulative epochs `T = tdep + sum(tof(1:i-1))`; `rp(i) = rp_non_dim(i)*RPL(seq(i+1))` |
| 230–265 | first leg | departure frame `iP1 = v1/|v1|`, `zP1 = (r1×v1)/|..|`, `jP1 = zP1×iP1`; `theta=2π·u`, `phi=acos(2v−1)−π/2`; `vinf = VINF·(cosθcosφ·iP1 + sinθcosφ·jP1 + sinφ·zP1)`; propagate `r1, v1+vinf` for `alpha(1)·tof(1)` days (`propagateKEP`); Lambert from DSM point to planet 2 over remaining time; `DV(1)=|v_lambert_start − v_arrived|` |
| 271–317 | intermediate legs i=1..N−2 | unpowered swingby at planet i+1: `vrel_in = v_sc_in − v_planet`; `e = 1 + rp(i)/mu(i+1)·|vrel_in|²`; `beta_rot = 2·asin(1/e)`; basis `ix = vrel_in/‖·‖`, `iy = unit(ix × v_planet/‖·‖)`, `iz = ix×iy`; `vrel_out = |vrel_in|·(cosβ·ix + cosγ·sinβ·iy + sinγ·sinβ·iz)`; then propagate `alpha(i+1)·tof(i+1)` days, Lambert to next planet, `DV(i+1)` |
| 320–346 | arrival | `DVrel = |v_planetN − v_sc_inN|`; P21: `DVarr = |DVper−DVper2|` (formulas in §Problem 21); P22: `DVarr = DVrel`; `DV(N)=DVarr` |
| 354–364 | totals | `DVtot = sum(DV)` (non-gtoc1); `DVvec=[VINF;DV]` (output only) |
| 371–473 | objective switch | P21 `'orbit insertion'`: `J=DVtot`; P22 `'total DV rndv'`: `J=DVtot+VINF` |
| 479–520 | `propagateKEP(r0,v0,t,mu)` | Kepler propagation via IC2par→mean-anomaly advance→M2E→par2IC; `[PRESERVE]` the DD rotation hack: if `|abs(ih(3))−1| < 1e-3` rotate frame by `[1 0 0; 0 0 1; 0 −1 0]` before/after to avoid Euler-angle singularities |
| 524–570 | `IC2par` | classic elements; `E(6)` = eccentric anomaly (ellipse) or GUDERMANNIAN (hyperbola); `real(acos(...))` only on the `ni` line; other `acos` calls unguarded (complex risk, §4) |
| 574–579 | `ni2E` | true→eccentric/Gudermannian |
| 584–647 | `par2IC` | elements→state; separate ellipse/hyperbola branches (hyperbola uses tan(EA) parametrization with `dNdzeta`) |
| 652–855 | `lambertI(r1,r2,t,mu,lw)` | Izzo Lambert. Non-dimensionalize by R=|r1|; `theta = acos(r1·r2/|r2|)`, flipped to `2π−θ` if `lw` (lw chosen by caller from sign of `(rd×r2)_z`); chord/semi-perimeter; N=0 branch only: secant ("regula-falsi-like") iteration on `y=log(tof(x))−log(t)` starting from `x = log(1±0.5233)`, `tol=1e-11`, loop while `err>tol && y1~=y2` (NO iteration cap in N=0 branch `[PRESERVE]`); reconstruct: `a=am/(1−x²)`, ellipse/hyperbola psi & eta, `p`, `sigma1`, `ih=vers(r1×r2)` (negated for lw); `vr1=sigma1, vt1=sqrt(p)`, `v1=vr1·r1+vt1·(ih×r1)`; `vt2=vt1/r2mod`, `vr2=−vr1+(vt1−vt2)/tan(θ/2)`, re-dimensionalize |
| 860–877 | `x2tof` | tof from x via alfa/beta (ellipse/hyperbola) |
| 881–889 | `tofabn` | Lagrange tof expression |
| 892–904 | `vers`, `vett` | unit vector; cross product |
| 910–1091 | `pleph_an(mjd2000, planet)` | analytic ephemerides planets 1–9 in ecliptic J2000: `T=(mjd2000+36525)/36525` Julian centuries since 1900; per-planet classical-element polynomials (lines 971–1056, Mercury..Neptune; Pluto 1060–1074 is a 5th-order fit in `mjd2000/36525`); `KM=1.495978706910000e8` AU→km, deg→rad, `E(6)=mod(M,2π)` → M2E → `conversion` |
| 1095–1135 | `conversion(E)` | elements→(r,v) with `muSUN = 1.327124280000000e11` |
| 1140–1151 | `M2E(M,e)` | Newton, guess `E=M+e·cos(M)`, tol 1e-10, ≤100 iters |
| 1155–1170 | `E2M` | inverse (Gudermannian branch for e>1) |
| 1176–1212 | `CUSTOMeph` | DEAD for P21/22 (sequence entries <10); the only place using `global AU mu` |
| 1216–1262 | `time2distance` | DEAD ('time to AUs' only) |
| 1266–1273 | `mjd20002jed`, `mjd2jed` | date helpers (used only by dead paths) |

**`[PRESERVE]` three DIFFERENT solar gravitational constants coexist**: `muSUN = 1.32712428e11` (main function, line 120 — feeds `propagateKEP` and `lambertI`, i.e. all spacecraft arcs); `mu = 1.327124400180000e11` (local in `pleph_an`, line 953 — defined but never actually consumed: planetary states come from `conversion`); `muSUN = 1.327124280000000e11` (local in `conversion`, line 1099 — generates planet position/velocity from elements). Do not "unify" them; replicate each in its own scope.

---

## 7. Port difficulty & work packages (3 parallel packages, ~equal effort)

Per-problem ratings: P1 S · P2 S · P3 M · P4 M(+fidelity XL) · P5 M · P6 M(shares 5) · P7 S · P8 M · P9 L · P10 M · P11 M · P12 M(shares 11) · P13 M · P14 S(shares engine) · P15 M · P16 S(shares) · P17 L(data) · P18 M · P19 S(shares) · P20 S(shares) · P21 XL · P22 XL(shares 21).

- **WP-A — closed-form physics + ODE (P1–P8, P10)**, ≈ S×3 + M×6. Contents: FM, Lennard-Jones, Tersoff×2, radar, TNEP, antenna, plus the two ode45 problems. The dominant task is a bit-faithful MATLAB `ode45` re-implementation (Dormand–Prince RK5(4), MATLAB initial-step heuristic, PI error controller, refine=4 dense output) shared by P3/P4. Everything else is direct transcription from §5.
- **WP-B — power-systems family (P9, P11–P20)**, ≈ L + M×4 + S×5 + L(data). Contents: one shared dispatch-penalty engine (violation primitive, POZ primitive, valve-point cost, B-loss with 4-decimal rounding, ramp limits static vs chained, hydro cascade), ten thin per-problem data modules (incl. the 140-unit tables), and the EBE pricing problem (Ybus + inverse + PTDF tensor — needs a small dense linear-algebra helper; 29×29 inverse, or LU solve replicated to match `inv`). Cross-check: P18 ≡ P20 outputs.
- **WP-C — spacecraft trajectories (P21–P22)**, ≈ XL. Contents: `mga_dsm` per §6 (Lambert solver, analytic ephemerides, Kepler propagation, swingby geometry), the two embedded problem structs, complex-number policy, probe verification against MATLAB with special attention to `acos` domain edges.

Suggested sequencing inside each WP: transcribe data → port → run the three probes → reconcile.

---

## 8. MATLAB-side probe-generation snippet (for whoever runs MATLAB once)

```matlab
% run from the cec2011 reference folder
fid = fopen('cec2011_probes.txt','w');
for fn = 1:22
    [n, xmax, xmin] = define_boundaries(fn);
    lo = xmin(:)'; hi = xmax(:)';
    P = [ (lo+hi)/2 ; lo+0.25*(hi-lo) ; lo+0.75*(hi-lo) ];
    f = Calc_Fitx_2011(P, fn, 3);
    fprintf(fid, '%d %d %.17g %.17g %.17g\n', fn, n, f(1), f(2), f(3));
end
fclose(fid);
```
Expected specials: P2 mid → `Inf`; P5/P6 mid → `0` (NaN→0); P18 row == P20 row.
