# Gold layer (Snowflake)

A star schema in Snowflake with business-segment revenue for Apple, Amazon and Microsoft (2023q1 to 2024q4),
built from the cleaned Silver tables in Databricks.

## Order to run

1. `setup/01_setup.sql`: warehouse (X-Small, auto-suspend 60 seconds), database `sec_pipeline`, schemas `staging`, `gold`, `dq`
2. Load the four staging CSVs (below)
3. `build/02_dimensions.sql`: the four dimension tables
4. `build/03_facts.sql`: the two fact tables and their checks
5. `tests/04_scd2_test.sql` (optional): proves SCD Type 2 on copies of the tables
6. `data_quality/05_dq_results.sql`: runs 29 checks and stores the results in `dq.dq_results`

Run each script with "Run all" in Snowsight.

## Loading staging

Export each Silver table from Databricks as CSV, then in Snowsight use Ingestion > Add Data > Load data into a table
(database `SEC_PIPELINE`, schema `STAGING`, first line as header):

| Silver table | Staging table | Rows |
|---|---|---|
| `silver.ref_companies` | `STG_REF_COMPANIES` | 3 |
| `silver.filings` | `STG_FILINGS` | 24 |
| `silver.ref_segment_map` | `STG_REF_SEGMENT_MAP` | 56 |
| `silver.facts_revenue_latest` | `STG_FACTS_REVENUE_LATEST` | 857 |

## Tables

| Table | One row is | Rows |
|---|---|---|
| `dim_company` | a company | 3 |
| `dim_filing` | a 10-K or 10-Q filing | 24 |
| `dim_segment` (SCD Type 2) | one version of a segment | 54 |
| `dim_date` | a calendar day, 2019 to 2025 | 2,557 |
| `fact_segment_revenue` | segment revenue for a period | 800 |
| `fact_company_revenue` | reported company total for a period | 57 |

## SCD Type 2

`dim_segment` keeps every version of a segment (`valid_from`, `valid_to`, `is_current`).
A fact uses the version valid on its period end date, so old figures keep the old name.
`tests/04_scd2_test.sql` shows this with a simulated rename.

## Data quality

29 checks, stored with a run id and time in `dq.dq_results`: row counts, unique keys, no gaps,
segments adding up to company totals, and a known Amazon total (574,785 million USD).

## Known limits

- Microsoft's product lines change by year, so they are mapped but not reconciled.
- The Silver-to-Gold load is a manual CSV export, not scheduled.
- Gold runs in a Snowflake trial; the tables are also exported to CSV.

Design decisions: `docs/decisions.md`.
