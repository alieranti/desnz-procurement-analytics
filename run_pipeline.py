import duckdb

RAW_DATA = "data/raw/*.csv"

con = duckdb.connect()
con.execute(f"""
    CREATE TABLE raw AS
    SELECT * FROM read_csv_auto(
        '{RAW_DATA}',
        union_by_name=true,
        filename=true,
        encoding='latin-1'
    )
""")

row_count = con.execute("SELECT COUNT(*) FROM raw").fetchone()[0]
columns = con.execute("DESCRIBE raw").df()

print(f"\n=== Loaded {row_count:,} rows ===\n")
print("Columns:")
print(columns[['column_name', 'column_type']].to_string(index=False))

# ===== PROFILING =====
print("\n=== PROFILING ===\n")

print(con.execute("""
    SELECT COUNT(*) AS total_rows,
           MIN("Date of Payment") AS earliest,
           MAX("Date of Payment") AS latest
    FROM raw
""").df().to_string(index=False))

print("\n--- Null counts per column ---")
cols = [c for c in con.execute("DESCRIBE raw").df()['column_name'] if c != 'filename']
null_checks = ",\n".join(
    [f'SUM(CASE WHEN "{c}" IS NULL THEN 1 ELSE 0 END) AS "{c}"' for c in cols]
)
nulls = con.execute(f"SELECT {null_checks} FROM raw").df().T
nulls.columns = ['null_count']
nulls['null_pct'] = (nulls['null_count'] / row_count * 100).round(1)
print(nulls.to_string())

print("\n--- Distinct suppliers ---")
print(con.execute('SELECT COUNT(DISTINCT "Supplier") AS distinct_suppliers FROM raw').df().to_string(index=False))

print("\n--- Amount values that won't cast to number ---")
print(con.execute("""
    SELECT "Amount", COUNT(*) AS n
    FROM raw
    WHERE TRY_CAST(REPLACE(REPLACE("Amount", ',', ''), '£', '') AS DOUBLE) IS NULL
    GROUP BY "Amount"
    ORDER BY n DESC
    LIMIT 20
""").df().to_string(index=False))

print("\n--- Rows per file ---")
print(con.execute("""
    SELECT filename, COUNT(*) AS rows
    FROM raw GROUP BY filename ORDER BY filename
""").df().to_string(index=False))

# ===== CLEANING =====
con.execute("""
    CREATE OR REPLACE VIEW clean AS
    SELECT
        "Date of Payment"                                    AS payment_date,
        date_trunc('month', "Date of Payment")               AS payment_month,
        TRIM(UPPER("Supplier"))                               AS supplier,
        TRIM("Expense Type")                                  AS expense_type,
        TRIM("Expense Area")                                  AS expense_area,
        COALESCE(NULLIF(TRIM("Supplier Type"), ''), 'Unknown') AS supplier_type,
        TRIM("Supplier Post Code")                            AS supplier_post_code,
        CAST(REPLACE(REPLACE("Amount", ',', ''), '£', '') AS DOUBLE) AS amount,
        "Transaction Number"                                  AS transaction_number,
        "Description"                                         AS description
    FROM raw
""")

print("\n=== CLEAN VIEW CHECK ===\n")

# Did supplier standardization reduce the distinct count?
print("Distinct suppliers after UPPER+TRIM:",
      con.execute("SELECT COUNT(DISTINCT supplier) FROM clean").fetchone()[0])

# Sanity: total spend, row count, any negative/zero amounts (refunds/anomalies)
print(con.execute("""
    SELECT
        COUNT(*)                                   AS rows,
        ROUND(SUM(amount), 2)                      AS total_spend,
        ROUND(AVG(amount), 2)                      AS avg_amount,
        SUM(CASE WHEN amount <= 0 THEN 1 ELSE 0 END) AS non_positive_amounts
    FROM clean
""").df().to_string(index=False))

# Duplicate check: same supplier, date, amount, txn number appearing more than once
print("\n--- Potential duplicate transactions ---")
print(con.execute("""
    SELECT supplier, payment_date, amount, transaction_number, COUNT(*) AS n
    FROM clean
    GROUP BY supplier, payment_date, amount, transaction_number
    HAVING COUNT(*) > 1
    ORDER BY n DESC
    LIMIT 10
""").df().to_string(index=False))

print("\n--- True full-row duplicates (identical across all fields) ---")
print(con.execute("""
    WITH dupe_check AS (
        SELECT supplier, payment_date, amount, transaction_number, expense_type,
               expense_area, description,
               COUNT(*) AS copies
        FROM clean
        GROUP BY ALL
        HAVING COUNT(*) > 1
    )
    SELECT COUNT(*) AS distinct_dupe_groups,
           SUM(copies) AS total_rows_involved,
           SUM(copies - 1) AS excess_rows_to_remove
    FROM dupe_check
""").df().to_string(index=False))

