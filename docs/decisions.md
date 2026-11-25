# Decision log

Record every important choice: date, what was decided, why, and what it affects.

| Date | Decision | Reason | Affects |
|---|---|---|---|
| 2026-11-02 | Primary mechanism changed from Li-ion fade to coin-cell depletion | Epic repair log: low coin-cell voltage goes with tamper lockouts (56 % vs 11 %) | Physics module, RQ1, H5 |
| 2026-11-24 | Use the 4 June 2026 database backup as the main dataset | Has dates, voltages, faults, install dates and locations; live re-run optional | Data pipeline |
| 2026-11-24 | Location from merchant address text → town → district; merchant text deleted after | No district field exists; data-protection commitment | Climate link, privacy |
| 2026-11-24 | GP and NTB jobs kept but excluded from climate analysis | No merchant locations for these clients | RQ1 limitation |
