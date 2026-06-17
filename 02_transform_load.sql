-- ============================================================
-- 02_transform_load.sql
-- Canadian Aviation Recovery Dashboard
-- Populates the star schema from the three staging tables.
-- Run after 01_create_schema.sql, against a database that
-- already has stg_annual, stg_monthly, stg_airline loaded from
-- the raw Statistics Canada CSVs.
-- ============================================================

-- ------------------------------------------------------------
-- dim_airport
-- Hand-curated mapping: StatCan does not publish an "airport
-- code" field, and the annual file (23-10-0253-01) and monthly
-- file (23-10-0312-01) spell out the same airport's GEO name
-- slightly differently in places. This table is the single
-- place that resolves both names to one iata_code, so every
-- fact table can join cleanly back to one dimension.
-- ------------------------------------------------------------
INSERT INTO dim_airport (airport_id, iata_code, city, province, airport_name_full, geo_name_annual, geo_name_monthly) VALUES
(1, 'YYZ', 'Toronto',   'Ontario',           'Toronto Pearson International',          'Toronto/Lester B Pearson International, Ontario',                  'Toronto/Lester B Pearson International, Ontario'),
(2, 'YVR', 'Vancouver', 'British Columbia',  'Vancouver International',                'Vancouver International, British Columbia',                        'Vancouver International, British Columbia'),
(3, 'YYC', 'Calgary',   'Alberta',           'Calgary International',                  'Calgary International, Alberta',                                   'Calgary International, Alberta'),
(4, 'YUL', 'Montréal',  'Quebec',            'Montréal/Trudeau International',         'Montréal/Pierre Elliott Trudeau International, Quebec',            'Montréal/Pierre Elliott Trudeau International, Quebec'),
(5, 'YOW', 'Ottawa',    'Ontario',           'Ottawa/Macdonald-Cartier International', 'Ottawa/Macdonald-Cartier International, Ontario',                   'Ottawa/Macdonald-Cartier International, Ontario'),
(6, 'YEG', 'Edmonton',  'Alberta',           'Edmonton International',                 'Edmonton International, Alberta',                                  'Edmonton International, Alberta'),
(7, 'YWG', 'Winnipeg',  'Manitoba',          'Winnipeg/Richardson International',      'Winnipeg/James Armstrong Richardson International, Manitoba',      'Winnipeg/James Armstrong Richardson International, Manitoba'),
(8, 'YHZ', 'Halifax',   'Nova Scotia',       'Halifax/Stanfield International',        'Halifax/Robert L Stanfield International, Nova Scotia',            'Halifax/Robert L Stanfield International, Nova Scotia');

-- ------------------------------------------------------------
-- dim_date
-- One row per month from Jan 2019 through the latest month
-- present in the monthly staging tables. Built with a recursive
-- CTE rather than hand-typed, so it always stretches to cover
-- whatever the most recent StatCan release includes.
-- ------------------------------------------------------------
WITH RECURSIVE months(n) AS (
    SELECT 0
    UNION ALL
    SELECT n + 1 FROM months
    WHERE n + 1 <= (
        SELECT (
            (CAST(strftime('%Y', MAX(d)) AS INTEGER) - 2019) * 12
            + CAST(strftime('%m', MAX(d)) AS INTEGER) - 1
        )
        FROM (
            SELECT date('20' || substr(REF_DATE, 5, 2) || '-' ||
                   CASE substr(REF_DATE, 1, 3)
                       WHEN 'Jan' THEN '01' WHEN 'Feb' THEN '02' WHEN 'Mar' THEN '03'
                       WHEN 'Apr' THEN '04' WHEN 'May' THEN '05' WHEN 'Jun' THEN '06'
                       WHEN 'Jul' THEN '07' WHEN 'Aug' THEN '08' WHEN 'Sep' THEN '09'
                       WHEN 'Oct' THEN '10' WHEN 'Nov' THEN '11' WHEN 'Dec' THEN '12'
                   END || '-01') AS d
            FROM stg_monthly
        )
    )
)
INSERT INTO dim_date (date_key, year, month_num, month_name, quarter, is_baseline, is_pandemic)
SELECT
    CAST(strftime('%Y', date('2019-01-01', '+' || n || ' months')) AS INTEGER) * 100
        + CAST(strftime('%m', date('2019-01-01', '+' || n || ' months')) AS INTEGER)               AS date_key,
    CAST(strftime('%Y', date('2019-01-01', '+' || n || ' months')) AS INTEGER)                      AS year,
    CAST(strftime('%m', date('2019-01-01', '+' || n || ' months')) AS INTEGER)                      AS month_num,
    CASE CAST(strftime('%m', date('2019-01-01', '+' || n || ' months')) AS INTEGER)
        WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
        WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June'
        WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September'
        WHEN 10 THEN 'October' WHEN 11 THEN 'November' WHEN 12 THEN 'December'
    END                                                                                              AS month_name,
    (CAST(strftime('%m', date('2019-01-01', '+' || n || ' months')) AS INTEGER) - 1) / 3 + 1         AS quarter,
    CASE WHEN CAST(strftime('%Y', date('2019-01-01', '+' || n || ' months')) AS INTEGER) = 2019 THEN 1 ELSE 0 END AS is_baseline,
    CASE WHEN CAST(strftime('%Y', date('2019-01-01', '+' || n || ' months')) AS INTEGER) = 2020 THEN 1 ELSE 0 END AS is_pandemic
FROM months;

