# Design Decisions and Open Questions

Format: what was decided, why, and what it costs. Newest information at the bottom of each entry. Dates are when the decision was made.

---

## D1. Project scope: segment revenue for a few companies
**Date:** 2026-10 · **Status:** decided

Build a warehouse of **business-segment revenue** (for example AWS versus North America versus International) for a small set of companies: Apple, Amazon and Microsoft. Not total-company comparison across many companies.

- **Why:** segment-level data is rarer and more useful than company totals, and it forces real standardization work (different tags and axes per company).
- **Cost:** harder than the company-totals version because the data lives in dimensional XBRL.
- **Expanding later:** add companies by extending the segment mapping, not the pipeline.

## D2. Data source: Financial Statement and Notes Data Sets
**Date:** 2026-10 · **Status:** decided

Use SEC's bulk **Notes** data sets (ZIPs of `sub`, `num`, `dim`, `tag` tables).

Rejected:
- **SEC `companyfacts` / `companyconcept` JSON APIs:** return company-wide totals only; segment breakdowns are not included.
- **Basic "Financial Statement Data Sets":** no `dim` table, so no segment breakdowns.
- **Raw XBRL instance documents parsed with Arelle:** the "proper" route, but much more work for the same facts. The SEC has already flattened them.

**Cost:** values are "as filed", with duplicates and amendments, so cleaning is on us. That is also the point of the project.

## D3. Platform split
**Date:** 2026-10 · **Status:** planned, not yet verified

Bronze and Silver on **Databricks** (PySpark, Delta Lake). Gold on **Snowflake** (star schema, SCD Type 2). Orchestration with **Airflow**. Dashboard in **Power BI**.

- **Why:** Databricks is built for file handling and Spark transforms; Snowflake serves clean, queryable data. Matches common job postings.
- **Risks to check:** (a) whether the free Databricks tier can download from sec.gov and store the data, (b) Snowflake trial length (start it only when Silver is stable), (c) whether free Databricks allows API access for Airflow.

## D4. Bronze is a faithful copy, all strings
**Date:** 2026-10 · **Status:** decided

Bronze tables keep every source column **as text, unchanged**, plus metadata columns: `period`, `_source_file`, `_ingested_at`. No type casting, filtering, or deduplication in Bronze.

- **Why:** Bronze must be re-playable. Anything cleaned here cannot be audited later. Duplicates and bad rows are handled in Silver.

## D5. Idempotent loads by period
**Date:** 2026-10 · **Status:** decided

Each period (for example `2024q1`) is loaded by overwriting only that period's partition, so re-running never duplicates rows. Checked by a test that loads one period twice and compares row counts.

## D6. Time range
**Date:** 2026-10 · **Status:** decided

Start with `2023q1` through `2024q4` (8 quarterly files, about 4 GB compressed). Widen later by changing a list in the config.

- **Why:** a 10-K carries three fiscal years, so this window gives several years of annual segment history without downloading everything.
- **Fiscal-calendar effect:** Amazon's 10-K (February) lands in Q1 files, Apple's (early November) in Q4 files, Microsoft's (late July) in Q3 files.

## D7. A "segment" is an axis plus a member
**Date:** 2026-10-10 · **Status:** decided (from Phase 0 findings)

The segment dimension stores **axis, member, a clean display name, and a segment type** (business unit, geographic, product or service), per company.

- **Why:** Apple's `BusinessSegments` are geographic regions, while Amazon's are business units. Treating "segment" as one thing would mix incomparable splits.
- **Cost:** a hand-built mapping table per company (see Silver).

## D8. Reconcile per axis and per level
**Date:** 2026-10-10 · **Status:** decided (from Phase 0 findings)

Silver checks that segment values add up to the company-wide total, **one axis at a time**, and only among members at the same level.

- **Why:** `BusinessSegments` and `Geographical` sum exactly to the total (verified for Amazon and Apple). `ProductOrService` mixes a rollup (Product, Service) with finer categories, so summing every member double counts.
- **Rule:** never add members across axes, and never add rollup and detail members together.

---

## Open questions

| # | Question | Where it matters | Status |
|---|---|---|---|
| Q1 | **Why are company totals duplicated?** (Amazon 4 copies, Microsoft 4, Apple 2.) Compare `iprx`, `version`, `coreg`, `uom` on the copies. | Silver dedupe rule | TODO |
| Q2 | **How should the malformed `dim.tsv` row be handled in Bronze?** (line 185897, extra tab.) Skipping it silently loses data. | Bronze loader | TODO: record what was changed in the Phase 0 script |
| Q3 | **Which tag wins** when a company reports revenue under more than one tag for the same period? | Silver totals | open |
| Q4 | **Microsoft's segment members.** Not yet listed. | Segment mapping | open |
| Q5 | **Apple's full-year numbers.** Its 10-K is in the Q4 files, not inspected yet. | Segment history | open |
| Q6 | **Can the Databricks tier in use download from sec.gov and hold the data?** | Phase 1 platform | open |
| Q7 | **How to handle a segment definition that changes between years** (companies do restructure segments). | SCD Type 2 on the segment dimension | open, revisit in Phase 3 |
