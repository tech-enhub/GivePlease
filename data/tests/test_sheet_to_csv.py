"""Trap tests for scripts/sheet_to_csv.py: every Excel / Google Sheet quirk we guard against.

Run: python3 -m pytest -q tests/
"""
import copy
import csv
import datetime as dt
import json
import pathlib
import sys

import pytest
from openpyxl import Workbook

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import sheet_to_csv as conv  # noqa: E402

BASE_MAP = json.loads((ROOT / "schemas" / "table_map.json").read_text())


def make_map(extra_rules=None, tables=None, **defaults):
    m = copy.deepcopy(BASE_MAP)
    m["column_rules"].update(extra_rules or {})
    m["defaults"].update(defaults)
    m["tables"] = tables
    return m


def write_xlsx(path, sheets):
    wb = Workbook()
    wb.remove(wb.active)
    for title, rows in sheets.items():
        ws = wb.create_sheet(title)
        for r in rows:
            ws.append(r)
    wb.save(path)


def run(tmp_path, m, sheets, as_csv=False, include=None):
    tmp_path.mkdir(parents=True, exist_ok=True)
    mp = tmp_path / "map.json"
    mp.write_text(json.dumps(m))
    if as_csv:
        d = tmp_path / "csv"
        d.mkdir()
        for title, rows in sheets.items():
            with (d / f"{title}.csv").open("w", newline="", encoding="utf-8") as f:
                csv.writer(f).writerows([["" if v is None else v for v in r] for r in rows])
        args = ["--csv-dir", str(d)]
    else:
        x = tmp_path / "in.xlsx"
        write_xlsx(x, sheets)
        args = ["--xlsx", str(x)]
    rc = conv.main(args + ["--map", str(mp), "--out", str(tmp_path / "out"), "--load-id", "T1"])
    out = tmp_path / "out" / "T1"
    man = json.loads((out / "manifest.json").read_text())
    data = {t["table"]: list(csv.DictReader((out / t["csv"]).open())) for t in man["tables"]}
    rej = list(csv.DictReader((out / "rejects.csv").open())) if (out / "rejects.csv").exists() else []
    return rc, man, data, rej


TRAP_RULES = {
    "Gift Date": {"name": "gift_date", "type": "DATE", "mode": "NULLABLE", "kind": "date", "format": "%d/%m/%Y", "description": "d"},
    "Created At": {"name": "created_at", "type": "TIMESTAMP", "mode": "NULLABLE", "kind": "ts", "description": "t"},
    "Recurring": {"name": "is_recurring", "type": "BOOL", "mode": "NULLABLE", "kind": "bool", "description": "b"},
}
TRAP_COLS = ["Unique ID", "ReceiptNo", "AGE", "Address", "Donation Amount  (2024)", "Gift Date", "Created At", "Recurring"]
TRAP_TABLE = [{"sheet": "Gifts", "table": "gifts", "include": True, "id_prefix": "UID-T", "description": "x", "source_columns": TRAP_COLS}]


def trap_sheet(rows):
    return {"Gifts": [TRAP_COLS] + rows}


# ------------------------------------------------------------------ dates
def test_excel_date_serial_becomes_iso_date(tmp_path):
    rows = [["UID-T-1", "R1", 40, None, 10, 45292, 45292.5, "yes"]]      # 45292 = 2024-01-01
    rc, _, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    r = d["gifts"][0]
    assert rc == 0
    assert r["gift_date"] == "2024-01-01"
    assert r["created_at"] == "2024-01-01 12:00:00"
    assert r["is_recurring"] == "true"


def test_real_date_cell_and_text_formats(tmp_path):
    rows = [["UID-T-1", "R1", 40, None, 10, dt.datetime(2025, 8, 14), "2025-08-14 09:30:00", "N"],
            ["UID-T-2", "R2", 40, None, 10, "14/08/2025", dt.datetime(2025, 8, 14, 9, 30), 0],
            ["UID-T-3", "R3", 40, None, 10, "2025-08-14", None, None]]
    rc, _, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 0
    assert [r["gift_date"] for r in d["gifts"]] == ["2025-08-14"] * 3
    assert d["gifts"][1]["created_at"] == "2025-08-14 09:30:00"
    assert [r["is_recurring"] for r in d["gifts"]] == ["false", "false", ""]


