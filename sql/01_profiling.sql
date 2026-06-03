-- ============================================================
-- 01_profiling.sql
-- DESNZ Procurement Spend Analysis — Data Profiling
-- ------------------------------------------------------------
-- Purpose: measure the shape and quality of the raw data BEFORE
-- making any cleaning decisions. Every cleaning step in
-- 02_cleaning.sql is justified by a finding here.
--
-- Source: UK Dept. for Energy Security & Net Zero (DESNZ),
--         departmental spending over £25,000, calendar year 2024
--         (12 monthly CSVs, loaded into table `raw`).
-- Engine: DuckDB
-- ============================================================


-- ------------------------------------------------------------
-- 1. Coverage check: row count and date range.
--    Confirms all 12 months loaded and the period is complete
--    (expected: 2024-01-02 to 2024-12-31, ~6,050 rows).
-- ------------------------------------------------------------
SELECT
    COUNT(*)               AS total_rows,
    MIN("Date of Payment") AS earliest,
    MAX("Date of Payment") AS latest
FROM raw;


-- ------------------------------------------------------------
-- 2. Completeness check: rows per source file.
--    Verifies no month is missing or truncated. March stands
--    out (~810 rows vs ~460 avg) — this is a real signal, not
--    an error: UK fiscal year-end (31 Mar) drives a spending
--    surge before budgets reset.
-- ------------------------------------------------------------
SELECT
    filename,
    COUNT(*) AS rows
FROM raw
GROUP BY filename
ORDER BY filename;


-- ------------------------------------------------------------
-- 3. Null analysis: how empty is each column?
--    Finding: 8 columns (Invoice Number, Programme Code/Name,
--    Cost Centre fields, NAC fields, Directorate) are ~85.5%
--    null — and share the EXACT same null count (5,175). That
--    identical figure is a fingerprint: those rows come from a
--    record type that doesn't populate programme/cost-centre
--    coding. Decision (see cleaning): drop these columns — at
--    85% empty they can't support reliable segmentation.
--
--    Run per-column manually, or generate programmatically.
--    Example for a single column:
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                              AS total_rows,
    SUM(CASE WHEN "Invoice Number" IS NULL THEN 1 ELSE 0 END)  AS invoice_nulls,
    SUM(CASE WHEN "Programme Code" IS NULL THEN 1 ELSE 0 END)  AS programme_nulls,
    SUM(CASE WHEN "Supplier Post Code" IS NULL THEN 1 ELSE 0 END) AS postcode_nulls
FROM raw;


-- ------------------------------------------------------------
-- 4. Type check on Amount: it loads as VARCHAR (text), not a
--    number, so it cannot be summed/averaged until cast.
--    This query strips thousand-separators and currency symbols,
--    then flags any value that STILL won't convert to a number.
--    Finding: zero non-castable values — the VARCHAR type was
--    caused only by comma separators, no junk to handle.
-- ------------------------------------------------------------
SELECT
    "Amount",
    COUNT(*) AS n
FROM raw
WHERE TRY_CAST(REPLACE(REPLACE("Amount", ',', ''), '£', '') AS DOUBLE) IS NULL
GROUP BY "Amount"
ORDER BY n DESC;


-- ------------------------------------------------------------
-- 5. Cardinality check: distinct suppliers.
--    877 distinct suppliers. Used as a baseline to test whether
--    casing/whitespace variants are fragmenting supplier names
--    (see cleaning step — UPPER+TRIM left the count unchanged,
--    confirming the data was already consistent on capitalisation).
-- ------------------------------------------------------------
SELECT COUNT(DISTINCT "Supplier") AS distinct_suppliers
FROM raw;


-- ------------------------------------------------------------
-- 6. Duplicate detection (two-part, deliberately careful).
--
--    6a. Rows sharing supplier + date + amount + txn number.
--        These LOOK like duplicates but need scrutiny — some
--        are legitimate split payments (one transaction number,
--        multiple line items with different amounts).
-- ------------------------------------------------------------
SELECT
    "Supplier",
    "Date of Payment",
    "Amount",
    "Transaction Number",
    COUNT(*) AS n
FROM raw
GROUP BY "Supplier", "Date of Payment", "Amount", "Transaction Number"
HAVING COUNT(*) > 1
ORDER BY n DESC;


-- ------------------------------------------------------------
--    6b. Transaction numbers carrying MULTIPLE distinct amounts.
--        Finding: 159 such transaction numbers. These are split
--        payments / multi-line invoices — NOT errors. Removing
--        them (e.g. a naive DISTINCT on transaction number) would
--        erase real spend and understate the department's outlay.
--        This is why deduplication (in cleaning) only removes rows
--        identical across ALL fields, never on transaction number alone.
-- ------------------------------------------------------------
SELECT COUNT(*) AS txn_numbers_with_varied_amounts
FROM (
    SELECT "Transaction Number"
    FROM raw
    GROUP BY "Transaction Number"
    HAVING COUNT(DISTINCT "Amount") > 1
);
