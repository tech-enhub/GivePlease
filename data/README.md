# gp_raw load kit: schemas and sheet-to-CSV conversion (WS02[a])

Turns the donor data that GivePlease exports from Amazon RDS for MySQL (shared as an Excel workbook or Google Sheet) into one typed CSV per BigQuery table, ready for `bq load` into `gp_raw` with an explicit schema. Nothing is auto-detected.

## Layout

| Path | What it is |
|---|---|
| `schemas/table_map.json` | The single place every rule lives: which tab goes to which table, column names, types, the Address and age policies. **Edit this file, not the generated schemas.** |
| `schemas/gp_raw/*.json` | BigQuery schema files, one per table, generated from the map by `scripts/make_schemas.py`. |
| `scripts/make_schemas.py` | Regenerates the schema files from the map. |
| `scripts/sheet_to_csv.py` | The conversion. Reads an `.xlsx` (Excel, or the Google Sheet downloaded as .xlsx) or a folder of per-tab CSVs. Writes the CSVs, `manifest.json`, and `rejects.csv` if anything failed. |
| `tests/test_sheet_to_csv.py` | 33 trap tests: date serial numbers, leading zeros, currency text, blanks, the age rules, Address on/off, column drift. |
| `evidence/` | Output of the run on the real sheet (26 Nov 2026) and of the tests. |

## Run it

Run from this `data/` folder. Keep the source workbook and the `out/` folder outside git (both are in `.gitignore`).

```bash
python3 scripts/make_schemas.py                                   # after any change to the map
python3 scripts/sheet_to_csv.py --xlsx donor_data.xlsx --load-id 20261126T1300 --out out
#   or: --csv-dir folder_with_one_csv_per_tab
python3 -m pytest -q tests/                                       # 33 passed
```

Exit code 0 = PASS, every source row converted. Exit code 2 = FAIL: see `rejects.csv` (row, column, value, reason) and the `problems` in `manifest.json`. **Load nothing from a FAIL run.**

The load itself (next step, not run yet):

```bash
gsutil cp out/<load_id>/*.csv  gs://giveplease-ai-reports-landing/raw/<table>/<load_id>/
bq load --source_format=CSV --skip_leading_rows=1 --max_bad_records=0 --replace \
  gp_raw.<table> gs://giveplease-ai-reports-landing/raw/<table>/<load_id>/<table>.csv \
  schemas/gp_raw/<table>.json
```

## Safe defaults in force (until the lead answers)

| Decision | Default now | Where to change it |
|---|---|---|
| D-02 Address (personal data) | **Dropped.** Not in the schema, not in the CSV. | `defaults.include_address: true`, then `make_schemas.py` |
| D-03 invalid ages | 0 or blank → `age` NULL, `age_status = unknown`. Below 1 or above 110 → `age` NULL, `age_status = out_of_range`. The original value is always kept in `age_raw`, so the rule can change later without re-loading. | `defaults.age_valid_min / age_valid_max` |
| D-07 which tabs | **All 8 converted.** Normal Donors Export and Normal Donors (Filtered) are identical apart from the ID prefix; 109 receipts are in both OnBehalf "without" tabs. Raw keeps every tab as supplied; curated views must pick one, or totals double. | `tables[].include: false` |
| Currency | Assumed SGD (noted in column descriptions). | `column_rules[...].description` |

## Type rules

| Source column | BigQuery column | Type | Why |
|---|---|---|---|
| Unique ID | `unique_id` | STRING, required | Identifier with a prefix; text keeps any leading zeros |
| ReceiptNo | `receipt_no` | STRING, required | Same |
| Age / AGE | `age`, `age_raw`, `age_status` | INT64, INT64, STRING | See D-03 above |
| Donation Amount (2019)…(2026) | `donation_amount_2019`…`_2026` | NUMERIC, 2 decimals | Money: exact decimal, never FLOAT64 |
| – | `_source_row`, `_load_id` | INT64, STRING | Trace each row back to the sheet row and the load batch |

Tables stay in the sheet's wide layout (one column per year), so row counts reconcile one-to-one with the sheet. The long layout (one row per donor per year) belongs in the curated views.

## What the conversion guards against

- **Dates stored as numbers.** Excel serials (45292 → 2024-01-01), real date cells, `YYYY-MM-DD`, or the column's declared format (default `dd/mm/yyyy`). Anything ambiguous is rejected.
- **Leading zeros.** ID columns are read as text. If an ID cell arrives as a number (Excel already stripped the zeros), it's flagged in the warnings.
- **Currency formatting.** `S$`, `SGD`, `$`, thousands separators, non-breaking spaces and `(75.50)` negatives are cleaned. More than 2 real decimals is rejected; float noise such as 0.30000000000000004 is rounded and flagged.
- **Blanks.** Empty or whitespace-only cells become NULL. Fully blank rows are skipped and counted. A blank in a required column is rejected.
- **Column drift.** A missing expected column fails the run. A new column holding data fails the run. Blank or duplicated header columns with no data (as on the Anonymous Donors tab) are ignored and listed in the manifest.

## Results on the real sheet (26 Nov 2026)

PASS: 8 tables, 127,948 rows, 0 rejected.

- Both input routes (.xlsx and per-tab CSV) give identical output.
- Every donation column totals exactly to the source.
- Every Unique ID is unchanged, in order.

| Table | Rows | Age valid / unknown / out of range |
|---|---|---|
| normal_donors | 45,337 | 13,919 / 31,415 / 3 |
| normal_donors_filtered | 45,337 | 13,919 / 31,415 / 3 |
| normal_donors_ndwn | 27,592 | 8,463 / 19,111 / 18 |
| normal_donors_ndwa | 9,356 | 1,149 / 8,207 / 0 |
| onbehalf_deceased | 32 | 8 / 24 / 0 |
| onbehalf_without_nric | 147 | 147 / 0 / 0 |
| onbehalf_without_address | 146 | 131 / 15 / 0 |
| anonymous_donors | 1 | – |

The sheet has no date columns, no leading-zero IDs and no currency text. Those protections are proven by the trap tests rather than by this data.
