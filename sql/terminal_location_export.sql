-- =====================================================================
-- Terminal location + repair export for the PoF prognostics research
-- Author: Lavindu Perera (University of Sri Jayewardenepura / Epic Lanka)
--
-- Runs on MySQL 5.7 (no CTEs or window functions are used).
-- Reads only: hardwarelive, tech_operation (and optionally
-- dfcc_pos_operation). It creates TEMPORARY tables only, which disappear
-- when the session ends; no live table is changed.
--
-- One row per workshop job (job card) received on or after @from_date.
-- Location is taken, in order of preference, from:
--   1 jobcard        : the merchant written on the TMC job card itself
--   2 serial_before  : latest field ticket for this serial number on or
--                      before the job date (breakdown removal, breakdown
--                      replacement, new install, terminal replacement)
--   3 tid_before     : latest field ticket for the job card's terminal ID
--   4 dfcc_list      : DFCC terminal list (if that database is available)
--   5 serial_after   : earliest field ticket after the job date (weakest)
--
-- Age columns (for the coin-cell model):
--   install_date            : latest installation of this serial at a
--                             merchant on or before the job date
--   first_seen_date         : earliest record of this serial anywhere
--                             (install, field ticket or repair); a lower
--                             bound on its age when install_date is missing
--   prev_coin_replaced_date : date a coin cell was fitted to this serial on
--                             an EARLIER repair job (gives the age of the
--                             coin cell that failed now)
--   prev_repair_date        : date of this serial's previous repair job
--   prev_repairs            : number of earlier repair jobs for this serial
--   release_before_install  : release date of the earlier repair that came
--                             just before install_date
--   storage_days            : days between that release and install_date,
--                             i.e. time spent unpowered in stock
--
-- PRIVACY: location_text is the merchant name/address text. It is only
-- needed to extract the town. After the town/district has been extracted,
-- DELETE the location_text column; do not store or publish it.
-- =====================================================================

USE tech_operation;               -- temporary tables are created here

SET @from_date := '2024-01-01';   -- change as needed (data starts 2019-12)
SET @tz        := '+05:30';       -- hw_terminals.saved_at is stored in UTC
SET @tolerance := 3;              -- days a field ticket may post-date receipt

-- ---------------------------------------------------------------------
-- 1. Jobs received at the hardware workshop (matches the "In" report)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS r_jobs;
CREATE TEMPORARY TABLE r_jobs (
  jobcard_no  INT PRIMARY KEY,
  in_date     DATETIME,
  released    DATETIME,
  bank        VARCHAR(20),
  serialno    VARCHAR(30),
  model       VARCHAR(40),
  tid         VARCHAR(12),
  jc_merchant VARCHAR(160),
  KEY (serialno), KEY (tid)
);

INSERT INTO r_jobs
SELECT h.jobcard_no,
       CONVERT_TZ(h.saved_at, '+00:00', @tz),
       h.Released_Date,
       h.bank,
       UPPER(TRIM(h.serialno)),
       h.model,
       NULLIF(TRIM(j.tid), ''),
       NULLIF(TRIM(j.merchant), '')
FROM hardwarelive.hw_terminals h
LEFT JOIN tech_operation.jobcard j ON j.jobcard_no = h.jobcard_no
WHERE h.saved_at >= @from_date;

-- ---------------------------------------------------------------------
-- 2. Every field event that ties a serial number / TID to a merchant
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS r_events;
CREATE TEMPORARY TABLE r_events (
  serialno  VARCHAR(30),
  tid       VARCHAR(12),
  ev_date   DATE,
  source    VARCHAR(30),
  merchant  VARCHAR(160),
  zone_id   INT,
  KEY (serialno, ev_date), KEY (tid, ev_date)
);

INSERT INTO r_events
SELECT UPPER(TRIM(fault_serialno)), NULLIF(TRIM(tid),''), tdate, 'breakdown_removed', merchant, zone_id
FROM tech_operation.breakdown
WHERE IFNULL(cancel,0) = 0 AND TRIM(merchant) <> '' AND IFNULL(TRIM(fault_serialno),'') <> '';

