-- ============================================================
-- 02_cleaning.sql
-- DESNZ Procurement Spend Analysis — Cleaning Layer
-- ------------------------------------------------------------
-- Purpose: turn the raw, mixed-quality `raw` table into a
-- trustworthy `clean` view for analysis. Every decision below
-- is driven by a finding in 01_profiling.sql.
--
-- Cleaning decisions, summarised:
--   1. Cast Amount (text -> number) after stripping separators.
--   2. Drop 8 columns that are ~85% null (no analytical value).
--   3. Standardise supplier names (UPPER + TRIM) to prevent
--      casing/whitespace fragmentation.
--   4. Replace blank Supplier Type with an explicit 'Unknown'
--      (NULLIF + COALESCE) rather than leaving a silent gap.
--   5. Derive payment_month for time-series analysis.
--   6. Deduplicate ONLY rows identical across all fields
--      (SELECT DISTINCT) — preserves the 159 legitimate split
--      payments identified in profiling.
-- Engine: DuckDB
-- ============================================================


CREATE OR REPLACE VIEW clean AS
SELECT DISTINCT                              -- (6) removes only full-row
                                             --     duplicates (3 rows);
                                             --     keeps split payments.

    "Date of Payment"                        AS payment_date,

    -- (5) Month bucket for the monthly spend trend chart.
    date_trunc('month', "Date of Payment")   AS payment_month,

    -- (3) Standardise supplier: UPPER removes case variants,
    --     TRIM removes leading/trailing whitespace. Tested in
    --     profiling — confirms names are consistent, no over-merging.
    TRIM(UPPER("Supplier"))                  AS supplier,

    TRIM("Expense Type")                     AS expense_type,
    TRIM("Expense Area")                     AS expense_area,

    -- (4) Blank supplier types become 'Unknown' explicitly.
    --     NULLIF turns '' into NULL; COALESCE then labels it,
    --     so gaps are visible in the dashboard rather than blank.
    COALESCE(NULLIF(TRIM("Supplier Type"), ''), 'Unknown') AS supplier_type,

    TRIM("Supplier Post Code")               AS supplier_post_code,

    -- (1) Amount: strip thousand-separators and any £ symbol,
    --     then cast text -> DOUBLE so it can be aggregated.
    --     Profiling confirmed every value casts cleanly.
    CAST(REPLACE(REPLACE("Amount", ',', ''), '£', '') AS DOUBLE) AS amount,

    "Transaction Number"                     AS transaction_number,
    "Description"                            AS description

FROM raw;
-- (2) The 8 high-null columns (Invoice Number, Purchase Order
--     Number, Cost Centre Name/Code, NAC Code/Name, Programme
--     Code/Name, Directorate) are simply not selected above —
--     dropped because they are ~85% empty.


-- ------------------------------------------------------------
-- Validation queries (run after creating the view)
-- ------------------------------------------------------------

-- Confirm the dedup removed exactly the expected rows
-- (expected: 6,047 = 6,050 raw - 3 full-row duplicates).
SELECT COUNT(*) AS rows_after_dedup FROM clean;

-- Sanity-check the cleaned numeric column: totals, average,
-- and any non-positive amounts (refunds/credits/errors).
-- Finding: zero non-positive amounts — no refunds to handle.
SELECT
    COUNT(*)                                     AS rows,
    ROUND(SUM(amount), 2)                        AS total_spend,
    ROUND(AVG(amount), 2)                        AS avg_amount,
    SUM(CASE WHEN amount <= 0 THEN 1 ELSE 0 END) AS non_positive_amounts
FROM clean;

-- Confirm supplier standardisation did not over-merge:
-- distinct count should match the profiling baseline (877).
SELECT COUNT(DISTINCT supplier) AS distinct_suppliers FROM clean;
