# Data dictionary: SEC Financial Statement and Notes Data Sets

Findings from Phase 0 exploration of the **2024q1** release, checked against
SEC's documentation (`https://www.sec.gov/files/aqfsn_1.pdf`). Everything marked
"observed" comes from running `exploration/explore_quarter.py` on real data.
Only one quarter has been inspected so far, so treat the observations as
provisional until the same checks are run on other periods.

## 1. Source

| Item | Value |
|---|---|
| Dataset | Financial Statement and Notes Data Sets (SEC) |
| Landing page | https://www.sec.gov/data-research/sec-markets-data/financial-statement-notes-data-sets |
| Contents | Numeric and text facts from XBRL filings, flattened into tab-separated tables, "as filed" (not corrected) |
| Coverage | 2009 through the latest month published |
| Quarterly files | `{year}q{quarter}_notes.zip`, e.g. `2024q1_notes.zip` (about 400-630 MB each) |
| Monthly files | `{year}_{mm}_notes.zip`, e.g. `2025_08_notes.zip` (published since Nov 2020; consolidated into quarterly files after about a year) |
| Base URL | `https://www.sec.gov/files/dera/data/financial-statement-notes-data-sets/` |
| Access rules | Send a `User-Agent` header with contact details; stay well under 10 requests per second |
| File format (observed) | Tab-delimited `.tsv`, UTF-8, header row in lowercase |

## 2. Tables used by this project

The ZIP contains eight tables. This project uses four.

| Table | One row is... | Observed size (2024q1) |
|---|---|---|
| `sub` | one EDGAR filing (10-K, 10-Q, ...) | 24,364 rows, 40 columns |
| `num` | one numeric fact in a filing | very large (not counted; the whole ZIP is 590 MB); 3,205 rows for our 3 filings |
| `dim` | one distinct breakdown (axis and member) | 703,169 rows, 3 columns |
| `tag` | one tag's definition (label, datatype) | not yet inspected |

Not used for now: `txt` (text facts), `pre` (statement placement, may be useful
later), `ren`, `cal`.

### Joins

```
num.adsh                 = sub.adsh                (which filing and company)
num.dimh                 = dim.dimh                (which breakdown)
num.tag + num.version    = tag.tag + tag.version   (what the fact means)
```

### `sub` (key columns)

`adsh` (filing ID, primary key), `cik` (company ID), `name`, `sic`, `form`
(10-K, 10-Q...), `period` (balance sheet date, yyyymmdd), `fy`, `fp` (FY, Q1,
Q2, Q3...), `filed` (yyyymmdd), `accepted`, `prevrpt` (1 = later amended).

Full column list (observed): adsh, cik, name, sic, countryba, stprba, cityba,
zipba, bas1, bas2, baph, countryma, stprma, cityma, zipma, mas1, mas2,
countryinc, stprinc, ein, former, changed, afs, wksi, fye, form, period, fy, fp,
filed, accepted, prevrpt, detail, instance, nciks, aciks, pubfloatusd,
floatdate, floataxis, floatmems.

### `num` (all 16 columns, observed)

| Column | Meaning |
|---|---|
| `adsh` | Filing ID |
| `tag` | What the number is, as tagged by the filer (e.g. `RevenueFromContractWithCustomerExcludingAssessedTax`) |
| `version` | Taxonomy the tag comes from; for company-defined (custom) tags it equals the filing's `adsh` |
| `ddate` | Period end date, `yyyymmdd`, rounded to month end |
| `qtrs` | Length of the period in quarters. `0` = a single point in time, `1` = a quarter, `2` = six months, `4` = a year |
| `uom` | Unit of measure (e.g. `USD`) |
| `dimh` | Link to `dim`. `0x00000000` means no breakdown (see section 4) |
| `iprx` | Tie-breaker for facts that are otherwise identical; `1` is the preferred one |
| `value` | The number, **not scaled** (plain dollars), four decimals, e.g. `62202000000.0000` |
| `footnote`, `footlen` | Footnote text and its original length |
| `dimn` | Number of breakdown dimensions on the fact (0 or 1 are the cases we use) |
| `coreg` | Co-registrant; empty means the consolidated company |
| `durp`, `datp`, `dcml` | Precision indicators used to rank duplicate facts |

### `dim` (observed)

| Column | Meaning |
|---|---|
| `dimh` | Key. A hash of the `segments` text |
| `segments` | Breakdown as text in the form `Axis=Member;`, e.g. `BusinessSegments=AmazonWebServicesSegment;`. The words "Statement", "Axis", "Member" and "Domain" are stripped from the names |
| `segt` | Flag: whether `segments` was truncated |

Several dimensions on one fact are concatenated: `Axis1=Member1;Axis2=Member2;`.

## 3. How to read a segment fact

1. Take a `num` row with `dimn = 1`.
2. Look up `dimh` in `dim` to get `segments`.
3. Split `segments` at `=`. The left part is the **axis** (the kind of breakdown),
   the right part without the `;` is the **member** (the specific value).

Example: `BusinessSegments=AmazonWebServicesSegment;` is axis `BusinessSegments`,
member `AmazonWebServicesSegment`.

## 4. The "no breakdown" code

