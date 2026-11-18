USE WAREHOUSE sec_wh;
SHOW TABLES IN SCHEMA sec_pipeline.staging;


-- dim_company: one row per company.
-- company_key is a "surrogate key": a simple number we generate, used by the fact table instead of the CIK.
CREATE OR REPLACE TABLE sec_pipeline.gold.dim_company AS
SELECT
    ROW_NUMBER() OVER (ORDER BY company)  AS company_key,
    CAST(cik AS NUMBER)                   AS cik,
    company                               AS company_name,
    CASE
        WHEN company ILIKE 'Apple%'     THEN 9    -- Apple's fiscal year ends in September
        WHEN company ILIKE 'Amazon%'    THEN 12   -- Amazon: December
        WHEN company ILIKE 'Microsoft%' THEN 6    -- Microsoft: June
    END                                   AS fiscal_year_end_month
FROM sec_pipeline.staging.stg_ref_companies;

-- dim_filing: one row per filing (10-K or 10-Q).
CREATE OR REPLACE TABLE sec_pipeline.gold.dim_filing AS
SELECT
    ROW_NUMBER() OVER (ORDER BY adsh)  AS filing_key,
    adsh                               AS accession_number,
    form,
    TO_DATE(filed_date)                AS filed_date,
    TO_DATE(balance_date)              AS period_end_date,
    fiscal_year,
    fiscal_period
FROM sec_pipeline.staging.stg_filings;

USE WAREHOUSE sec_wh;

CREATE OR REPLACE TABLE sec_pipeline.gold.dim_segment AS
SELECT
    ROW_NUMBER() OVER (ORDER BY c.company_key, m.axis, m.member) AS segment_key,
    c.company_key,
    m.axis,
    m.member                  AS member_code,
    m.segment_name,
    m.segment_type,
    m.in_top_level,
    m.in_detail_level,
    DATE '1900-01-01'         AS valid_from,
    DATE '9999-12-31'         AS valid_to,
    TRUE                      AS is_current
FROM sec_pipeline.staging.stg_ref_segment_map m
JOIN sec_pipeline.gold.dim_company c
  ON m.company = c.company_name
WHERE m."INCLUDE" = TRUE;

CREATE OR REPLACE TABLE sec_pipeline.gold.dim_date AS
SELECT
    TO_NUMBER(TO_CHAR(d, 'YYYYMMDD')) AS date_key,
    d                                 AS full_date,
    YEAR(d)                           AS calendar_year,
    QUARTER(d)                        AS calendar_quarter,
    MONTH(d)                          AS calendar_month,
    MONTHNAME(d)                      AS month_name,
    (d = LAST_DAY(d))                 AS is_month_end
FROM (
    SELECT DATEADD(day, SEQ4(), DATE '2019-01-01') AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 3000))
)
WHERE d <= DATE '2025-12-31';

USE WAREHOUSE sec_wh;

SELECT check_name, actual, expected, IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM (
    -- dim_company
    SELECT 'dim_company: rows' AS check_name, COUNT(*) AS actual, 3 AS expected
      FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_company: duplicate company_key', COUNT(*) - COUNT(DISTINCT company_key), 0
      FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_company: duplicate cik', COUNT(*) - COUNT(DISTINCT cik), 0
      FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_company: missing fiscal_year_end_month', COUNT_IF(fiscal_year_end_month IS NULL), 0
      FROM sec_pipeline.gold.dim_company

    -- dim_filing
    UNION ALL SELECT 'dim_filing: rows', COUNT(*), 24
      FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_filing: duplicate accession_number', COUNT(*) - COUNT(DISTINCT accession_number), 0
      FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_filing: forms other than 10-K / 10-Q', COUNT_IF(form NOT IN ('10-K', '10-Q')), 0
      FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_filing: missing dates', COUNT_IF(filed_date IS NULL OR period_end_date IS NULL), 0
      FROM sec_pipeline.gold.dim_filing

    -- dim_segment
    UNION ALL SELECT 'dim_segment: rows', COUNT(*), 54
      FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: duplicate segment_key', COUNT(*) - COUNT(DISTINCT segment_key), 0
      FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: rows with no company', COUNT_IF(company_key IS NULL), 0
      FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: more than one current row per segment',
           COUNT(*) - COUNT(DISTINCT company_key::STRING || '|' || axis || '|' || member_code), 0
      FROM sec_pipeline.gold.dim_segment WHERE is_current
    UNION ALL SELECT 'dim_segment: unexpected segment_type',
           COUNT_IF(segment_type NOT IN ('business_unit', 'geographic', 'product_service')), 0
      FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: valid_from not before valid_to', COUNT_IF(valid_from >= valid_to), 0
      FROM sec_pipeline.gold.dim_segment

    -- dim_date
    UNION ALL SELECT 'dim_date: rows', COUNT(*), 2557
      FROM sec_pipeline.gold.dim_date
    UNION ALL SELECT 'dim_date: duplicate date_key', COUNT(*) - COUNT(DISTINCT date_key), 0
      FROM sec_pipeline.gold.dim_date
    UNION ALL SELECT 'dim_date: missing days in the range',
           (DATEDIFF(day, MIN(full_date), MAX(full_date)) + 1) - COUNT(*), 0
      FROM sec_pipeline.gold.dim_date
);
