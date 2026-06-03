-- ============================================================
-- 03_analysis.sql
-- DESNZ Procurement Spend Analysis — Analysis / KPI Layer
-- ------------------------------------------------------------
-- Purpose: produce the metrics that feed the Power BI dashboard
-- and the findings write-up. Runs on the `clean` view from
-- 02_cleaning.sql.
--
-- Key findings (year 2024, ~£12.03bn total spend, 6,047 txns):
--   * Spend is extremely concentrated: top 10 "suppliers" = 85.4%.
--     But these are largely arm's-length bodies / infrastructure
--     recipients (Nuclear Decommissioning Authority, Sizewell C,
--     Ofgem), so this reflects grant/investment transfers, not
--     competitive procurement concentration.
--   * Two monthly spikes: March (fiscal year-end) and September
--     (few transactions, very large lumpy capital transfers).
--   * Largest expense types are grants/equity, confirming the
--     grant-dominated nature of the spend.
-- Engine: DuckDB
-- ============================================================


-- ------------------------------------------------------------
-- KPI 1 — Headline numbers (dashboard cards).
-- ------------------------------------------------------------
SELECT
    COUNT(*)                  AS transactions,
    COUNT(DISTINCT supplier)  AS suppliers,
    ROUND(SUM(amount)/1e9, 2) AS total_spend_bn,
    ROUND(AVG(amount), 0)     AS avg_transaction
FROM clean;


-- ------------------------------------------------------------
-- KPI 2 — Top 10 recipients by spend (bar chart).
-- ------------------------------------------------------------
SELECT
    supplier,
    ROUND(SUM(amount)/1e6, 1) AS spend_m,
    COUNT(*)                  AS txns
FROM clean
GROUP BY supplier
ORDER BY SUM(amount) DESC
LIMIT 10;


-- ------------------------------------------------------------
-- KPI 3 — Spend concentration (procurement risk metric).
--   Uses a window function to rank suppliers by spend and
--   compute the share held by the top 10 and top 50.
--   Finding: top 10 = 85.4%, top 50 = 92.6%.
-- ------------------------------------------------------------
WITH ranked AS (
    SELECT
        supplier,
        SUM(amount)                                  AS spend,
        ROW_NUMBER() OVER (ORDER BY SUM(amount) DESC) AS rn,
        SUM(SUM(amount)) OVER ()                     AS grand_total
    FROM clean
    GROUP BY supplier
)
SELECT
    ROUND(SUM(CASE WHEN rn <= 10 THEN spend END) / MAX(grand_total) * 100, 1) AS top10_pct,
    ROUND(SUM(CASE WHEN rn <= 50 THEN spend END) / MAX(grand_total) * 100, 1) AS top50_pct
FROM ranked;


-- ------------------------------------------------------------
-- KPI 4 — Monthly spend trend (line chart).
--   Reads BOTH spend and transaction count: September is high
--   spend on LOW volume (large lumpy payments), distinct from
--   March's broad fiscal year-end surge.
-- ------------------------------------------------------------
SELECT
    payment_month,
    ROUND(SUM(amount)/1e6, 1) AS spend_m,
    COUNT(*)                  AS txns
FROM clean
GROUP BY payment_month
ORDER BY payment_month;


-- ------------------------------------------------------------
-- KPI 5 — Spend by expense type, with High/Medium/Low tier.
--   Tier thresholds: High >= £100m, Medium >= £10m, else Low.
--   Mirrors the classification approach used in coursework;
--   makes the long tail of expense types scannable at a glance.
-- ------------------------------------------------------------
WITH by_type AS (
    SELECT
        expense_type,
        SUM(amount) AS spend
    FROM clean
    GROUP BY expense_type
)
SELECT
    expense_type,
    ROUND(spend/1e6, 1) AS spend_m,
    CASE
        WHEN spend >= 100e6 THEN 'High'
        WHEN spend >= 10e6  THEN 'Medium'
        ELSE 'Low'
    END AS tier
FROM by_type
ORDER BY spend DESC;
