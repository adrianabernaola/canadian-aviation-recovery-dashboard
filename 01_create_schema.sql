-- ============================================================
-- 01_create_schema.sql
-- Canadian Aviation Recovery Dashboard
-- Creates the star schema: 2 dimension tables + 3 fact tables.
-- Staging tables (stg_annual, stg_monthly, stg_airline) are
-- assumed to already exist, loaded directly from the raw
-- Statistics Canada CSVs with no transformation.
-- ============================================================

DROP TABLE IF EXISTS dim_airport;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS fact_airport_annual;
DROP TABLE IF EXISTS fact_airport_monthly;
DROP TABLE IF EXISTS fact_airline_monthly;

-- ------------------------------------------------------------
-- dim_airport
-- One row per major Canadian airport. Statistics Canada uses
-- two different GEO naming conventions across the annual table
-- (23-10-0253-01) and the monthly table (23-10-0312-01), so this
-- dimension carries both names and lets each fact table join on
-- the column that matches its own source file.
-- ------------------------------------------------------------
CREATE TABLE dim_airport (
    airport_id         INTEGER PRIMARY KEY,
    iata_code          TEXT NOT NULL,
    city               TEXT NOT NULL,
    province           TEXT NOT NULL,
    airport_name_full  TEXT NOT NULL,
    geo_name_annual    TEXT NOT NULL,  -- matches GEO column in the annual (23-10-0253-01) file
    geo_name_monthly   TEXT NOT NULL   -- matches GEO column in the monthly (23-10-0312-01) file
);

-- ------------------------------------------------------------
-- dim_date
-- One row per calendar month, Jan 2019 - latest available month.
-- is_baseline flags 2019 (the pre-pandemic comparison year used
-- by every "recovery vs. 2019" measure). is_pandemic flags 2020
-- (the crash year) for easy exclusion/highlighting in charts.
-- ------------------------------------------------------------
CREATE TABLE dim_date (
    date_key      INTEGER PRIMARY KEY,  -- YYYYMM, e.g. 201901 = Jan 2019
    year          INTEGER NOT NULL,
    month_num     INTEGER NOT NULL,     -- 1-12
    month_name    TEXT    NOT NULL,
    quarter       INTEGER NOT NULL,     -- 1-4
    is_baseline   INTEGER NOT NULL,     -- 1 if year = 2019, else 0
    is_pandemic   INTEGER NOT NULL      -- 1 if year = 2020, else 0
);

-- ------------------------------------------------------------
-- fact_airport_annual
-- Grain: one row per airport per year.
-- Source: 23-10-0253-01 (annual passenger traffic).
-- ------------------------------------------------------------
CREATE TABLE fact_airport_annual (
    fact_id           INTEGER PRIMARY KEY,
    airport_id        INTEGER NOT NULL REFERENCES dim_airport(airport_id),
    year              INTEGER NOT NULL,
    domestic_pax      INTEGER,  -- domestic-sector passengers (enplaned + deplaned)
    transborder_pax   INTEGER,  -- transborder (US) sector passengers
    intl_pax          INTEGER,  -- other-international sector passengers
    total_pax         INTEGER,  -- domestic + transborder + intl
    passenger_flights INTEGER
);

-- ------------------------------------------------------------
-- fact_airport_monthly
-- Grain: one row per airport per month.
-- Source: 23-10-0312-01 (monthly screened passengers, 8 largest airports).
-- ------------------------------------------------------------
CREATE TABLE fact_airport_monthly (
    fact_id         INTEGER PRIMARY KEY,
    airport_id      INTEGER NOT NULL REFERENCES dim_airport(airport_id),
    date_key        INTEGER NOT NULL REFERENCES dim_date(date_key),
    total_screened  INTEGER,  -- everyone screened (passengers + non-passengers)
    total_pax       INTEGER,
    domestic_pax    INTEGER,
    transborder_pax INTEGER,
    intl_pax        INTEGER,
    non_pax         INTEGER   -- crew, staff, etc.
);

-- ------------------------------------------------------------
-- fact_airline_monthly
-- Grain: one row per month, Canada-wide (StatCan publishes this
-- table at the national industry level, not broken out by
-- individual carrier - see data dictionary for detail).
-- Source: 23-10-0079-01 (airline operating & financial statistics).
-- ------------------------------------------------------------
CREATE TABLE fact_airline_monthly (
    fact_id            INTEGER PRIMARY KEY,
    date_key           INTEGER NOT NULL REFERENCES dim_date(date_key),
    passengers         INTEGER,  -- thousands
    load_factor        REAL,     -- percent, already a unit value (not thousands)
    available_seat_km  INTEGER,  -- thousands
    passenger_km       INTEGER,  -- thousands
    hours_flown        INTEGER,  -- thousands
    fuel_consumed      INTEGER,  -- thousands of litres
    total_revenue      INTEGER,  -- thousands of dollars
    total_expenses     INTEGER   -- thousands of dollars
);