-- ------------------------------------------------------------
-- fact_airport_annual
-- Source: stg_annual (23-10-0253-01), filtered to the 8 major
-- airports and pivoted from long format (one metric per row)
-- to wide format (one row per airport-year) with CASE WHEN.
-- VALUE is cast to INTEGER because StatCan ships it as text to
-- accommodate suppressed cells ('..' in STATUS, blank VALUE).
-- ------------------------------------------------------------
INSERT INTO fact_airport_annual (airport_id, year, domestic_pax, transborder_pax, intl_pax, total_pax, passenger_flights)
SELECT
    a.airport_id,
    s.REF_DATE AS year,
    SUM(CASE WHEN s."Air passenger traffic" = 'Domestic sector'             THEN CAST(s.VALUE AS INTEGER) END) AS domestic_pax,
    SUM(CASE WHEN s."Air passenger traffic" = 'Transborder sector'          THEN CAST(s.VALUE AS INTEGER) END) AS transborder_pax,
    SUM(CASE WHEN s."Air passenger traffic" = 'Other International sector' THEN CAST(s.VALUE AS INTEGER) END) AS intl_pax,
    SUM(CASE WHEN s."Air passenger traffic" = 'Total, passenger sector'    THEN CAST(s.VALUE AS INTEGER) END) AS total_pax,
    SUM(CASE WHEN s."Air passenger traffic" = 'Passenger flights'          THEN CAST(s.VALUE AS INTEGER) END) AS passenger_flights
FROM stg_annual s
JOIN dim_airport a ON a.geo_name_annual = s.GEO
WHERE s.REF_DATE BETWEEN 2019 AND 2024
GROUP BY a.airport_id, s.REF_DATE;

-- ------------------------------------------------------------
-- fact_airport_monthly
-- Source: stg_monthly (23-10-0312-01), filtered to the 8 major
-- airports. REF_DATE arrives as 'Mon-YY' (e.g. 'Apr-19'), so it
-- is parsed into a date_key (YYYYMM) with explicit month-name
-- and century logic rather than relying on default date parsing,
-- which would misread the 2-digit year.
-- ------------------------------------------------------------
INSERT INTO fact_airport_monthly (airport_id, date_key, total_screened, total_pax, domestic_pax, transborder_pax, intl_pax, non_pax)
SELECT
    a.airport_id,
    (2000 + CAST(substr(s.REF_DATE, 5, 2) AS INTEGER)) * 100 +
        CASE substr(s.REF_DATE, 1, 3)
            WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3 WHEN 'Apr' THEN 4
            WHEN 'May' THEN 5 WHEN 'Jun' THEN 6 WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8
            WHEN 'Sep' THEN 9 WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
        END                                                                       AS date_key,
    SUM(CASE WHEN s."Screened traffic" = 'Total screened traffic'                  THEN s.VALUE END) AS total_screened,
    SUM(CASE WHEN s."Screened traffic" = 'Total passengers'                        THEN s.VALUE END) AS total_pax,
    SUM(CASE WHEN s."Screened traffic" = 'Domestic sector passengers'              THEN s.VALUE END) AS domestic_pax,
    SUM(CASE WHEN s."Screened traffic" = 'Transborder sector passengers'           THEN s.VALUE END) AS transborder_pax,
    SUM(CASE WHEN s."Screened traffic" = 'Other International sector passengers'   THEN s.VALUE END) AS intl_pax,
    SUM(CASE WHEN s."Screened traffic" = 'Non-passengers'                          THEN s.VALUE END) AS non_pax
FROM stg_monthly s
JOIN dim_airport a ON a.geo_name_monthly = s.GEO
GROUP BY a.airport_id, date_key;

-- ------------------------------------------------------------
-- fact_airline_monthly
-- Source: stg_airline (23-10-0079-01). This StatCan table is
-- published at the national ("Canada") level only - it does not
-- break results out by individual carrier - so this fact table
-- is industry-wide, one row per month. Same 'Mon-YY' parsing
-- logic as fact_airport_monthly, but this source goes back to
-- 1981, so the 2-digit year needs explicit century handling
-- (YY >= 50 -> 19xx, else 20xx) before it's safe to filter down
-- to the 2019-onward window dim_date covers.
-- ------------------------------------------------------------
INSERT INTO fact_airline_monthly (date_key, passengers, load_factor, available_seat_km, passenger_km, hours_flown, fuel_consumed, total_revenue, total_expenses)
SELECT
    (CASE WHEN CAST(substr(s.REF_DATE, 5, 2) AS INTEGER) >= 50 THEN 1900 ELSE 2000 END
        + CAST(substr(s.REF_DATE, 5, 2) AS INTEGER)) * 100 +
        CASE substr(s.REF_DATE, 1, 3)
            WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3 WHEN 'Apr' THEN 4
            WHEN 'May' THEN 5 WHEN 'Jun' THEN 6 WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8
            WHEN 'Sep' THEN 9 WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
        END                                                                                AS date_key,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Passengers'                  THEN s.VALUE END) AS passengers,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Load factor'                 THEN s.VALUE END) AS load_factor,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Available seat-kilometres'    THEN s.VALUE END) AS available_seat_km,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Passenger-kilometres'         THEN s.VALUE END) AS passenger_km,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Hours flown'                  THEN s.VALUE END) AS hours_flown,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Turbo fuel consumed'           THEN s.VALUE END) AS fuel_consumed,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Total operating revenues'      THEN s.VALUE END) AS total_revenue,
    SUM(CASE WHEN s."Operational and financial statistics" = 'Total operating expenses'      THEN s.VALUE END) AS total_expenses
FROM stg_airline s
WHERE s.GEO = 'Canada'
GROUP BY date_key
HAVING date_key >= 201901;