INSERT INTO r_events
SELECT UPPER(TRIM(replaced_serialno)), NULLIF(TRIM(tid),''), tdate, 'breakdown_installed', merchant, zone_id
FROM tech_operation.breakdown
WHERE IFNULL(cancel,0) = 0 AND TRIM(merchant) <> '' AND IFNULL(TRIM(replaced_serialno),'') <> '';

INSERT INTO r_events
SELECT UPPER(TRIM(serialno)), NULLIF(TRIM(tid),''), tdate, 'new_install', merchant, zone_id
FROM tech_operation.newinstall
WHERE IFNULL(cancel,0) = 0 AND TRIM(merchant) <> '';

INSERT INTO r_events
SELECT UPPER(TRIM(based_serialno)), NULLIF(TRIM(based_tid),''), tdate, 'replacement_removed', merchant, zone_id
FROM tech_operation.terminal_replacement
WHERE IFNULL(cancel,0) = 0 AND TRIM(merchant) <> '' AND IFNULL(TRIM(based_serialno),'') <> '';

INSERT INTO r_events
SELECT UPPER(TRIM(replaced_serialno)), NULLIF(TRIM(replaced_tid),''), tdate, 'replacement_installed', merchant, zone_id
FROM tech_operation.terminal_replacement
WHERE IFNULL(cancel,0) = 0 AND TRIM(merchant) <> '' AND IFNULL(TRIM(replaced_serialno),'') <> '';

-- Optional: DFCC terminal list (delete this block if dfcc_pos_operation
-- is not on the same server)
INSERT INTO r_events
SELECT UPPER(TRIM(serial_no)), CAST(tid AS CHAR), DATE(add_date), 'dfcc_list', merchant, NULL
FROM dfcc_pos_operation.terminal_list
WHERE TRIM(merchant) <> '';

-- ---------------------------------------------------------------------
-- 3. Coin-cell part IDs (hardwarelive.hw_parts)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS r_coin_parts;
CREATE TEMPORARY TABLE r_coin_parts (Part_ID VARCHAR(15) PRIMARY KEY);
INSERT INTO r_coin_parts
SELECT CAST(Part_ID AS CHAR) FROM hardwarelive.hw_parts
WHERE LOWER(part_name) LIKE '%coin batt%';

-- Every coin-cell replacement since records began, by serial number
DROP TEMPORARY TABLE IF EXISTS r_coin;
CREATE TEMPORARY TABLE r_coin (
  serialno   VARCHAR(30),
  jobcard_no INT,
  coin_date  DATETIME,
  KEY (serialno, coin_date)
);
INSERT INTO r_coin
SELECT UPPER(TRIM(h.serialno)), a.jobcard_no, a.Saved_Date
FROM hardwarelive.hw_repair_addpart a
JOIN r_coin_parts c ON c.Part_ID = a.Part_ID
JOIN hardwarelive.hw_terminals h ON h.jobcard_no = a.jobcard_no
WHERE a.Saved_Date > '2000-01-01';

-- Every repair job since records began, by serial number
DROP TEMPORARY TABLE IF EXISTS r_repairs;
CREATE TEMPORARY TABLE r_repairs (
  serialno   VARCHAR(30),
  jobcard_no INT,
  in_date    DATETIME,
  released   DATETIME,
  KEY (serialno, in_date),
  KEY (serialno, released)
);
INSERT INTO r_repairs
SELECT UPPER(TRIM(serialno)), jobcard_no, CONVERT_TZ(saved_at, '+00:00', @tz),
       IF(Released_Date > '2000-01-01', Released_Date, NULL)
FROM hardwarelive.hw_terminals
WHERE saved_at > '2000-01-01';

-- ---------------------------------------------------------------------
-- 4. Final export: one row per job
-- ---------------------------------------------------------------------
SELECT t.*,
  -- time in storage: from the release of an earlier repair to the next
  -- installation at a merchant (the terminal sits unpowered in stock, so
  -- its coin cell drains the whole time)
  (SELECT MAX(p.released) FROM r_repairs p WHERE p.serialno = t.serialno
     AND p.jobcard_no <> t.jobcard_no AND p.released IS NOT NULL
     AND DATE(p.released) <= t.install_date) AS release_before_install,
  DATEDIFF(t.install_date,
    (SELECT MAX(p.released) FROM r_repairs p WHERE p.serialno = t.serialno
       AND p.jobcard_no <> t.jobcard_no AND p.released IS NOT NULL
       AND DATE(p.released) <= t.install_date)) AS storage_days
