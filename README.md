# PoF Prognostics for Payment Terminals

Physics-of-failure informed prognostics and annealing-based field-service planning for
Epic Lanka's payment-terminal fleet (B.Sc. Honours, Department of Physics,
University of Sri Jayewardenepura).

**Start here:** read [`PROJECT_PLAN.md`](PROJECT_PLAN.md). It has the full research plan, data
description, equations, timeline and the build checklist.

## Quick start
```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```
1. Copy Epic's `.sql` dumps and `.xlsx` files into `data/raw/` (never commit them).
2. Load the dumps into a local MySQL/MariaDB (see PROJECT_PLAN.md section 12.3).
3. Run `sql/terminal_location_export.sql` and save the result as `data/interim/export.csv`.
4. Extract districts and drop merchant text:
   ```bash
   python scripts/extract_district.py data/interim/export.csv data/reference/lk_town_district.csv data/interim/export_district.csv
   ```

## Layout
| Folder | Contents |
|---|---|
| `docs/` | Proposal, experiment plan, presentation script, decision log |
| `sql/` | Export query (read-only, tested on the 4 June 2026 backup) |
| `scripts/` | One-off tools (district extraction) |
| `data/` | Raw, interim and processed data (**git-ignored**) |
| `src/pofp/` | Project code: data, climate, physics, prognostics, rules, planner, sim |
| `notebooks/` | Exploration and figures |
| `tests/` | Checks against datasheets and published results |
"# pof-prognostics-pos" 
