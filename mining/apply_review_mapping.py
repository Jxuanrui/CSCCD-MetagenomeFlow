#!/usr/bin/env python3
"""Apply the human-approved review_mapping_draft to curation.sqlite.

Policy (ratified 2026-09-23):
  - HIGH/MEDIUM proposals applied (LOW left unmapped: 宁缺毋滥)
  - cross-ontology IDs (HP:/NCIT:) allowed in disease field (prefix self-describing)
  - one-to-many proposals joined with ';' (existing convention)
  - unmappable stays NULL, method='review_unmappable'
  - 'Donor' recoded as healthy control (condition_group='healthy')
"""
import sqlite3
import sys
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "curation.sqlite"
DRAFT = ROOT / "review_mapping_draft.yaml"
RANK = {"high": 3, "medium": 2, "low": 1}


def main():
    entries = yaml.safe_load(DRAFT.read_text())["entries"]
    con = sqlite3.connect(DB)
    cur = con.cursor()
    cur.execute("PRAGMA table_info(review_queue)")
    if "resolved" not in [r[1] for r in cur.fetchall()]:
        cur.execute("ALTER TABLE review_queue ADD COLUMN resolved INTEGER DEFAULT 0")

    stats = {"applied": 0, "unmappable": 0, "donor_healthy": 0, "rows_updated": 0}
    for e in entries:
        field, raw = e["field"], e["raw_value"]
        keys_sql = ("SELECT canonical_key FROM review_queue "
                    "WHERE field=? AND raw_value=? AND resolved=0")
        if field == "disease" and raw == "Donor":
            n = cur.execute("""UPDATE curation SET condition_group='healthy',
                               disease_method='review_healthy_rule'
                               WHERE canonical_key IN (%s)""" % keys_sql,
                            (field, raw)).rowcount
            stats["donor_healthy"] += n
        else:
            props = [p for p in e.get("proposal") or []
                     if p.get("confidence") in ("high", "medium")]
            if props:
                ids = ";".join(p["term_id"] for p in props)
                conf = max((p["confidence"] for p in props), key=lambda c: RANK[c])
                col = "disease" if field == "disease" else "body_site"
                n = cur.execute(
                    f"""UPDATE curation SET {col}_label=COALESCE({col}_label, ?),
                        {col}_{ 'mondo' if field == 'disease' else 'uberon'}=?,
                        {col}_method='review_applied', {col}_confidence=?
                        WHERE canonical_key IN (%s)""" % keys_sql,
                    (raw, ids, conf, field, raw)).rowcount
                stats["applied"] += n
            else:
                col = "disease" if field == "disease" else "body_site"
                n = cur.execute(
                    f"""UPDATE curation SET {col}_method='review_unmappable'
                        WHERE canonical_key IN (%s)""" % keys_sql,
                    (field, raw)).rowcount
                stats["unmappable"] += n
        cur.execute("UPDATE review_queue SET resolved=1 WHERE field=? AND raw_value=?",
                    (field, raw))
        stats["rows_updated"] += e.get("occurrence_count", 0)

    con.commit()
    print("applied:", stats["applied"], "| unmappable:", stats["unmappable"],
          "| donor->healthy:", stats["donor_healthy"])
    print("disease mapped total now:",
          cur.execute("SELECT COUNT(*) FROM curation WHERE disease_mondo IS NOT NULL "
                      "AND disease_mondo!=''").fetchone()[0], "/ 66607")
    print("review_queue unresolved left:",
          cur.execute("SELECT COUNT(*) FROM review_queue WHERE resolved=0").fetchone()[0])
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
