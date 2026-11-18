USE WAREHOUSE sec_wh;

CREATE SCHEMA IF NOT EXISTS sec_pipeline.dq;

-- Create the data quality results table for Gold checks
CREATE TABLE IF NOT EXISTS sec_pipeline.dq.dq_results (
    run_id      STRING,
    run_ts      TIMESTAMP_NTZ,
    layer       STRING,
    check_name  STRING,
    actual      NUMBER(38,4),
    expected    NUMBER(38,4),
    result      STRING
);

SET run_id = (SELECT UUID_STRING());

-- Run all 29 Gold checks and store each result as a row in dq_results
INSERT INTO sec_pipeline.dq.dq_results (run_id, run_ts, layer, check_name, actual, expected, result)
SELECT $run_id, SYSDATE(), 'gold', check_name, actual, expected, IFF(actual = expected, 'PASS', 'FAIL')
FROM (
    SELECT 'dim_company: rows' AS check_name, COUNT(*) AS actual, 3 AS expected FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_company: duplicate company_key', COUNT(*) - COUNT(DISTINCT company_key), 0 FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_company: duplicate cik', COUNT(*) - COUNT(DISTINCT cik), 0 FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_company: missing fiscal_year_end_month', COUNT_IF(fiscal_year_end_month IS NULL), 0 FROM sec_pipeline.gold.dim_company
    UNION ALL SELECT 'dim_filing: rows', COUNT(*), 24 FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_filing: duplicate accession_number', COUNT(*) - COUNT(DISTINCT accession_number), 0 FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_filing: forms other than 10-K / 10-Q', COUNT_IF(form NOT IN ('10-K', '10-Q')), 0 FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_filing: missing dates', COUNT_IF(filed_date IS NULL OR period_end_date IS NULL), 0 FROM sec_pipeline.gold.dim_filing
    UNION ALL SELECT 'dim_segment: rows', COUNT(*), 54 FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: duplicate segment_key', COUNT(*) - COUNT(DISTINCT segment_key), 0 FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: rows with no company', COUNT_IF(company_key IS NULL), 0 FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: more than one current row per segment',
           COUNT(*) - COUNT(DISTINCT company_key::STRING || '|' || axis || '|' || member_code), 0
           FROM sec_pipeline.gold.dim_segment WHERE is_current
    UNION ALL SELECT 'dim_segment: unexpected segment_type',
           COUNT_IF(segment_type NOT IN ('business_unit', 'geographic', 'product_service')), 0 FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_segment: valid_from not before valid_to', COUNT_IF(valid_from >= valid_to), 0 FROM sec_pipeline.gold.dim_segment
    UNION ALL SELECT 'dim_date: rows', COUNT(*), 2557 FROM sec_pipeline.gold.dim_date
    UNION ALL SELECT 'dim_date: duplicate date_key', COUNT(*) - COUNT(DISTINCT date_key), 0 FROM sec_pipeline.gold.dim_date
    UNION ALL SELECT 'dim_date: missing days in the range', (DATEDIFF(day, MIN(full_date), MAX(full_date)) + 1) - COUNT(*), 0 FROM sec_pipeline.gold.dim_date
    UNION ALL SELECT 'segment fact rows = staging rows with a breakdown',
           (SELECT COUNT(*) FROM sec_pipeline.gold.fact_segment_revenue),
           (SELECT COUNT(*) FROM sec_pipeline.staging.stg_facts_revenue_latest WHERE TRY_TO_NUMBER(dimn) = 1)
    UNION ALL SELECT 'company fact rows = staging total rows',
           (SELECT COUNT(*) FROM sec_pipeline.gold.fact_company_revenue),
           (SELECT COUNT(*) FROM sec_pipeline.staging.stg_facts_revenue_latest WHERE TRY_TO_NUMBER(dimn) = 0)
    UNION ALL SELECT 'segment fact: duplicate rows',
           (SELECT COUNT(*) - COUNT(DISTINCT company_key::STRING || '|' || segment_key::STRING || '|' || date_key::STRING || '|' || period_length_quarters::STRING)
            FROM sec_pipeline.gold.fact_segment_revenue), 0
    UNION ALL SELECT 'company fact: duplicate rows',
           (SELECT COUNT(*) - COUNT(DISTINCT company_key::STRING || '|' || date_key::STRING || '|' || period_length_quarters::STRING)
            FROM sec_pipeline.gold.fact_company_revenue), 0
    UNION ALL SELECT 'segment fact: revenue zero or negative',
           (SELECT COUNT_IF(revenue_usd <= 0) FROM sec_pipeline.gold.fact_segment_revenue), 0
    UNION ALL SELECT 'company fact: revenue zero or negative',
           (SELECT COUNT_IF(revenue_usd <= 0) FROM sec_pipeline.gold.fact_company_revenue), 0
    UNION ALL SELECT 'companies in segment fact', (SELECT COUNT(DISTINCT company_key) FROM sec_pipeline.gold.fact_segment_revenue), 3
    UNION ALL SELECT 'companies in company fact', (SELECT COUNT(DISTINCT company_key) FROM sec_pipeline.gold.fact_company_revenue), 3
    UNION ALL SELECT 'Amazon 2023 total revenue',
           (SELECT SUM(f.revenue_usd) FROM sec_pipeline.gold.fact_company_revenue f
            JOIN sec_pipeline.gold.dim_company c ON c.company_key = f.company_key
            WHERE c.company_name ILIKE 'Amazon%' AND f.period_length_quarters = 4 AND f.date_key = 20231231),
           574785000000
    UNION ALL SELECT 'BusinessSegments / Geographical that do not add up to the company total',
           (SELECT COUNT(*) FROM (
                SELECT f.company_key, f.date_key, f.period_length_quarters, s.axis
                FROM sec_pipeline.gold.fact_segment_revenue f
                JOIN sec_pipeline.gold.dim_segment s ON s.segment_key = f.segment_key
                JOIN sec_pipeline.gold.fact_company_revenue t
                  ON t.company_key = f.company_key AND t.date_key = f.date_key
                 AND t.period_length_quarters = f.period_length_quarters
                WHERE s.axis IN ('BusinessSegments', 'Geographical')
                GROUP BY f.company_key, f.date_key, f.period_length_quarters, s.axis
                HAVING SUM(f.revenue_usd) <> MAX(t.revenue_usd))), 0
    UNION ALL SELECT 'cross-layer: Gold fact rows (segment + company) = staging rows',
           (SELECT COUNT(*) FROM sec_pipeline.gold.fact_segment_revenue) + (SELECT COUNT(*) FROM sec_pipeline.gold.fact_company_revenue),
           (SELECT COUNT(*) FROM sec_pipeline.staging.stg_facts_revenue_latest)
    UNION ALL SELECT 'cross-layer: staging rows = Silver rows (857, counted in Databricks)',
           (SELECT COUNT(*) FROM sec_pipeline.staging.stg_facts_revenue_latest), 857
);

-- Count PASS and FAIL for the most recent run
SELECT result, COUNT(*) AS checks
FROM sec_pipeline.dq.dq_results
WHERE run_id = (SELECT run_id FROM sec_pipeline.dq.dq_results ORDER BY run_ts DESC LIMIT 1)
GROUP BY result;

-- List every check from the most recent run, with failures first
SELECT check_name, actual, expected, result
FROM sec_pipeline.dq.dq_results
WHERE run_id = (SELECT run_id FROM sec_pipeline.dq.dq_results ORDER BY run_ts DESC LIMIT 1)
ORDER BY result DESC, check_name;