def test_date_serial_arriving_as_text_in_csv(tmp_path):
    rows = [["UID-T-1", "R1", 40, None, 10, "45292", "", ""]]
    rc, _, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows), as_csv=True)
    assert rc == 0 and d["gifts"][0]["gift_date"] == "2024-01-01"


def test_ambiguous_or_bad_date_is_rejected(tmp_path):
    rows = [["UID-T-1", "R1", 40, None, 10, "08-14-2025", None, None],
            ["UID-T-2", "R2", 40, None, 10, "31/02/2025", None, None]]
    rc, man, d, rej = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 2 and len(rej) == 2 and d["gifts"] == []
    assert man["result"] == "FAIL"


# ------------------------------------------------------------------ leading zeros / IDs
def test_leading_zeros_survive_when_cell_is_text(tmp_path):
    rows = [["UID-T-00123", "0000456", 40, None, 10, None, None, None]]
    rc, _, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 0
    assert d["gifts"][0]["unique_id"] == "UID-T-00123"
    assert d["gifts"][0]["receipt_no"] == "0000456"


def test_numeric_id_cell_is_flagged(tmp_path):
    rows = [["UID-T-1", 456, 40, None, 10, None, None, None]]         # Excel already turned 000456 into 456
    rc, man, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 0 and d["gifts"][0]["receipt_no"] == "456"
    assert man["tables"][0]["warnings"] == {"ReceiptNo: numeric_id_cell": 1}


def test_id_prefix_mismatch_is_flagged(tmp_path):
    rows = [["UID-X-1", "R1", 40, None, 10, None, None, None]]
    _, man, _, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert "Unique ID: not starting with UID-T-" in man["tables"][0]["warnings"]


# ------------------------------------------------------------------ currency / money
@pytest.mark.parametrize("raw,expected", [
    ("S$1,250.00", "1250.00"), ("$ 50", "50.00"), ("SGD 7.5", "7.50"), ("1 000.10", "1000.10"),
    ("12.5 SGD", "12.50"), (1250, "1250.00"), (8016.75, "8016.75"), ("-", ""), ("", ""), (None, ""),
])
def test_currency_formatting_is_cleaned(tmp_path, raw, expected):
    rows = [["UID-T-1", "R1", 40, None, raw, None, None, None]]
    rc, _, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 0 and d["gifts"][0]["donation_amount_2024"] == expected


def test_accounting_negative_is_kept_and_flagged(tmp_path):
    rows = [["UID-T-1", "R1", 40, None, "(75.50)", None, None, None]]
    rc, man, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 0 and d["gifts"][0]["donation_amount_2024"] == "-75.50"
    assert man["tables"][0]["warnings"]["Donation Amount  (2024): negative_amount"] == 1


def test_float_artefact_rounded_but_real_extra_decimals_rejected(tmp_path):
    rows = [["UID-T-1", "R1", 40, None, 0.1 + 0.2, None, None, None],
            ["UID-T-2", "R2", 40, None, 1.234, None, None, None],
            ["UID-T-3", "R3", 40, None, "12abc", None, None, None]]
    rc, man, d, rej = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 2
    assert [r["donation_amount_2024"] for r in d["gifts"]] == ["0.30"]
    assert sorted(r["sheet_row"] for r in rej) == ["3", "4"]


