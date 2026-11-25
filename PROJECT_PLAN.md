# Project Plan: Physics-of-Failure Prognostics for Payment Terminals

**Full title:** Physics-of-Failure Informed Prognostics and Annealing-Based Field-Service Optimisation for Nationally Distributed Payment Terminal Fleets under Tropical Operating Conditions

| | |
|---|---|
| Student | Lavindu Perera |
| Department | Department of Physics, University of Sri Jayewardenepura |
| Supervisor | Prof. P. K. D. Duleepa P. Pitigala |
| Industry partner | Epic Lanka (Pvt) Ltd |
| Duration | 26 weeks: week 1 began **2 November 2026**, week 26 ends **2 May 2027** |
| Status (25 Nov 2026) | Week 4. Proposal presented. Data received. Starting the code. |

---

## Contents

1. [The project in one page](#1-the-project-in-one-page)
2. [Research questions and hypotheses](#2-research-questions-and-hypotheses)
3. [What we know so far](#3-what-we-know-so-far)
4. [Data](#4-data)
5. [The physics](#5-the-physics)
6. [Prognostics, uncertainty and calibration](#6-prognostics-uncertainty-and-calibration)
7. [Priority rules](#7-priority-rules)
8. [Planner (statistical mechanics)](#8-planner-statistical-mechanics)
9. [Bench experiment](#9-bench-experiment)
10. [Evaluation and experiments](#10-evaluation-and-experiments)
11. [Timeline](#11-timeline)
12. [Code: structure, set-up and build order](#12-code-structure-set-up-and-build-order)
13. [Open questions and items to check](#13-open-questions-and-items-to-check)
14. [Data protection rules](#14-data-protection-rules)
15. [Key references](#15-key-references)
16. [Glossary](#16-glossary)

---

## 1. The project in one page

**Problem.** Epic Lanka maintains a large share of Sri Lanka's ~131,000 card-payment terminals. Service is reactive: a terminal is fixed after it fails. Epic's repair data shows the most common "battery" failure is the **backup coin cell**. When it runs down, the terminal's security circuit declares a **tamper** and locks itself.

**Approach.** Two physics-based halves:

1. **Physics of failure → prognostics.** Model how each failure mechanism progresses:
   - coin-cell depletion is the primary mechanism;
   - lithium-ion fade, solder fatigue, humidity corrosion and external shocks compete with it;
   - the mechanisms are combined as competing risks;
   - a small neural network corrects what the physics misses;
   - the output is a calibrated probability of remaining life for every terminal.
2. **Statistical mechanics → planning.** Turn each remaining-life distribution into a priority (four rules compared), then build weekly visit plans by **annealing a Potts spin system**, benchmarked against Google OR-Tools.

**Contribution.**
- A mechanistic failure model for payment terminals, fitted to field voltages.
- The first controlled comparison of remaining-life priority rules inside a routing problem.
- A Potts-annealing planner.
- An open synthetic benchmark.
- For Epic: a coin-cell replacement policy and a weekly service plan.

**Pipeline:**

```
Epic data + climate + bench  →  physics models  →  competing risks + ML correction
   →  calibrated remaining life  →  priority rules A–D  →  Potts annealing planner
   →  weekly plan  →  evaluation (720-run factorial experiment)
```

---

## 2. Research questions and hypotheses

| | Research question |
|---|---|
| **RQ1** | Can a physics model of coin-cell depletion, with Li-ion, solder, humidity and shock as competing risks, predict tamper lockouts and failures, and extrapolate to unseen conditions better than a data-only model? |
| **RQ2** | How do parameter, climate and model uncertainty propagate into remaining-life predictions, and can the distribution be calibrated? |
| **RQ3** | Do four rules for turning a remaining-life distribution into a priority give different plans and outcomes, and how does this depend on uncertainty? |
| **RQ4** | Can annealing of a Potts spin system plan visits and routes competitively with a classical solver? |

| | Hypothesis (stated so it can fail) | Test |
|---|---|---|
| **H1** | The physics-informed hybrid beats a data-only model on held-out conditions (hottest districts, or oldest serial cohorts) | Lower negative log-likelihood (NLL) |
| **H2** | Rules rank terminals differently, more so as uncertainty grows | Kendall's τ < 0.7 between rules |
| **H3** | Rule D lowers the tail risk of unplanned failures at a measurable travel cost | Lower 95 % CVaR of failures |
| **H4** | Annealed routes come within 5 % of OR-Tools, with every plan feasible | Relative gap ≤ 5 % |
| **H5** | Coin cells deplete mainly with unpowered time; voltage falls with age | Fitted unpowered share *u* differs by model; voltage–age trend |

Objectives O1–O6 are in the proposal (`docs/`).

---

## 3. What we know so far

### 3.1 From Epic's first repair log (2,113 jobs, 2,007 terminals)
- The battery-voltage column is the **coin cell**: about 3.05 V when healthy, 3.0–3.4 V after replacement.
- Tamper fault: **56 %** of jobs at ≤ 3.0 V, against **11 %** above 3.0 V (odds ratio ≈ 10).
- Older VX520 serial blocks (260–288) have 20–28 % of cells at or below 3.0 V, against 6–8 % in newer blocks (321–333).
- **VX675** portable: coin cell replaced in 58 % of jobs.
- External damage (spill, mains surge, user damage, drop): **18 %** of jobs.
- Most common faults: printer 22 %, keypad 19 %, tamper 16 %, software 12 %.

### 3.2 From the database backup (export query, jobs since 2024)
- 2,737 repair jobs from 2024 to May 2026 in the backup.
- Location found for **64 %** of jobs. A district was extracted for **95 %** of those with location text (60 % of all jobs).
- Coin-cell voltage: 86 % of jobs. Faults: 88 %. Coin cell replaced: 25 %.
- Installation date: 59 %. Previous coin-cell replacement known: 16 % (exact cell age). Storage time: 32 % (median 32 days).
- **Coin-cell types** (from `hw_parts`): VX520 and VX680 use a **CR2450** (600 mAh), VX675 a **CR2032**, X990 a **CR2430**.

### 3.3 First result: coin-cell life (preliminary, 125 cases)
Coin-related returns where the cell's earlier fitting date is known:

| Model | Cell | Cases | Median life |
|---|---|---|---|
| VX520 | CR2450 | 47 | 3.4 years |
| VX675 | CR2032 | 48 | 3.7 years |
| X990 | CR2430 | 30 | **0.9 years** |

The short X990 life is the most interesting open question. It could be a higher backup current, more unpowered time, or the smaller cell; the bench experiment separates these.

---

## 4. Data

### 4.1 Files received

| File | Contents | Notes |
|---|---|---|
| `All_Terminal_Details_List.xlsx` | 2,113 repair jobs: bank, model, job no., serial, fault, coin-cell V (before/after), service, cause | Mostly 2024 or earlier; no dates |
| `Tamper_code_x990.xlsx`, `Evo_520_Tamper_code_log_ALL.xlsx` | Tamper-code reference tables | X990 code 2000000 = "coin cell … under 2 V" |
| `In_Terminal_Report.xlsx` | 3,037 intakes, 2 Jan 2024 – 20 Nov 2026 | "In Date" = `hw_terminals.saved_at` |
| `Out_Terminal_Report.xlsx` | 1,802 releases | `Released_Date` |
| `Quatation_Report.xlsx` | 558 repair quotations | Meaning to confirm with Epic |
| `hardwarelive_bkp.sql` | Repair workshop DB (37 MB) | Backup of 4 June 2026 |
| `tech_operation.sql` | Field operations DB (306 MB) | Backup of 4 June 2026 |
| `dfcc_pos_operation_bkp.sql` | DFCC terminal list (0.3 MB) | |
| `new_itsup_bkp.sql` | IT helpdesk (10 MB) | Not needed |

### 4.2 Database tables that matter

**`hardwarelive` (repair workshop)**

| Table | Key columns | Use |
|---|---|---|
| `hw_terminals` | `jobcard_no`, `saved_at` (**UTC**, add 5:30), `bank`, `serialno`, `model`, `Released_Date`, `fo_fault` | One row per repair job |
| `hw_repair` | `jobcard_no`, `Bat_V` (coin-cell V), `Saved_Date` | 42,140 rows, 2019–2026 |
| `hw_repair_fault` + `hw_terminal_fault` | `Fault_id` → `Fault_Name` | e.g. "Tamper-7FFFFF" (7,524) |
| `hw_repair_addpart` + `hw_parts` | `Part_ID`, `part_name` | Coin-cell replacements ("Coin Battery …") |

**`tech_operation` (field operations)**

| Table | Key columns | Use |
|---|---|---|
| `jobcard` | `jobcard_no`, `tid`, `merchant`, `serialno`, `jc_date` | Merchant on the job card (often blank) |
| `breakdown` | `fault_serialno`, `replaced_serialno`, `tid`, `merchant`, `tdate`, `zone_id` | Field visits: where a faulty unit was removed |
| `newinstall` | `serialno`, `tid`, `merchant`, `tdate` | Installation date and place |
| `terminal_replacement` | `based_serialno`, `replaced_serialno`, `merchant`, `tdate` | Swaps |
| `bank` | `bank`, `bankname`, maintenance flags | Client codes |

**Client codes.**
- **GP** = Global Payment: repair only, so Epic has no merchant locations for these terminals.
- **NTB** = Nations Trust Bank: field records stop in 2020.
- Others include **PB** (People's Bank), **BOC** (Bank of Ceylon), **DFCC**, **SAM** (Sampath), **SEYB** (Seylan) and **HNB**.

**Location.** There is no district column; `zone_id` is mostly 0. The town appears only inside the merchant name/address text, so `scripts/extract_district.py` converts it to a district using `data/reference/lk_town_district.csv`.

### 4.3 The export (`sql/terminal_location_export.sql`)
One row per repair job since `@from_date` (default 2024-01-01). It reads data only and creates temporary tables. Tested on the backup: 2,737 rows in about 5 seconds.

Columns:
- `jobcard_no`, `in_date`, `released`, `bank`, `serialno`, `model`, `tid`
- `location_text` (**merchant text: delete after extracting the district**), `location_source`, `zone_id`
- `install_date`, `first_seen_date`, `prev_coin_replaced_date`, `prev_repair_date`, `prev_repairs`
- `coin_cell_v`, `coin_cell_replaced`, `faults`
- `release_before_install`, `storage_days`

### 4.4 External data
- **ERA5 hourly climate** (temperature, dew point → relative humidity) per district: Copernicus Climate Data Store (free account, `cdsapi`).
- **Coin-cell datasheets:** Panasonic CR2450 / CR2032, plus the CR2430 of the brand Epic fits. Take capacity, discharge curve, self-discharge and temperature range.
- **Road travel times:** OpenStreetMap / OSRM, for the planner.
- **CVRPLIB** instances (`vrplib`) to validate the routing code.

---

## 5. The physics

Equation numbers follow the written proposal.

### 5.1 Arrhenius law (shared by all wear-out mechanisms)
$$ r(T) = A\,\exp\!\left(-\frac{E_a}{RT}\right) \tag{1}$$

### 5.2 Primary mechanism: coin-cell depletion
Charge balance: the cell drains through the backup current when the terminal is unpowered, and through self-discharge.
$$ \frac{dQ}{dt} = -\,u(t)\,I_b(T) - k_{sd}(T)\,Q \tag{2}$$
$$ I_b(T)=I_0\exp\!\left[-\frac{E_b}{R}\left(\frac1T-\frac1{T_{ref}}\right)\right],\qquad k_{sd}(T)=k_0\exp\!\left[-\frac{E_{sd}}{R}\left(\frac1T-\frac1{T_{ref}}\right)\right] \tag{3}$$
$$ V(t)=V_{oc}(Q/Q_0)-I\,R_{int}(Q/Q_0,T);\qquad \text{tamper lockout when } V<V_{th} \tag{4}$$
$$ t_f=\frac1{k_{sd}}\ln\!\left[\frac{Q_0+uI_b/k_{sd}}{Q_{min}+uI_b/k_{sd}}\right]\approx\frac{Q_0-Q_{min}}{u\,I_b} \tag{5}$$

| Symbol | Meaning | Source |
|---|---|---|
| $Q_0$ | Usable capacity (mAh) | Datasheet (CR2450 ≈ 600 mAh) |
| $Q_{min}$ | Charge left at the voltage knee | Datasheet discharge curve |
| $u$ | Share of time with **no main power** (unplugged, and main battery flat or absent) | Storage days, field estimates, fitted from lifetimes |
| $I_b$, $I_0$, $E_b$ | Backup current, its value at 25 °C, its activation energy | **Bench experiment** (placeholder 10 µA) |
| $k_{sd}$ | Self-discharge, ≈ 1 % per year at room temperature | Datasheet / Linden's Handbook |
| $V_{th}$ | Lockout voltage (≈ 2–3 V) | Bench (Experiment 2), X990 tamper table |

**Identifiability.** Field lifetimes only reveal the product $u \times I_b$. The bench measurement of $I_b$ is what separates "more current" from "more unpowered time".

### 5.3 Competing mechanisms

**Li-ion fade (portables X990 and VX675):**
$$ Q_{loss}=A\,e^{-E_a/R(1/T-1/T_{ref})}\,h(\mathrm{SOC})\,t^{z}+B\,e^{-E_{a,c}/R(1/T-1/T_{ref})}N_{EFC}^{\,w},\quad z\approx0.5 \tag{6}$$

**Solder fatigue:**
$$ N_f=C(\Delta\varepsilon_p)^{-\beta}\;\Rightarrow\;N_f\propto(\Delta T)^{-n} \tag{7}$$
$$ N_f=\tfrac12\left(\frac{\Delta\gamma}{2\varepsilon_f}\right)^{1/c},\quad c=-0.442-6\times10^{-4}T_{SJ}+1.74\times10^{-2}\ln(1+360/t_D) \tag{8}$$
$$ AF=\left(\frac{\Delta T_t}{\Delta T_f}\right)^{n}\left(\frac{f_f}{f_t}\right)^{m}\exp\!\left[\frac{E_a}{k}\left(\frac1{T_{max,f}}-\frac1{T_{max,t}}\right)\right] \tag{9}$$

Three published Norris–Landzberg parameter sets disagree. Report the stability of the site ranking, not single lives.

**Humidity:**
$$ TTF=A_0\,RH^{-n}\exp(E_a/kT),\quad (n,E_a)=(2.66,0.79\,\text{eV})\text{ or }(3.0,0.9\,\text{eV}) \tag{10}$$
$$ \frac{dD_h}{dt}=\mathbb 1[RH_{local}>RH_{crit}]\;k_0\,RH_{local}^{\,n}\,e^{-E_a/kT}\,g(\mathrm{Cl}) \tag{11}$$

**External shocks** (spills, surges, drops):
$$ h_{shock}=\lambda_{liquid}+\lambda_{surge}+\lambda_{drop} \tag{12}$$

### 5.4 Combining mechanisms
$$ h_{sys}(t)=\sum_k h_k(t),\qquad R_{sys}(t)=\prod_k R_k(t) \tag{13}$$
Each wear-out mechanism has a lognormal life with its median set by the physics; Weibull is a check. A background hazard covers printer, keypad and software faults.

---

## 6. Prognostics, uncertainty and calibration

**Residual hybrid.** The network corrects the physics hazard; it does not replace it.
$$ \log h_k(t\mid\mathbf x)=\log h_k^{phys}(t\mid\mathbf x;\theta)+g_{\phi,k}(\mathbf x) \tag{14}$$

**Training loss.** Censored survival likelihood, plus a penalty that keeps survival curves decreasing over time (eq. 17 in the proposal). Terminals that haven't failed count as censored.

**Voltage observation model.** Every job with a voltage helps fit the model, not only failures.
$$ V_i^{obs}=V\big(Q_i(t_i;\theta,u_i,\mathbf T_i)\big)+\varepsilon_i,\quad\varepsilon_i\sim N(0,\sigma_V^2) \tag{18}$$

**Uncertainty: three nested layers.**
1. Model: a deep ensemble.
2. Parameters: priors on $I_0$, $E_b$, $Q_0$, $u$, the Norris–Landzberg sets and the humidity constants.
3. Future conditions: climate years and future unplugged time.

**Calibration gate (week 12).**
- Measures: expected calibration error (ECE), NLL and coverage.
- If miscalibrated, apply isotonic recalibration.
- Predictions must pass before the rules are compared.

**Remaining life for the planner:**
$$ P(\mathrm{RUL}>\tau\mid\text{working at }t_0)=\frac{R_{sys}(t_0+\tau)}{R_{sys}(t_0)} $$

**Train/test split.** Training, an in-distribution test set, and an **out-of-distribution test**: the hottest districts, or the oldest serial cohorts.

---

## 7. Priority rules

All four are rescaled to the range 0–1.

| Rule | Source | Priority |
|---|---|---|
| **A** Expected failure cost | Camci (2014, 2015) | $P(\text{fail within horizon }H)\times c_f$ (+ downtime cost) |
| **B** Renewal cost rate | Yildirim et al. (2017) | $g(\tau)=\dfrac{c_pR(\tau)+c_f(1-R(\tau))}{\int_0^\tau R(t)\,dt}$; priority = $1/\tau^*$ |
| **C** Optimised threshold | Zhu, Wang & Coit (2022) | Visit if damage $D>D^*$; $D^*$ tuned in simulation |
| **D** 5th-percentile remaining life | **Proposed here** | Priority = $1/\mathrm{RUL}_{5\%}$; α varied in sensitivity tests |

Costs needed from Epic: technician visit, repair, coin cell (in `hw_parts.Price`), and merchant downtime per day.

---

## 8. Planner (statistical mechanics)

**Metropolis rule:**
$$ p_{accept}=\min\{1,e^{-\Delta E/T}\} \tag{15}$$

**Parallel tempering swap:**
$$ p_{swap}=\min\{1,\exp[(\beta_a-\beta_b)(E_a-E_b)]\},\quad \beta=1/T \tag{16}$$

**Potts energy of a weekly plan.** Each terminal's spin $\sigma_i\in\{0,1,\dots,K\}$, where 0 means "not this week" and 1…K are days.
$$ E(\sigma)=-\sum_i\tilde w_i\,\mathbb 1[\sigma_i\neq0]+\lambda_d\sum_{i<j}d_{ij}\,\delta(\sigma_i,\sigma_j)\,\mathbb 1[\sigma_i\neq0] \tag{19}$$

**Daily limit:** $\sum_i\tau_i\,\delta(\sigma_i,k)\le L_k$ for every day $k$. Moves that break it are rejected.

**Method details.**
- Daily routes are annealed as visit orders with 2-opt moves.
- Benchmark against Google OR-Tools, and validate the routing code on CVRPLIB instances.
- Cooling is geometric, slowed near the peak of the specific heat $C(T)=\mathrm{Var}(E)/T^2$.
- Why Potts and not QUBO: a Potts spin enforces "one day per terminal" by construction, while penalty QUBOs fail beyond about 15 stops (Sinno et al. 2025).

**Epic inputs needed:** technician bases, working hours and visits per day.

---

## 9. Bench experiment

Full plan: `docs/Coin_Cell_Experiment_Plan.pdf`.

**Minimum (one afternoon).**
- Measure the backup current at room temperature on a retired **X990** and **VX520**.
- Replace the coin cell with a 3.00 V bench supply connected through a micro-ammeter, with mains unplugged.

**Full version.**
- **Exp. 1:** backup current at 25, 30, 35, 40, 45 and 50 °C. Wait 45 minutes at each step, then take 10 readings, one per minute. Repeat the run.
- **Exp. 2:** current against supply voltage from 3.2 V down to 2.0 V, and the lockout voltage (with an Epic technician present).
- **Exp. 3:** current while on mains power.
- **Exp. 4 (optional):** open-circuit and loaded voltage of 20–30 used cells.

**Analysis.**
- Plot $\ln I_b$ against $(1/T - 1/298.15)$.
- The slope gives $-E_b/R$ and the intercept gives $\ln I_0$.
- Worked example: if the current doubles from 25 °C to 45 °C, then $E_b \approx 27$ kJ/mol.

**Status.** Email drafted to Epic asking for retired terminals, a technician, cells, cell brand, how `Bat_V` is measured, and permission. Lab equipment requested via Prof. Pitigala.

---

## 10. Evaluation and experiments

**Factorial design:** 4 rules × 3 uncertainty levels × 3 geographies × 2 models (hybrid, data-only) × 10 seeds = **720 simulated service years**.

| Group | Metrics |
|---|---|
| Prediction | NLL, C-index, integrated Brier score, ECE, interval coverage |
| Decisions | Unplanned failures and tamper lockouts, merchant downtime-days, total cost, 95 % CVaR of failures, Kendall's τ between rules |
| Planning | Distance or travel time, gap to OR-Tools, runtime, feasibility |

**Statistics.** Paired comparisons across seeds, non-parametric tests with effect sizes and confidence intervals, and thresholds fixed in advance.

**Synthetic fleet.** It contains hidden effects the prediction model doesn't know about (different parameters, defects, random failures), so the test isn't circular. It is calibrated to the distributions in Epic's data.

**Physics validation before use.**
- Coin-cell model: reproduce the datasheet curve and the bench current.
- Li-ion model: reproduce Keil et al. (2016).
- Solder model: reproduce Norris–Landzberg's 13× predicted against 12.35× observed.

---

## 11. Timeline

Week *n* starts on 2 Nov 2026 + 7(*n* − 1) days.

| Weeks | Dates | Phase / task | Status |
|---|---|---|---|
| 1–3 | 2–22 Nov | Clean Epic data, data requests, proposal presentation | ✅ Done |
| **4** | **23–29 Nov** | **Gate 1:** data usable? → **Yes** (backup has dates, voltages, faults, install dates, districts for 60 %) | ✅ Passed |
| 4–5 | 23 Nov–6 Dec | **Build the data pipeline and exploration** (section 12.4, steps 1–2) | ⏳ Now |
| 5–8 | 30 Nov–27 Dec | Physics module: coin cell first, then Li-ion, solder, humidity, shocks; ERA5 pipeline | |
| 5–9 | 30 Nov–3 Jan | Bench experiment (at least the room-temperature current) | |
| 6–8 | 7–27 Dec | Synthetic fleet generator | |
| 8–11 | 21 Dec–17 Jan | Hybrid physics-informed model (residual ensemble) | |
| 10–12 | 4–24 Jan | Uncertainty (three-layer Monte Carlo) and recalibration | |
| **12** | **18–24 Jan** | **Gate 2:** calibration (ECE, NLL) | |
| 13–14 | 25 Jan–7 Feb | Priority rules A–D on a common scale | |
| 14–17 | 1–28 Feb | Potts assignment and parallel tempering | |
| 16–19 | 15 Feb–14 Mar | Route annealing against OR-Tools; CVRPLIB validation | |
| 6–18 | (optional) | IoT logger pilot (unplugged time, shop temperature and humidity) | Stretch |
| 19–22 | 8 Mar–4 Apr | Factorial experiments and statistical analysis | |
| 20–23 | 15 Mar–11 Apr | Dashboard prototype for Epic | Stretch |
| 21–26 | 22 Mar–2 May | Thesis writing, paper draft, viva preparation | |

---

## 12. Code: structure, set-up and build order

### 12.1 Folder structure
```
pof-prognostics/
├── PROJECT_PLAN.md          ← this file
├── README.md
├── requirements.txt
├── .gitignore
├── docs/                    ← proposal, experiment plan, script, decision log
├── references/              ← papers and datasheets (keep out of a public repo)
├── sql/
│   └── terminal_location_export.sql
├── scripts/
│   └── extract_district.py
├── data/                    ← NEVER committed to Git
│   ├── raw/                 ← .sql dumps and Epic .xlsx files (copy here)
│   ├── interim/             ← export CSV (contains merchant text: delete after use)
│   ├── processed/           ← clean, pseudonymised, district-tagged dataset
│   ├── reference/           ← lk_town_district.csv, cell parameters
│   └── climate/             ← ERA5 downloads
├── src/pofp/
│   ├── data/                ← loading, cleaning, pseudonymising
│   ├── climate/             ← ERA5 per district
│   ├── physics/             ← coincell.py, liion.py, solder.py, humidity.py, shocks.py
│   ├── prognostics/         ← competing risks, fitting, ensembles, calibration
│   ├── rules/               ← rules A–D
│   ├── planner/             ← potts.py, routes.py, ortools_baseline.py
│   └── sim/                 ← synthetic fleet
├── notebooks/               ← 01_explore.ipynb, 02_coincell_fit.ipynb, …
└── tests/                   ← datasheet / published-result checks (pytest)
```

### 12.2 What to copy into the folder
| Put | Where |
|---|---|
| The 4 `.sql` dumps and all Epic `.xlsx` files | `data/raw/` |
| Coin-cell datasheets (CR2450, CR2430, CR2032) | `references/datasheets/` |
| The literature PDFs | `references/papers/` |
| ERA5 API key (`~/.cdsapirc`) | Your home folder, **not** the project |

### 12.3 Set-up
1. **Python 3.11+** and a virtual environment: `python -m venv .venv`, activate it, then `pip install -r requirements.txt`.
2. **MySQL 8 or MariaDB 10.x** locally, to load the dumps:
   ```sql
   CREATE DATABASE hardwarelive; CREATE DATABASE tech_operation; CREATE DATABASE dfcc_pos_operation;
   ```
   ```bash
   mysql -u root -p hardwarelive       < data/raw/hardwarelive_bkp.sql
   mysql -u root -p tech_operation     < data/raw/tech_operation.sql
   mysql -u root -p dfcc_pos_operation < data/raw/dfcc_pos_operation_bkp.sql
   ```
   If the import complains about dates such as `0000-00-00`, run `SET GLOBAL sql_mode='';` first.
3. **VS Code extensions:** Python, Jupyter, a SQL client (for example "SQLTools" with its MySQL driver), and a Markdown preview with maths support (for example "Markdown Preview Enhanced").
4. **Git:** `git init`. The `.gitignore` already excludes `data/` and the dumps.

### 12.4 Build order (checklist)

**Step 1: data pipeline (this week)**
- [ ] Load the dumps into local MySQL/MariaDB.
- [ ] Run `sql/terminal_location_export.sql` and save the result to `data/interim/export.csv`.
- [ ] Run `python scripts/extract_district.py data/interim/export.csv data/reference/lk_town_district.csv data/interim/export_district.csv`.
- [ ] Check `*_unmatched_towns.csv`, add missing towns to the lookup and run again.
- [ ] Pseudonymise `serialno` and `tid` (salted hash), normalise model names into families (VX520 / VX675 / VX680 / X990 / other), clean voltages (keep 0–4 V), and parse faults into flags (tamper, coin, printer, keypad, liquid…).
- [ ] Save `data/processed/jobs.parquet`, then **delete `export.csv`**.

**Step 2: exploration**
- [ ] Coin-cell lifetimes by model (the 0.9 / 3.4 / 3.7-year medians).
- [ ] Voltage against age (`first_seen_date`, `install_date`).
- [ ] Tamper rate against voltage band.
- [ ] Storage-time distribution.
- [ ] Monthly intake, and the spikes (Sep 2024, Jan–Feb 2025, Jul 2026).
- [ ] Jobs per district.

**Step 3: coin-cell physics** (`physics/coincell.py`)
- [ ] Equations (2)–(5), with cell parameters per model from datasheets.
- [ ] Tests: reproduce the datasheet discharge curve; life scales as 1/*u*.

**Step 4: fit to data**
- [ ] Estimate the drain $u\,I_b$ per model from lifetimes (with censoring) and voltages, equation (18).
- [ ] Once the bench result arrives, split it into $u$ and $I_b$.

**Step 5: climate**
- [ ] ERA5 hourly 2019–2026 for district centres.
- [ ] Join to jobs; test the temperature effect.

**Steps 6–8**
- [ ] Competing risks and the hybrid model.
- [ ] Uncertainty and calibration.
- [ ] Synthetic fleet.
- [ ] Rules A–D.
- [ ] Potts planner and OR-Tools baseline.
- [ ] Factorial experiment.

**Good habits**
- Keep a **decision log** (`docs/decisions.md`): what you changed and why.
- Fix random seeds and record package versions.
- Write a small test for every physics function: reproduce a datasheet or published number.
- Commit often, and never commit data.

---

## 13. Open questions and items to check

**Ask Epic** (one message):
- [ ] Written permission to use the data in the thesis and in publications.
- [ ] Bench-experiment items: retired X990 and VX520 (VX675 if possible), technician time, new and used coin cells, cell brand.
- [ ] How `Bat_V` is measured: cell in or out, and which meter.
- [ ] Causes of the intake spikes (Sep 2024, Jan–Feb 2025, Jul 2026).
- [ ] Meaning of the Quotation Report.
- [ ] GP locations (district only, via Global Payment) and NTB field records after 2020.
- [ ] Whether VeriCentre stores terminal last-contact times (would help estimate *u*).
- [ ] Later: costs, technician bases, working hours, visits per day.
- [ ] Optional, near the end: re-run the export on the live system (adds Jun–Nov 2026).

**Ask Prof. Pitigala:**
- [ ] Is a laboratory experiment expected in the honours project?
- [ ] Lab space and equipment: µA meter, power supply, oven or incubator, thermocouple.
- [ ] Risk-assessment process.
- [ ] Target journal or conference.

**Verify before submission:**
- [ ] CBSL figure of 131,029 terminals (end 2024).
- [ ] Sign of the frequency exponent in Pan et al. (2005) against JEP122H.
- [ ] Year of the Engelmaier reference.
- [ ] Author lists for the Auburn isothermal-ageing study, Sinno et al. (2025) and Lam et al. (2025).
- [ ] Linden's Handbook self-discharge figure (~1 % per year).
- [ ] The functional forms of *h*(SOC) and *g*(Cl): to be fitted or assumed, and stated as such.
- [ ] Review `lk_town_district.csv` (drafted from general knowledge).

---

## 14. Data protection rules

- **No transaction, merchant-identity or cardholder data** in any analysis output, thesis or paper.
- `location_text` (merchant names and addresses) is used **only** to extract the town. Delete it afterwards.
- Pseudonymise serial numbers and terminal IDs (T0001…) before analysis. Don't report client bank names in results.
- The dumps also contain staff logins, contact details and helpdesk tickets. Don't open those tables, don't copy them, and keep the files encrypted.
- Store raw data only on your own encrypted disk. Never commit it to Git or upload it to public services.
- Bench work uses retired terminals only. Don't read memory, bypass security, or publish photos of security features without Epic's approval.
- Delete the dumps at the end of the project, or as Epic requires.

---

## 15. Key references

**Physics of failure**
- JEDEC JEP122H (failure mechanisms); JESD91B; JESD47I; JESD22-A104.
- Reddy (ed.), *Linden's Handbook of Batteries*, 4th ed., 2011 (lithium primary cells).
- Roy, Mukhopadhyay & Mahmoodi-Meimand (2003), *Proc. IEEE* 91(2): CMOS leakage.
- PCI SSC, *PTS POI Modular Security Requirements* (tamper response).
- Ploehn, Ramadass & White (2004): diffusion-limited SEI. Keil et al. (2016): calendar ageing. Wang et al. (2011): cycle ageing. Lam et al. (2025).
- Coffin (1954); Manson (1953); IPC-9701; Engelmaier; Norris & Landzberg (1969); Pan et al. (2005); Lall et al. (2012).
- Peck (1986); Hallberg & Peck (1991); Verdingovas et al. (2015); ISO 9223.

**Prognostics, machine learning and uncertainty**
- Li et al. (2024) and Deng et al. (2023): physics-informed RUL reviews.
- Sankararaman (2015): uncertainty in RUL.
- Lakshminarayanan et al. (2017): deep ensembles.
- Kuleshov et al. (2018): calibration.
- Escobar & Meeker; Weibull (1951).

**Maintenance and routing**
- Camci (2014, 2015); Yildirim, Gebraeel & Sun (2017); Zhu, Wang & Coit (2022); Irawan et al. (2017); Schrotenboer et al. (2018); Käslin et al. (2025).

**Statistical mechanics and optimisation**
- Metropolis et al. (1953); Kirkpatrick, Gelatt & Vecchi (1983).
- Wu (1982): Potts model; Hukushima & Nemoto (1996): parallel tempering; Lucas (2014): Ising formulations.
- Sinno et al. (2025): QUBO limits.
- Uchoa et al. (2017): CVRPLIB; Braekers et al. (2016): VRP review.

The full list is in the proposal (`docs/`).

---

## 16. Glossary

| Term | Meaning |
|---|---|
| **Coin cell** | Small 3 V lithium primary cell (CR2450 etc.) that powers the security circuit when the terminal has no main power |
| **Tamper / lockout** | The terminal detects a possible attack (or a weak coin cell), erases its keys and stops working until repaired |
| **u** | Share of time a terminal has no main power, so its coin cell is draining |
| **RUL** | Remaining useful life: time left before failure |
| **Competing risks** | Several failure mechanisms; the terminal fails when the first one does |
| **Censored** | A terminal that has not failed yet: we only know its life is longer than observed |
| **Calibration** | Predicted probabilities match observed frequencies (10 % predicted → about 10 % fail) |
| **Potts spin** | A variable that takes one of *q* values; here, the day a terminal is visited |
| **Simulated annealing** | Optimisation by slowly "cooling" a system while accepting moves with Boltzmann probability |
| **Parallel tempering** | Several annealing copies at different temperatures that swap states |
| **QUBO** | Problem written as yes/no variables with a quadratic score; rules enforced by penalties |
| **ERA5** | Global hourly climate reanalysis from ECMWF / Copernicus |
| **CVaR** | Conditional value at risk: the average of the worst 5 % of outcomes |
