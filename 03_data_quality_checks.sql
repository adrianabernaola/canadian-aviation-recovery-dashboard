-- ============================================================
-- 03_data_quality_checks.sql
-- Canadian Aviation Recovery Dashboard
-- Run after 02_transform_load.sql. Validates the star schema
-- before it gets loaded into Power BI.
-- ============================================================

-- 1) ROW COUNT RECONCILIATION
-- fact_airport_monthly should be exactly 8 airports x every
-- month in dim_date. If this isn't 0, an airport/month combo
-- is missing (StatCan suppression or a join mismatch).
SELECT
    (SELECT COUNT(*) FROM dim_airport) * (SELECT COUNT(*) FROM dim_date)
        - (SELECT COUNT(*) FROM fact_airport_monthly) AS missing_airport_month_rows;

-- fact_airport_annual should be exactly 8 airports x 6 years (2019-2024).
SELECT
    (SELECT COUNT(*) FROM dim_airport) * 6
        - (SELECT COUNT(*) FROM fact_airport_annual) AS missing_airport_year_rows;

-- 2) ORPHAN CHECK
-- Every fact row's foreign key should resolve to a real dimension
-- row. A non-zero count here means a join would silently drop data.
SELECT COUNT(*) AS orphan_airport_monthly_rows
FROM fact_airport_monthly f
LEFT JOIN dim_airport a ON f.airport_id = a.airport_id
WHERE a.airport_id IS NULL;

SELECT COUNT(*) AS orphan_airport_monthly_dates
FROM fact_airport_monthly f
LEFT JOIN dim_date d ON f.date_key = d.date_key
WHERE d.date_key IS NULL;

SELECT COUNT(*) AS orphan_airline_monthly_dates
FROM fact_airline_monthly f
LEFT JOIN dim_date d ON f.date_key = d.date_key
WHERE d.date_key IS NULL;

-- 3) NULL / COMPLETENESS CHECK
-- % of rows in each fact table with a NULL metric. A small amount
-- is expected (some small/seasonal sectors at some airports get
-- suppressed by StatCan), but a spike flags a transform bug.
SELECT
    ROUND(100.0 * SUM(CASE WHEN total_pax IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_null_total_pax
FROM fact_airport_monthly;

SELECT
    ROUND(100.0 * SUM(CASE WHEN total_revenue IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_null_revenue
FROM fact_airline_monthly;

-- 4) STATUS-FLAG AUDIT (on staging data, before it was pivoted)
-- StatCan ships two distinct "no value" flags:
--   'x'  = suppressed for confidentiality
--   '..' = not available for that reference period
-- They are NOT the same thing and should not be treated as
-- interchangeable nulls when explaining gaps in the data.
SELECT STATUS, COUNT(*) AS row_count
FROM stg_annual
WHERE STATUS IS NOT NULL
GROUP BY STATUS;

-- 5) ANOMALY CHECK - component sums vs. published total
-- domestic + transborder + intl should equal total_pax exactly.
-- Any row outside the published total signals either a missing
-- sector pivot or a StatCan rounding adjustment worth footnoting.
SELECT airport_id, year, domestic_pax, transborder_pax, intl_pax, total_pax,
       (domestic_pax + transborder_pax + intl_pax) - total_pax AS variance
FROM fact_airport_annual
WHERE (domestic_pax + transborder_pax + intl_pax) <> total_pax;

-- 6) RECOVERY SANITY CHECK
-- Flags any airport-year where total passengers are negative or
-- zero (would indicate a load/parsing failure, not a real value).
SELECT airport_id, year, total_pax
FROM fact_airport_annual
WHERE total_pax IS NOT NULL AND total_pax <= 0;