- Company-wide totals have `dimn = 0` and `dimh = 0x00000000`.
- SEC's documentation describes this as `0`. The data actually contains the
  string `0x00000000`. Filter on `dimn = '0'` rather than relying on the code.
- In 2024q1, 1,605 of the 3,205 `num` rows for our three filings were totals.

## 5. Breakdown axes per company (observed, 2024q1)

Number of distinct members under each axis, single-dimension facts only. Only
the axes relevant to revenue are listed; each company has many more
(debt, equity, fair value, taxes...).

| Company | `BusinessSegments` | `ProductOrService` | `Geographical` |
|---|---|---|---|
| Amazon (10-K, FY2023) | 3 | 10 | 5 |
| Apple (10-Q, fiscal Q1 2024) | 5 | 6 | not seen |
| Microsoft (10-Q, fiscal Q2 2024) | 3 | 12 | 2 |

**"Segment" means different things per company.**

- **Amazon `BusinessSegments`**: `AmazonWebServicesSegment`, `InternationalSegment`,
  `NorthAmericaSegment`.
- **Apple `BusinessSegments` are geographic regions**: `AmericasSegment`,
  `EuropeSegment`, `GreaterChinaSegment`, `JapanSegment`,
  `RestOfAsiaPacificSegment`. Apple's Products-versus-Services split sits under
  `ProductOrService`, not `BusinessSegments`.
- **Microsoft**: three `BusinessSegments` exist; member names have not been
  inspected yet.
- **Amazon `ProductOrService`** members seen: `Advertising`, `AmazonWebServices`,
  `OnlineStores`, `OtherServices`, `PhysicalStores`, `Product`, `Service`,
  `SubscriptionServices`, `ThirdPartySellerServices` (9 of 10 seen in the
  printed rows).
- **Amazon `Geographical`**: `US`, `DE`, `GB`, `JP`, `NonUs` (here `NonUs` is the
  remaining "rest of world" bucket, not a total of the other countries).

Consequence for the model: the segment dimension needs an `axis` (and a
`segment_type`), not just a name.

## 6. Reconciliation results (observed)

Segment sums versus company-wide revenue, in USD millions.

| Company, period | Split | Sum of members | Reported total | Match |
|---|---|---|---|---|
| Amazon FY2021 | BusinessSegments (3) | 469,822 | 469,822 | yes |
| Amazon FY2022 | BusinessSegments (3) | 513,983 | 513,983 | yes |
| Amazon FY2023 | BusinessSegments (3) | 574,785 | 574,785 | yes |
| Amazon FY2022, FY2023 | Geographical (5) | 513,983 / 574,785 | same | yes |
| Amazon FY2021-FY2023 | `Product` + `Service` | equals total | | yes |
| Amazon FY2021, FY2023 | 7 finer `ProductOrService` members | equals total | | yes |
| Apple, quarter ended 2022-12-31 | BusinessSegments (5 regions) | 117,154 | 117,154 | yes |

**Overlap warning.** Amazon's `ProductOrService` axis contains two different
splits of the same revenue: `Product` + `Service`, and seven finer categories
(online stores, AWS, ...). Each split sums to the total on its own. **Adding all
members of the axis counts the revenue twice.** Reconciliation must therefore be
done per axis and per level, and never by summing every member.

## 7. Periods and fiscal calendars (observed)

- A **10-K** carries three years of annual data (Amazon FY2023 filing contains
  2021, 2022 and 2023, all with `qtrs = 4`).
- A **10-Q** carries the current and the prior-year quarter (Apple), and for
  Microsoft also the six-month figures (`qtrs = 2`).
- `fy` and `fp` follow each company's own fiscal calendar: the period ending
  2023-12-31 is `fy 2024 / Q1` for Apple, `fy 2024 / Q2` for Microsoft and
  `fy 2023 / FY` for Amazon. **Use `ddate` and `qtrs` to align periods across
  companies, not `fy` and `fp`.**
- Which release file contains a filing depends on when it was filed. Amazon's
  10-K (filed 2024-02-02) is in `2024q1`; Apple's own 10-K is filed in
  November and should appear in the Q4 files.

## 8. Data quality findings

| # | Finding | Impact | Status |
|---|---|---|---|
| 1 | `dim.tsv` (2024q1) has a row with an extra tab. pandas error: `Expected 3 fields in line 185897, saw 4` | Strict parsers fail; lenient ones skip or merge the row | Row not yet inspected. Bronze must load without crashing |
| 2 | Company-wide revenue appears several times in the joined data (Amazon 4 copies, Microsoft 4, Apple 2), with identical values | Sums would be inflated if not deduplicated | **Cause not determined** (see `decisions.md`, open question 1) |
| 3 | The tag `Revenues` also appears under the axis `EquityMethodInvestmentNonconsolidatedInvestee`; that is an investee's revenue, not Amazon's | Filtering on the revenue tag alone pulls in the wrong numbers | Filter on the axis as well |
| 4 | Members within `ProductOrService` overlap (section 6) | Double counting | Reconcile per axis and level |
| 5 | Companies use different tags for revenue (`RevenueFromContractWithCustomerExcludingAssessedTax`, `Revenues`, ...) | Needs a tag priority list | Handled in Silver |
| 6 | `value` is unscaled and `ddate` is rounded to month end | None if known | Documented here |