print("\n--- Same txn number but DIFFERENT amounts (likely legit split payments, keep) ---")
print(con.execute("""
    SELECT COUNT(*) AS txn_numbers_with_varied_amounts
    FROM (
        SELECT transaction_number
        FROM clean
        GROUP BY transaction_number
        HAVING COUNT(DISTINCT amount) > 1
    )
""").df().to_string(index=False))

# ===== CLEANING (finalized with dedup) =====
con.execute("""
    CREATE OR REPLACE VIEW clean AS
    SELECT DISTINCT
        "Date of Payment"                                    AS payment_date,
        date_trunc('month', "Date of Payment")               AS payment_month,
        TRIM(UPPER("Supplier"))                               AS supplier,
        TRIM("Expense Type")                                  AS expense_type,
        TRIM("Expense Area")                                  AS expense_area,
        COALESCE(NULLIF(TRIM("Supplier Type"), ''), 'Unknown') AS supplier_type,
        TRIM("Supplier Post Code")                            AS supplier_post_code,
        CAST(REPLACE(REPLACE("Amount", ',', ''), '£', '') AS DOUBLE) AS amount,
        "Transaction Number"                                  AS transaction_number,
        "Description"                                         AS description
    FROM raw
""")

print("\n=== POST-DEDUP ROW COUNT ===")
print(con.execute("SELECT COUNT(*) AS rows_after_dedup FROM clean").df().to_string(index=False))

# ===== ANALYSIS LAYER =====
print("\n=== ANALYSIS ===\n")

# KPI 1: Headline numbers
print("--- Headline KPIs ---")
print(con.execute("""
    SELECT
        COUNT(*)                          AS transactions,
        COUNT(DISTINCT supplier)          AS suppliers,
        ROUND(SUM(amount)/1e9, 2)         AS total_spend_bn,
        ROUND(AVG(amount), 0)             AS avg_transaction
    FROM clean
""").df().to_string(index=False))

# KPI 2: Top 10 suppliers by spend
print("\n--- Top 10 suppliers by spend ---")
print(con.execute("""
    SELECT supplier,
           ROUND(SUM(amount)/1e6, 1) AS spend_m,
           COUNT(*) AS txns
    FROM clean GROUP BY supplier
    ORDER BY SUM(amount) DESC LIMIT 10
""").df().to_string(index=False))

# KPI 3: Supplier concentration (procurement risk metric)
print("\n--- Supplier concentration ---")
print(con.execute("""
    WITH ranked AS (
        SELECT supplier, SUM(amount) AS spend
        FROM clean GROUP BY supplier
        ORDER BY spend DESC
    ),
    tagged AS (
        SELECT *, ROW_NUMBER() OVER (ORDER BY spend DESC) AS rn,
               SUM(spend) OVER () AS grand_total
        FROM ranked
    )
    SELECT
        ROUND(SUM(CASE WHEN rn <= 10 THEN spend END) / MAX(grand_total) * 100, 1) AS top10_pct,
        ROUND(SUM(CASE WHEN rn <= 50 THEN spend END) / MAX(grand_total) * 100, 1) AS top50_pct
    FROM tagged
""").df().to_string(index=False))

# KPI 4: Monthly trend (the fiscal year-end spike should show)
print("\n--- Monthly spend trend ---")
print(con.execute("""
    SELECT payment_month,
           ROUND(SUM(amount)/1e6, 1) AS spend_m,
           COUNT(*) AS txns
    FROM clean GROUP BY payment_month ORDER BY payment_month
""").df().to_string(index=False))

# KPI 5: Spend by expense type, with High/Med/Low tier (your graded technique)
print("\n--- Spend by expense type with tier ---")
print(con.execute("""
    WITH by_type AS (
        SELECT expense_type, SUM(amount) AS spend
        FROM clean GROUP BY expense_type
    )
    SELECT expense_type,
           ROUND(spend/1e6, 1) AS spend_m,
           CASE
               WHEN spend >= 100e6 THEN 'High'
               WHEN spend >= 10e6  THEN 'Medium'
               ELSE 'Low'
           END AS tier
    FROM by_type ORDER BY spend DESC LIMIT 15
""").df().to_string(index=False))

# ===== EXPORT FOR POWER BI =====
import os
os.makedirs("data/processed", exist_ok=True)

con.execute("""
    COPY (SELECT * FROM clean ORDER BY payment_date)
    TO 'data/processed/desnz_clean.csv' (HEADER, DELIMITER ',')
""")

print("\n=== EXPORT COMPLETE ===")
print("Written: data/processed/desnz_clean.csv")
print("Rows exported:", con.execute("SELECT COUNT(*) FROM clean").fetchone()[0])