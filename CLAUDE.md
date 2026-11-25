# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

B.Sc. Honours (Physics) research code: physics-of-failure prognostics for Epic Lanka's payment-terminal fleet, plus a statistical-mechanics (Potts annealing) field-service planner. **`PROJECT_PLAN.md` is the source of truth.** It holds the equations (numbered to match the proposal in `docs/`), the data dictionary, the build checklist (§12.4) and the timeline. Check it before you design anything, and cite its equation numbers in code and docstrings. Record significant choices in `docs/decisions.md` (date | decision | reason | affects).

Status (late Nov 2026): the data pipeline is in progress. `src/pofp/*` subpackages are empty stubs, and so far the only working code is `sql/terminal_location_export.sql` and `scripts/extract_district.py`.

## Commands

```bash
python -m venv .venv && .venv\Scripts\activate      # Windows; Python 3.11+
pip install -r requirements.txt                      # torch / ortools / vrplib are commented out: add them when those stages start
pytest                                               # tests/ is empty so far
pytest tests/test_coincell.py::test_name             # single test
```

There is no `pyproject.toml`, so `pofp` isn't installed. Run from the repo root with `PYTHONPATH=src` (or add packaging) to import it.

Data pipeline (step 1):
1. Load the dumps in `data/raw/` into local MySQL/MariaDB as the databases `hardwarelive`, `tech_operation` and `dfcc_pos_operation` (`SET GLOBAL sql_mode='';` if `0000-00-00` dates fail).
2. Run `sql/terminal_location_export.sql` (MySQL 5.7-compatible: no CTEs or window functions; temp tables only, read-only) and save the result as `data/interim/export.csv`.
3. `python scripts/extract_district.py data/interim/export.csv data/reference/lk_town_district.csv data/interim/export_district.csv`. Review `*_unmatched_towns.csv`, add towns to the lookup and run again.
4. Next (not yet written): pseudonymise `serialno`/`tid` (salted hash), map models to families (VX520/VX675/VX680/X990/other), keep voltages in 0–4 V, parse faults into flags, write `data/processed/jobs.parquet`, then delete `export.csv`.

## Architecture (planned modules in `src/pofp/`)

Pipeline: Epic data + ERA5 climate + bench measurements → `physics` → `prognostics` → `rules` → `planner`, evaluated in `sim`.

- `data/`: loading, cleaning, pseudonymising the export.
- `climate/`: ERA5 hourly temperature and dew point (→ RH) per district centre via `cdsapi`. The key lives in `~/.cdsapirc`, never in the repo.
- `physics/`: one file per mechanism (`coincell.py`, `liion.py`, `solder.py`, `humidity.py`, `shocks.py`). **Coin-cell depletion is the primary mechanism** (eqs 2–5): a charge balance driven by backup current `I_b(T)` during unpowered time share `u`, plus self-discharge. Tamper lockout happens when V < V_th. Field data only identifies the product `u·I_b`; the bench experiment supplies `I_b` to split them. Cell type depends on model: VX520/VX680 = CR2450, VX675 = CR2032, X990 = CR2430. Every physics function needs a test that reproduces a datasheet curve or published number (e.g. Norris–Landzberg 13× vs 12.35×, Keil et al. 2016).
- `prognostics/`: competing risks (eq 13, lognormal per mechanism, Weibull as a check, plus a background hazard). Adds a residual neural correction to the log-hazard (eq 14, a correction, never a replacement), a censored likelihood, a voltage observation model (eq 18, every job with a voltage counts), deep ensembles, and isotonic recalibration. Predictions must pass the calibration gate (ECE, NLL, coverage) before rules are compared. The OOD test split is the hottest districts or the oldest serial cohorts.
- `rules/`: priority rules A–D (§7), each rescaled to 0–1.
- `planner/`: `potts.py` (spin σ_i ∈ {0..K}, 0 = not this week, energy eq 19; moves that break the daily limit are rejected, not penalised), Metropolis and parallel tempering, `routes.py` (2-opt annealing), `ortools_baseline.py`, with CVRPLIB validation.
- `sim/`: synthetic fleet with hidden effects the model doesn't know about, so evaluation isn't circular. Feeds the 720-run factorial (4 rules × 3 uncertainty × 3 geographies × 2 models × 10 seeds). Fix seeds.

## Data facts that affect code

- `hw_terminals.saved_at` is stored in **UTC**. Add +05:30 (the export query does this).
- `hw_repair.Bat_V` is the **coin-cell** voltage, not the main battery.
- There is no district column and `zone_id` is mostly 0. Location comes only from merchant address text → town → district.
- GP (Global Payment) jobs have no merchant locations, and NTB field records stop in 2020. Keep both, but exclude them from climate analysis.

## Data protection (hard rules)

- Never commit or upload anything in `data/` (except `data/reference/`), the `.sql` dumps, `.xlsx` files, or `references/` PDFs. `.gitignore` enforces this, so don't weaken it.
- `location_text` (merchant name/address) is used only to extract the town and must be dropped from every output. Scripts must never write merchant names, including in diagnostic files.
- Pseudonymise serial numbers and TIDs before analysis. Keep client bank names out of reported results.
- Don't query, open or copy tables holding staff logins, contact details or helpdesk tickets (`new_itsup` isn't needed at all).
