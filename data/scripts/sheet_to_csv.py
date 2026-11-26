#!/usr/bin/env python3
"""Convert the GivePlease Excel workbook or Google Sheet export into one typed CSV per gp_raw table.

Input (one of):
  --xlsx  path/to/workbook.xlsx         Excel workbook, or a Google Sheet downloaded as .xlsx
  --csv-dir path/to/folder              one CSV per tab, named "<tab title>.csv" (Google Sheets CSV download)

Output (in --out/<load_id>/):
  <table>.csv          header = BigQuery column names; empty field = NULL; UTF-8; ready for bq load
  manifest.json        per table: source rows, output rows, age_status counts, ignored columns,
                       warnings, sha256; overall result
  rejects.csv          only if a value could not be converted (exit code 2, nothing should be loaded)

Every type rule lives in schemas/table_map.json. Nothing is auto-detected.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import pathlib
import re
import sys
import unicodedata
from collections import Counter
from decimal import Decimal, InvalidOperation

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from make_schemas import table_fields  # noqa: E402

EXCEL_EPOCH = dt.date(1899, 12, 30)        # Excel 1900 date system (accounts for the 1900 leap-year bug)
CURRENCY = re.compile(r"(?i)^(S\$|SGD|US\$|USD|\$)|(S\$|SGD|USD|\$)$")
SPACES = re.compile(r"[\s   ]+")


class CellError(ValueError):
    """A value that cannot be converted to its declared type."""


# ------------------------------------------------------------------ readers
def _norm_header(h):
    return "" if h is None else unicodedata.normalize("NFC", str(h)).strip()


def read_xlsx(path, sheet):
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    if sheet not in wb.sheetnames:
        raise SystemExit(f"Tab {sheet!r} not found in {path}. Tabs: {wb.sheetnames}")
    rows = wb[sheet].iter_rows(values_only=True)
    header = [_norm_header(h) for h in next(rows, ())]
    return header, rows


def read_csv(folder, sheet):
    p = pathlib.Path(folder) / f"{sheet}.csv"
    if not p.exists():
        raise SystemExit(f"CSV for tab {sheet!r} not found: {p}")
    f = p.open(newline="", encoding="utf-8-sig")
    r = csv.reader(f)
    header = [_norm_header(h) for h in next(r, [])]
    return header, ([None if v == "" else v for v in row] for row in r)


# ------------------------------------------------------------------ value converters
def is_blank(v):
    return v is None or (isinstance(v, str) and SPACES.sub("", v) == "") or (isinstance(v, float) and math.isnan(v))


def to_string(v, kind, warn):
    if is_blank(v):
        return None
    if isinstance(v, bool):
        raise CellError(f"boolean {v!r} in a text column")
    if isinstance(v, (int, float)):
        if kind == "id":
            warn("numeric_id_cell")          # leading zeros may already be lost in the source cell
        if isinstance(v, float) and v.is_integer():
            v = int(v)
        return str(v)
    if isinstance(v, (dt.date, dt.datetime)):
        raise CellError(f"date {v!r} in a text column")
    return unicodedata.normalize("NFC", str(v)).strip()


def to_decimal(v):
    if isinstance(v, bool):
        raise CellError(f"boolean {v!r} in a number column")
    if isinstance(v, int):
        return Decimal(v)
    if isinstance(v, float):
        if not math.isfinite(v):
            raise CellError(f"non-finite number {v!r}")
        return Decimal(repr(v))
    if isinstance(v, Decimal):
        return v
    s = SPACES.sub("", str(v))
    neg = s.startswith("(") and s.endswith(")")
    if neg:
        s = s[1:-1]
    s = CURRENCY.sub("", s).replace(",", "")
    if s in ("", "-"):
        return None
    try:
        d = Decimal(s)
    except InvalidOperation:
        raise CellError(f"not a number: {v!r}")
    if not d.is_finite():
        raise CellError(f"not a finite number: {v!r}")
    return -d if neg else d


def to_numeric(v, scale, warn):
    if is_blank(v):
        return None
    d = to_decimal(v)
    if d is None:
        return None
    exp = d.normalize().as_tuple().exponent
    if isinstance(exp, int) and -exp > scale:
        # A float like 0.30000000000000004 from a formula: accept if it rounds cleanly at 10 dp.
        r = d.quantize(Decimal(1).scaleb(-10))
        if -r.normalize().as_tuple().exponent > scale:
            raise CellError(f"{v!r} has more than {scale} decimal places")
        warn("float_artefact_rounded")
        d = r
    if d < 0:
        warn("negative_amount")
    q = d.quantize(Decimal(1).scaleb(-scale))
    return format(q, "f")


def to_int(v):
    if is_blank(v):
        return None
    d = to_decimal(v)
    if d is None:
        return None
    if d != d.to_integral_value():
        raise CellError(f"{v!r} is not a whole number")
    i = int(d)
    if not -(2 ** 63) <= i < 2 ** 63:
        raise CellError(f"{v!r} out of INT64 range")
    return i


def to_date(v, fmt):
    if is_blank(v):
        return None
    if isinstance(v, dt.datetime):
        return v.date().isoformat()
    if isinstance(v, dt.date):
        return v.isoformat()
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if not 1 <= v < 2958466:               # 1900-01-01 .. 9999-12-31
            raise CellError(f"date serial {v!r} out of range")
        return (EXCEL_EPOCH + dt.timedelta(days=int(v))).isoformat()
    s = str(v).strip()
    if re.fullmatch(r"\d+(\.\d+)?", s):         # serial number that arrived as text (CSV)
        return to_date(float(s), fmt)
    for f in ("%Y-%m-%d", fmt):
        try:
            return dt.datetime.strptime(s, f).date().isoformat()
        except (ValueError, TypeError):
            pass
    raise CellError(f"date {v!r} does not match YYYY-MM-DD or {fmt}")


def to_timestamp(v, fmt):
    if is_blank(v):
        return None
    if isinstance(v, dt.datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, dt.date):
        return v.strftime("%Y-%m-%d 00:00:00")
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if not 1 <= v < 2958466:
            raise CellError(f"timestamp serial {v!r} out of range")
        t = dt.datetime(1899, 12, 30) + dt.timedelta(days=float(v))
        return t.replace(microsecond=0).strftime("%Y-%m-%d %H:%M:%S")
    s = str(v).strip()
    for f in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", fmt):
        try:
            return dt.datetime.strptime(s, f).strftime("%Y-%m-%d %H:%M:%S")
        except (ValueError, TypeError):
            pass
    raise CellError(f"timestamp {v!r} does not match YYYY-MM-DD HH:MM:SS or {fmt}")


BOOLS = {"true": "true", "false": "false", "yes": "true", "no": "false", "y": "true", "n": "false", "1": "true", "0": "false"}


def to_bool(v):
    if is_blank(v):
        return None
    if isinstance(v, bool):
        return "true" if v else "false"
    k = str(v).strip().lower()
    if k.endswith(".0"):
        k = k[:-2]
    if k not in BOOLS:
        raise CellError(f"{v!r} is not a yes/no value")
    return BOOLS[k]


# ------------------------------------------------------------------ table conversion
def plan_columns(m, t, header):
    """Map sheet column positions to rules; decide which extra columns may be ignored."""
    rules, include_address = m["column_rules"], m["defaults"]["include_address"]
    expected = t["source_columns"]
    pos, ignored, problems = {}, [], []
    for i, h in enumerate(header):
        if h in expected and h not in pos:
            pos[h] = i
        else:
            ignored.append((i, h))          # blank header or a repeated header: allowed only if empty
    missing = [h for h in expected if h not in pos]
    if missing:
        problems.append(f"missing expected columns {missing}")
    plan = []
    for h in expected:
        if h not in pos:
            continue
        r = rules[h]
        if r["kind"] == "address" and not include_address:
            ignored.append((pos[h], h))     # personal data, dropped by policy (RAID D-02)
            continue
        plan.append((pos[h], h, r))
    return plan, ignored, problems


def convert_table(m, t, header, rows, load_id, out_dir):
    d = m["defaults"]
    fields = table_fields(m, t)
    names = [f["name"] for f in fields]
    plan, ignored, problems = plan_columns(m, t, header)
    address_dropped = {h for _, h in ignored if m["column_rules"].get(h, {}).get("kind") == "address"}
    extra = [(i, h) for i, h in ignored if h not in address_dropped]
    rejects, warns, age_status = [], Counter(), Counter()
    src_rows = out_rows = blank_rows = 0
    ignored_with_data = Counter()
    csv_path = out_dir / f"{t['table']}.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(names)
        for rownum, row in enumerate(rows, start=2):
            row = list(row or [])
            if all(is_blank(v) for v in row):
                blank_rows += 1
                continue
            src_rows += 1
            for i, h in extra:
                if i < len(row) and not is_blank(row[i]):
                    ignored_with_data[h or f"column {i + 1}"] += 1
            rec, bad = {}, False
            for i, h, r in plan:
                v = row[i] if i < len(row) else None
                try:
                    kind, typ = r["kind"], r["type"]
                    def warn(code, _h=h):
                        warns[f"{_h}: {code}"] += 1
                    if kind == "age":
                        raw = to_int(v)
                        rec["age_raw"] = raw
                        if raw is None or raw == 0:
                            rec["age"], rec["age_status"] = None, "unknown"
                        elif d["age_valid_min"] <= raw <= d["age_valid_max"]:
                            rec["age"], rec["age_status"] = raw, "valid"
                        else:
                            rec["age"], rec["age_status"] = None, "out_of_range"
                        age_status[rec["age_status"]] += 1
                    elif typ == "STRING":
                        rec[r["name"]] = to_string(v, kind, warn)
                    elif typ == "NUMERIC":
                        rec[r["name"]] = to_numeric(v, r.get("scale", d["money_scale"]), warn)
                    elif typ == "INT64":
                        rec[r["name"]] = to_int(v)
                    elif typ == "DATE":
                        rec[r["name"]] = to_date(v, r.get("format", "%d/%m/%Y"))
                    elif typ == "TIMESTAMP":
                        rec[r["name"]] = to_timestamp(v, r.get("format", "%d/%m/%Y %H:%M:%S"))
                    elif typ == "BOOL":
                        rec[r["name"]] = to_bool(v)
                    else:
                        raise CellError(f"unsupported type {typ}")
                    if r["mode"] == "REQUIRED" and rec.get(r["name"]) is None:
                        raise CellError("required value is blank")
                except CellError as e:
                    bad = True
                    rejects.append({"table": t["table"], "sheet_row": rownum, "column": h, "value": repr(v), "error": str(e)})
            if bad:
                continue
            if t.get("id_prefix") and rec.get("unique_id") and not rec["unique_id"].startswith(t["id_prefix"] + "-"):
                warns[f"Unique ID: not starting with {t['id_prefix']}-"] += 1
            rec["_source_row"], rec["_load_id"] = rownum, load_id
            w.writerow(["" if rec.get(n) is None else rec[n] for n in names])
            out_rows += 1
    for h, n in ignored_with_data.items():
        problems.append(f"column {h!r} is not in the map but holds data in {n} rows")
    sha = hashlib.sha256(csv_path.read_bytes()).hexdigest()
    return {
        "table": t["table"], "sheet": t["sheet"], "csv": csv_path.name, "sha256": sha,
        "source_rows": src_rows, "output_rows": out_rows, "rejected_rows": src_rows - out_rows,
        "blank_rows_skipped": blank_rows, "columns": names,
        "ignored_columns": [h or f"(blank header, column {i + 1})" for i, h in ignored],
        "age_status": dict(age_status), "warnings": dict(warns), "problems": problems,
    }, rejects


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--xlsx")
    src.add_argument("--csv-dir")
    ap.add_argument("--map", default="schemas/table_map.json")
    ap.add_argument("--out", default="out")
    ap.add_argument("--load-id", default=dt.datetime.now().strftime("%Y%m%dT%H%M%S"))
    ap.add_argument("--only", nargs="*", help="convert only these tables")
    a = ap.parse_args(argv)

    m = json.loads(pathlib.Path(a.map).read_text())
    out_dir = pathlib.Path(a.out) / a.load_id
    out_dir.mkdir(parents=True, exist_ok=True)
    tables, all_rejects = [], []
    for t in m["tables"]:
        if not t["include"] or (a.only and t["table"] not in a.only):
            continue
        header, rows = read_xlsx(a.xlsx, t["sheet"]) if a.xlsx else read_csv(a.csv_dir, t["sheet"])
        info, rejects = convert_table(m, t, header, rows, a.load_id, out_dir)
        tables.append(info)
        all_rejects += rejects
        flag = "OK " if info["rejected_rows"] == 0 and not info["problems"] else "ERR"
        print(f"{flag} {t['table']:<26} source {info['source_rows']:>6}  output {info['output_rows']:>6}  "
              f"rejected {info['rejected_rows']:>4}  age {info['age_status'] or '-'}")
        for p in info["problems"]:
            print(f"    problem: {p}")
    if all_rejects:
        with (out_dir / "rejects.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["table", "sheet_row", "column", "value", "error"])
            w.writeheader()
            w.writerows(all_rejects)
    ok = not all_rejects and not any(t["problems"] for t in tables)
    manifest = {"load_id": a.load_id, "source": a.xlsx or a.csv_dir, "map": a.map,
                "created_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "include_address": m["defaults"]["include_address"],
                "age_valid_range": [m["defaults"]["age_valid_min"], m["defaults"]["age_valid_max"]],
                "result": "PASS" if ok else "FAIL", "tables": tables}
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\n{manifest['result']}: {len(tables)} tables, {sum(t['output_rows'] for t in tables)} rows -> {out_dir}")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
