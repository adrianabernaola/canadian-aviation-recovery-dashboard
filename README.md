# Canadian Aviation Recovery Dashboard

An end-to-end business intelligence project analyzing Canada's post-pandemic aviation recovery — built with SQL, Power BI, and 100% real Statistics Canada open data.

**Live question:** Canadian aviation was devastated in 2020. Five years later — which airports fully recovered? Which routes drove that recovery? Which are still lagging? And how are Canada's major airlines performing operationally and financially compared to pre-pandemic levels?

---

## Key Findings

- **System-wide airport recovery sits at 99%** of 2019 passenger levels as of 2024 — Canada's major airports are essentially back to pre-pandemic volumes.
- **Montréal (YUL) leads the recovery**, surpassing 2019 levels at 110%, driven by strong international route demand.
- **Ottawa (YOW) lags the most**, still ~9% below 2019 passenger levels — the largest gap among the 8 major hubs.
- **Airline revenue has outpaced passenger recovery.** Despite passenger volumes not fully recovering, industry-wide airline revenue reached **120% of 2019 levels** in 2024 — a sign of higher ticket prices, not just higher demand.
- **Route mix varies sharply by airport.** Toronto (YYZ) and Montréal (YUL) carry the highest international mix (36% and 45%), while Winnipeg (YWG) and Edmonton (YEG) are over 85% domestic — making them far more sensitive to domestic travel demand swings.
- **Load factor has fully recovered**, averaging 84–89% in 2024, matching pre-pandemic operating efficiency.

---

## Dashboard Preview

**Page 1 — Executive Scorecard**
![Executive Scorecard](docs/screenshots/page1_executive_scorecard.png)

**Page 2 — Airport Deep-Dive**
![Airport Deep-Dive](docs/screenshots/page2_airport_deep_dive.png)

**Page 3 — Airline Industry Performance**
![Airline Industry Performance](docs/screenshots/page3_airline_performance.png)

---

## Data Sources

All data is real, publicly available, and sourced directly from Statistics Canada:

| File | StatCan Table | Description | Coverage |
|---|---|---|---|
| `airport-passenger-traffic-annual.csv` | 23-10-0253-01 | Annual passengers enplaned/deplaned by airport, split by domestic, transborder (US), and international routes | 2019–2024 |
| `airport-screened-passengers-monthly.csv` | 23-10-0312-01 | Monthly screened passengers at Canada's 8 largest airports (YYZ, YVR, YYC, YUL, YOW, YEG, YWG, YHZ) | 2019–2026 |
| `airline-operating-financial-stats.csv` | 23-10-0079-01 | Monthly operating and financial statistics for Canada's major airlines — passengers carried, load factor, available seat-kilometres, hours flown, fuel consumed, total operating revenue | 2019–2026 |

---

## Technical Architecture

**1. Data staging (SQLite)**
Raw CSVs were loaded into staging tables exactly as published by Statistics Canada — long format, one metric per row, with StatCan's native `STATUS` (data quality flag) and `SCALAR_FACTOR` (units) columns intact.

**2. Star schema design (SQL)**
Staging data was transformed into a star schema using `CASE WHEN` pivot logic to convert long-format StatCan data into wide, analysis-ready fact tables:

- **Dimension tables:** `dim_date`, `dim_airport`
- **Fact tables:** `fact_airport_annual`, `fact_airport_monthly`, `fact_airline_monthly`

A bridge design in `dim_airport` (separate name columns for the annual vs. monthly source files) resolves an airport-naming inconsistency between the two StatCan datasets, allowing both to join cleanly to a single dimension table.

**3. Data quality checks (SQL)**
Before transformation, staging data was validated for:
- Null/suppressed values (`STATUS` flag handling — StatCan marks suppressed cells separately from valid nulls)
- Row count reconciliation (e.g., 8 airports × 88 months = 704 expected rows in `fact_airport_monthly`)
- Year parsing edge cases (StatCan's 2-digit year format required explicit logic to avoid misreading historical dates)

**4. Semantic model (Power BI)**
Clean star schema tables were loaded into Power BI Desktop and connected through modeled relationships (`dim_date` → fact tables, `dim_airport` → fact tables), with explicit attention to relationship cardinality and active/inactive paths.

**5. DAX measures**
Custom measures calculate recovery rate vs. 2019 baseline, route mix %, year-over-year change, and revenue recovery — including baseline measures that intentionally ignore report-level filters (`ALL()`/`FILTER()`) so KPIs stay anchored to a fixed comparison year regardless of slicer selection.

**6. Dashboard design**
Three report pages, each scoped to a distinct audience need:
- **Executive Scorecard** — headline recovery KPIs and airport-level comparison
- **Airport Deep-Dive** — monthly trends, route mix, and self-serve year/city slicers
- **Airline Industry Performance** — load factor and revenue trends, fixed-baseline recovery KPIs

Each page includes a written **Key Insights** panel translating the underlying data into plain-language takeaways.

---

## Repository Structure

```
canadian-aviation-recovery-dashboard/
├── README.md
├── data/
│   └── raw/                      # Original StatCan CSVs
├── sql/                          # Schema creation, transformation, and data quality SQL
├── powerbi/                      # Power BI .pbix file
├── docs/
│   ├── data_dictionary.md        # Full column-level documentation
│   └── screenshots/              # Dashboard page exports
└── aviation_recovery.db          # SQLite database (star schema)
```

---

## Tools Used

- **SQLite** (via DB Browser for SQLite) — star schema design and SQL transformations
- **Power BI Desktop** — semantic modeling, DAX, dashboard design
- **Statistics Canada Open Data** — sole data source, no synthetic or simulated data

---

## Skills Demonstrated

- **SQL** — star schema design, long-to-wide pivot transformations, data quality validation
- **Power BI** — relationship modeling, cardinality management, multi-page report design
- **DAX** — recovery-rate calculations, fixed-baseline KPIs, route mix %, YoY change
- **Data quality monitoring** — StatCan status-flag handling, completeness checks, row-count reconciliation across three independent sources
- **Dashboard design** — executive scorecard layout, self-serve slicers, consistent KPI definitions, written insight callouts for a non-technical audience
- **Documentation** — this README and the accompanying [data dictionary](docs/data_dictionary.md)

---

## Author

Adriana Bernaola — built as a portfolio project to demonstrate business intelligence and analytics skills for a Business Insight Analyst role.