# ------------------------------------------------------------------ blanks
def test_blank_cells_and_blank_rows(tmp_path):
    rows = [["UID-T-1", "R1", None, None, "   ", None, None, None],
            [None, None, None, None, None, None, None, None],                # fully blank row: skipped, counted
            ["UID-T-2", "R2", "", None, None, None, None, None]]
    rc, man, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    t = man["tables"][0]
    assert rc == 0 and t["source_rows"] == 2 and t["output_rows"] == 2 and t["blank_rows_skipped"] == 1
    assert d["gifts"][0]["donation_amount_2024"] == "" and d["gifts"][0]["age_status"] == "unknown"
    assert d["gifts"][1]["_source_row"] == "4"                                # row numbers still match the sheet


def test_required_blank_is_rejected(tmp_path):
    rows = [[None, "R1", 40, None, 10, None, None, None]]
    rc, _, _, rej = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 2 and rej[0]["column"] == "Unique ID" and "required" in rej[0]["error"]


# ------------------------------------------------------------------ age policy
@pytest.mark.parametrize("raw,age,raw_out,status", [
    (0, "", "0", "unknown"), (None, "", "", "unknown"), (62, "62", "62", "valid"), (62.0, "62", "62", "valid"),
    (-952, "", "-952", "out_of_range"), (234, "", "234", "out_of_range"), (110, "110", "110", "valid"),
])
def test_age_policy(tmp_path, raw, age, raw_out, status):
    rows = [["UID-T-1", "R1", raw, None, 10, None, None, None]]
    rc, _, d, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    r = d["gifts"][0]
    assert rc == 0 and (r["age"], r["age_raw"], r["age_status"]) == (age, raw_out, status)


def test_fractional_age_is_rejected(tmp_path):
    rows = [["UID-T-1", "R1", 45.5, None, 10, None, None, None]]
    rc, _, _, rej = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert rc == 2 and "whole number" in rej[0]["error"]


# ------------------------------------------------------------------ address policy (D-02)
def test_address_dropped_by_default_and_loaded_when_enabled(tmp_path):
    rows = [["UID-T-1", "R1", 40, "1 Main St", 10, None, None, None]]
    _, _, d, _ = run(tmp_path / "a", make_map(TRAP_RULES, TRAP_TABLE), trap_sheet(rows))
    assert "address" not in d["gifts"][0]
    _, _, d, _ = run(tmp_path / "b", make_map(TRAP_RULES, TRAP_TABLE, include_address=True), trap_sheet(rows))
    assert d["gifts"][0]["address"] == "1 Main St"


# ------------------------------------------------------------------ header drift
def test_missing_column_fails(tmp_path):
    sheet = {"Gifts": [TRAP_COLS[:-1]] + [["UID-T-1", "R1", 40, None, 10, None, None]]}
    rc, man, _, _ = run(tmp_path, make_map(TRAP_RULES, TRAP_TABLE), sheet)
    assert rc == 2 and "missing expected columns" in man["tables"][0]["problems"][0]


def test_unknown_column_with_data_fails_but_empty_extra_columns_are_ignored(tmp_path):
    hdr = TRAP_COLS + ["", "Donation Amount  (2024)", "Notes"]
    ok = {"Gifts": [hdr, ["UID-T-1", "R1", 40, None, 10, None, None, None, None, None, None]]}
    rc, man, _, _ = run(tmp_path / "ok", make_map(TRAP_RULES, TRAP_TABLE), ok)
    assert rc == 0 and len(man["tables"][0]["ignored_columns"]) == 4         # Address + 3 extras
    bad = {"Gifts": [hdr, ["UID-T-1", "R1", 40, None, 10, None, None, None, None, None, "call back"]]}
    rc, man, _, _ = run(tmp_path / "bad", make_map(TRAP_RULES, TRAP_TABLE), bad)
    assert rc == 2 and "'Notes'" in man["tables"][0]["problems"][0]


# ------------------------------------------------------------------ schema / CSV agreement
def test_csv_header_matches_generated_schema():
    from make_schemas import table_fields
    for t in BASE_MAP["tables"]:
        schema = json.loads((ROOT / "schemas" / "gp_raw" / f"{t['table']}.json").read_text())
        assert [f["name"] for f in schema] == [f["name"] for f in table_fields(BASE_MAP, t)]
