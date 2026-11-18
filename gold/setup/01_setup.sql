-- 1) A warehouse is the compute that runs queries. X-Small is the cheapest size.
--    AUTO_SUSPEND = 60 stops it after 60 seconds idle, so it doesn't use up the free balance.
CREATE WAREHOUSE IF NOT EXISTS sec_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE sec_wh;

-- 2) A database is the top-level container for our tables.
CREATE DATABASE IF NOT EXISTS sec_pipeline;

-- 3) Two schemas (folders inside the database):
--    staging = raw copies of the Silver tables we bring over
--    gold    = the final star schema
CREATE SCHEMA IF NOT EXISTS sec_pipeline.staging;
CREATE SCHEMA IF NOT EXISTS sec_pipeline.gold;

-- 4) Check that it worked.
SHOW SCHEMAS IN DATABASE sec_pipeline;




-- Check: expect 3 and 24.
SELECT 'dim_company' AS table_name, COUNT(*) AS row_count FROM sec_pipeline.gold.dim_company
UNION ALL
SELECT 'dim_filing', COUNT(*) FROM sec_pipeline.gold.dim_filing;