FROM (
SELECT
  j.jobcard_no,
  j.in_date,
  j.released,
  j.bank,
  j.serialno,
  j.model,
  j.tid,

  -- location text and where it came from
  COALESCE(
    j.jc_merchant,
    (SELECT e.merchant FROM r_events e WHERE e.serialno = j.serialno
       AND e.ev_date <= DATE(j.in_date) + INTERVAL @tolerance DAY ORDER BY e.ev_date DESC LIMIT 1),
    (SELECT e.merchant FROM r_events e WHERE j.tid IS NOT NULL AND e.tid = j.tid
       AND e.ev_date <= DATE(j.in_date) + INTERVAL @tolerance DAY ORDER BY e.ev_date DESC LIMIT 1),
    (SELECT e.merchant FROM r_events e WHERE e.serialno = j.serialno
       ORDER BY e.ev_date ASC LIMIT 1)
  ) AS location_text,
  CASE
    WHEN j.jc_merchant IS NOT NULL THEN 'jobcard'
    WHEN EXISTS (SELECT 1 FROM r_events e WHERE e.serialno = j.serialno
                 AND e.ev_date <= DATE(j.in_date) + INTERVAL @tolerance DAY) THEN 'serial_before'
    WHEN j.tid IS NOT NULL AND EXISTS (SELECT 1 FROM r_events e WHERE e.tid = j.tid
                 AND e.ev_date <= DATE(j.in_date) + INTERVAL @tolerance DAY) THEN 'tid_before'
    WHEN EXISTS (SELECT 1 FROM r_events e WHERE e.serialno = j.serialno) THEN 'serial_after'
    ELSE 'none'
  END AS location_source,
  (SELECT e.zone_id FROM r_events e WHERE e.serialno = j.serialno AND e.zone_id > 0
     ORDER BY ABS(DATEDIFF(e.ev_date, j.in_date)) LIMIT 1) AS zone_id,

  -- age of the terminal and of its coin cell
  (SELECT MAX(e.ev_date) FROM r_events e WHERE e.serialno = j.serialno
     AND e.source IN ('new_install','breakdown_installed','replacement_installed','dfcc_list')
     AND e.ev_date <= DATE(j.in_date)) AS install_date,
  LEAST(
    IFNULL((SELECT MIN(e.ev_date) FROM r_events e WHERE e.serialno = j.serialno), '9999-12-31'),
    IFNULL((SELECT MIN(DATE(p.in_date)) FROM r_repairs p WHERE p.serialno = j.serialno), '9999-12-31')
  ) AS first_seen_date,
  (SELECT MAX(c.coin_date) FROM r_coin c WHERE c.serialno = j.serialno
     AND c.jobcard_no <> j.jobcard_no AND c.coin_date < j.in_date) AS prev_coin_replaced_date,
  (SELECT MAX(p.in_date) FROM r_repairs p WHERE p.serialno = j.serialno
     AND p.jobcard_no <> j.jobcard_no AND p.in_date < j.in_date) AS prev_repair_date,
  (SELECT COUNT(*) FROM r_repairs p WHERE p.serialno = j.serialno
     AND p.jobcard_no <> j.jobcard_no AND p.in_date < j.in_date) AS prev_repairs,

  -- coin-cell voltage measured at the workshop, and whether it was replaced
  (SELECT r.Bat_V FROM hardwarelive.hw_repair r WHERE r.jobcard_no = j.jobcard_no
     ORDER BY r.hw_jobno DESC LIMIT 1) AS coin_cell_v,
  EXISTS (SELECT 1 FROM hardwarelive.hw_repair_addpart a JOIN r_coin_parts c ON c.Part_ID = a.Part_ID
          WHERE a.jobcard_no = j.jobcard_no) AS coin_cell_replaced,

  -- faults recorded by the workshop
  (SELECT GROUP_CONCAT(f.Fault_Name ORDER BY f.Fault_Name SEPARATOR '; ')
     FROM hardwarelive.hw_repair_fault rf
     JOIN hardwarelive.hw_terminal_fault f ON f.Fault_ID = rf.Fault_id
    WHERE rf.jobcard_no = j.jobcard_no) AS faults
FROM r_jobs j
) t
ORDER BY t.in_date;
