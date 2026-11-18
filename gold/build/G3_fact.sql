USE WAREHOUSE sec_wh;
SHOW TABLES IN SCHEMA sec_pipeline.gold;

USE WAREHOUSE sec_wh;

CREATE OR REPLACE TABLE sec_pipeline.gold.fact_segment_revenue AS
WITH f AS (
    SELECT company, adsh, TO_DATE(period_end) AS period_end, qtrs,
           CAST(value AS NUMBER(38,4)) AS revenue_usd,
           TRY_TO_NUMBER(dimn) AS dimn, axis, member
    FROM sec_pipeline.staging.stg_facts_revenue_latest
)
SELECT c.company_key,
       s.segment_key,
       fl.filing_key,
       d.date_key,
       f.qtrs        AS period_length_quarters,
       f.revenue_usd
FROM f
JOIN sec_pipeline.gold.dim_company c ON f.company = c.company_name
JOIN sec_pipeline.gold.dim_segment s
     ON s.company_key = c.company_key AND s.axis = f.axis AND s.member_code = f.member
    AND f.period_end BETWEEN s.valid_from AND s.valid_to
JOIN sec_pipeline.gold.dim_filing fl ON fl.accession_number = f.adsh
JOIN sec_pipeline.gold.dim_date d    ON d.full_date = f.period_end
WHERE f.dimn = 1;

CREATE OR REPLACE TABLE sec_pipeline.gold.fact_company_revenue AS
WITH f AS (
    SELECT company, adsh, TO_DATE(period_end) AS period_end, qtrs,
           CAST(value AS NUMBER(38,4)) AS revenue_usd,
           TRY_TO_NUMBER(dimn) AS dimn
    FROM sec_pipeline.staging.stg_facts_revenue_latest
)
SELECT c.company_key,
       fl.filing_key,
       d.date_key,
       f.qtrs        AS period_length_quarters,
       f.revenue_usd
FROM f
JOIN sec_pipeline.gold.dim_company c ON f.company = c.company_name
JOIN sec_pipeline.gold.dim_filing fl ON fl.accession_number = f.adsh
JOIN sec_pipeline.gold.dim_date d    ON d.full_date = f.period_end
WHERE f.dimn = 0;

SELECT check_name, actual, expected, IFF(actual = expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'segment fact rows = staging rows with a breakdown' AS check_name,
           (SELECT COUNT(*) FROM sec_pipeline.gold.fact_segment_revenue) AS actual,
           (SELECT COUNT(*) FROM sec_pipeline.staging.stg_facts_revenue_latest WHERE TRY_TO_NUMBER(dimn) = 1) AS expected
    UNION ALL
    SELECT 'company fact rows = staging total rows',
           (SELECT COUNT(*) FROM sec_pipeline.gold.fact_company_revenue),
           (SELECT COUNT(*) FROM sec_pipeline.staging.stg_facts_revenue_latest WHERE TRY_TO_NUMBER(dimn) = 0)
    UNION ALL
    SELECT 'segment fact: duplicate rows',
           (SELECT COUNT(*) - COUNT(DISTINCT company_key::STRING || '|' || segment_key::STRING || '|' || date_key::STRING || '|' || period_length_quarters::STRING)
            FROM sec_pipeline.gold.fact_segment_revenue),
           0
    UNION ALL
    SELECT 'Amazon 2023 total revenue',
           (SELECT SUM(f.revenue_usd) FROM sec_pipeline.gold.fact_company_revenue f
            JOIN sec_pipeline.gold.dim_company c ON c.company_key = f.company_key
            WHERE c.company_name ILIKE 'Amazon%' AND f.period_length_quarters = 4 AND f.date_key = 20231231),
           574785000000
);
