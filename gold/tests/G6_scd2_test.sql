USE WAREHOUSE sec_wh;

-- 1) A free, instant copy of the segment table to experiment on.
CREATE OR REPLACE TABLE sec_pipeline.gold.dim_segment_test CLONE sec_pipeline.gold.dim_segment;

-- 2) Step one of SCD Type 2: CLOSE the current version of the segment (don't overwrite it).
UPDATE sec_pipeline.gold.dim_segment_test
SET valid_to = DATE '2023-12-31', is_current = FALSE
WHERE axis = 'BusinessSegments'
  AND member_code = 'InternationalSegment'
  AND is_current
  AND company_key = (SELECT company_key FROM sec_pipeline.gold.dim_company WHERE company_name ILIKE 'Amazon%');

-- 3) Step two: INSERT a NEW version with the new name, valid from 2024-01-01 onward.
INSERT INTO sec_pipeline.gold.dim_segment_test
    (segment_key, company_key, axis, member_code, segment_name, segment_type,
     in_top_level, in_detail_level, valid_from, valid_to, is_current)
SELECT (SELECT MAX(segment_key) + 1 FROM sec_pipeline.gold.dim_segment_test),
       company_key, axis, member_code, 'International (renamed)', segment_type,
       in_top_level, in_detail_level, DATE '2024-01-01', DATE '9999-12-31', TRUE
FROM sec_pipeline.gold.dim_segment_test
WHERE axis = 'BusinessSegments'
  AND member_code = 'InternationalSegment'
  AND valid_to = DATE '2023-12-31'
  AND company_key = (SELECT company_key FROM sec_pipeline.gold.dim_company WHERE company_name ILIKE 'Amazon%');

-- 4) Re-point the facts: each fact picks the segment version that was valid on ITS date.
CREATE OR REPLACE TABLE sec_pipeline.gold.fact_segment_revenue_test AS
SELECT f.company_key, s2.segment_key, f.filing_key, f.date_key,
       f.period_length_quarters, f.revenue_usd
FROM sec_pipeline.gold.fact_segment_revenue f
JOIN sec_pipeline.gold.dim_segment s1 ON s1.segment_key = f.segment_key
JOIN sec_pipeline.gold.dim_date d     ON d.date_key = f.date_key
JOIN sec_pipeline.gold.dim_segment_test s2
  ON s2.company_key = s1.company_key AND s2.axis = s1.axis AND s2.member_code = s1.member_code
 AND d.full_date BETWEEN s2.valid_from AND s2.valid_to;

USE WAREHOUSE sec_wh;

SELECT c.company_name,
       d.full_date AS period_end,
       f.period_length_quarters AS qtrs,
       s.segment_name,
       s.valid_from,
       s.valid_to,
       s.is_current,
       f.revenue_usd
FROM sec_pipeline.gold.fact_segment_revenue_test f
JOIN sec_pipeline.gold.dim_segment_test s ON s.segment_key = f.segment_key
JOIN sec_pipeline.gold.dim_company c      ON c.company_key = s.company_key
JOIN sec_pipeline.gold.dim_date d         ON d.date_key = f.date_key
WHERE s.member_code = 'InternationalSegment'
  AND s.axis = 'BusinessSegments'
  AND s.company_key = (SELECT company_key FROM sec_pipeline.gold.dim_company WHERE company_name ILIKE 'Amazon%')
ORDER BY d.full_date, f.period_length_quarters;

USE WAREHOUSE sec_wh;
SELECT c.company_name,
       s.member_code,
       LAG(s.segment_name) OVER (PARTITION BY s.company_key, s.axis, s.member_code ORDER BY s.valid_from) AS previous_name,
       s.segment_name AS name,
       s.valid_from AS changed_on
FROM sec_pipeline.gold.dim_segment_test s
JOIN sec_pipeline.gold.dim_company c ON c.company_key = s.company_key
WHERE s.member_code = 'InternationalSegment'
  AND s.axis = 'BusinessSegments'
ORDER BY s.valid_from;

DROP TABLE IF EXISTS sec_pipeline.gold.fact_segment_revenue_test;
DROP TABLE IF EXISTS sec_pipeline.gold.dim_segment_test;

SHOW TABLES IN SCHEMA sec_pipeline.gold;
