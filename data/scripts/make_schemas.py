#!/usr/bin/env python3
"""Generate BigQuery schema JSON files (one per gp_raw table) from schemas/table_map.json.

Usage: python3 scripts/make_schemas.py [--map schemas/table_map.json] [--out schemas/gp_raw]
"""
import argparse
import json
import pathlib


def table_fields(m, t):
    """Ordered list of BigQuery fields for one table entry of the map."""
    rules, derived = m["column_rules"], m["derived_columns"]
    include_address = m["defaults"]["include_address"]
    fields = []
    for src in t["source_columns"]:
        r = rules.get(src)
        if r is None:
            raise SystemExit(f"{t['table']}: no column rule for source header {src!r}")
        if r["kind"] == "address" and not include_address:
            continue
        f = {"name": r["name"], "type": r["type"], "mode": r["mode"], "description": r["description"]}
        fields.append(f)
        for d in derived.get(r["kind"], []):
            fields.append(dict(d))
    fields.extend(dict(c) for c in m["load_columns"])
    names = [f["name"] for f in fields]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        raise SystemExit(f"{t['table']}: duplicate column names {sorted(dupes)}")
    return fields


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="schemas/table_map.json")
    ap.add_argument("--out", default="schemas/gp_raw")
    a = ap.parse_args()
    m = json.loads(pathlib.Path(a.map).read_text())
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.json"):
        old.unlink()
    for t in m["tables"]:
        if not t["include"]:
            continue
        fields = table_fields(m, t)
        (out / f"{t['table']}.json").write_text(json.dumps(fields, indent=2) + "\n")
        print(f"{t['table']}: {len(fields)} columns")


if __name__ == "__main__":
    main()
