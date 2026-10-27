"""שלב 2: גיבוי, פירוק וניתוח של dictionary.json הקיים (ללא שינוי).

פלט (בתיקיית העבודה):
  baseline/dictionary.original.json   עותק זהה בייט-לבייט + hash
  baseline/existing_records.jsonl     רשומה לכל (מילון, מפתח), עם פירושים מפורקים
  baseline/regression_snapshot.json   כל הפירושים הקיימים, לבדיקת "לא נמחק דבר"
  reports/baseline_stats.json         מדדים
  reports/baseline_duplicates.csv     כפילויות בתוך מילון ובין מילונים
  reports/baseline_anomalies.csv      שדות ריקים, סימונים חריגים וכו'
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

from common import (
    HEBREW_LETTER_RE,
    INVISIBLE_RE,
    MARKS_RE,
    load_config,
    normalize_key,
    parse_sense,
    repo_root,
    sha256_file,
    split_senses,
    split_synonyms,
    stable_id,
    work_dir,
    write_json,
    write_jsonl,
)


def dict_slug(name: str) -> str:
    return stable_id(name, length=6)


def build_records(data: dict[str, list[dict[str, str]]]) -> list[dict]:
    """רשומה לכל (מילון, מפתח) עם פירושים מפורקים ומזהים יציבים."""
    records: list[dict] = []
    for name, entries in data.items():
        seen: dict[str, int] = {}
        for index, entry in enumerate(entries):
            for key, value in entry.items():
                base = stable_id(name, key)
                seen[base] = seen.get(base, 0) + 1
                suffix = "" if seen[base] == 1 else f"-{seen[base]}"
                rec_id = f"ex-{dict_slug(name)}-{base}{suffix}"
                senses = []
                for n, raw in enumerate(split_senses(str(value))):
                    parsed = parse_sense(raw)
                    parsed["sense_id"] = f"{rec_id}-s{n + 1}"
                    parsed["synonyms"] = split_synonyms(parsed["text"])
                    senses.append(parsed)
                records.append(
                    {
                        "record_id": rec_id,
                        "dictionary": name,
                        "position": index,
                        "key": key,
                        "normalized_key": normalize_key(key),
                        "raw_value": value,
                        "senses": senses,
                    }
                )
    return records


def analyze(records: list[dict]) -> tuple[dict, list[list], list[list]]:
    stats: dict = {"dictionaries": {}}
    duplicates: list[list] = [["kind", "dictionary", "normalized_key", "record_ids", "keys", "values"]]
    anomalies: list[list] = [["kind", "dictionary", "record_id", "key", "value"]]
    by_dict: dict[str, list[dict]] = defaultdict(list)
    for rec in records:
        by_dict[rec["dictionary"]].append(rec)

    norm_index: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for name, recs in by_dict.items():
        s = {
            "records": len(recs),
            "unique_raw_keys": len({r["key"] for r in recs}),
            "unique_normalized_keys": len({r["normalized_key"] for r in recs}),
            "multi_sense_records": sum(1 for r in recs if len(r["senses"]) > 1),
            "total_senses": sum(len(r["senses"]) for r in recs),
            "empty_values": 0,
            "with_curly_expression": 0,
            "with_expansion": 0,
            "multiword_keys": sum(1 for r in recs if " " in r["normalized_key"]),
            "keys_with_quotes": sum(1 for r in recs if '"' in r["normalized_key"] or "'" in r["normalized_key"]),
            "keys_with_niqqud": sum(1 for r in recs if MARKS_RE.search(r["key"])),
            "keys_non_hebrew_chars": 0,
            "invisible_chars": 0,
            "double_spaces_in_value": 0,
            "unbalanced_markup": 0,
        }
        for r in recs:
            norm_index[name][r["normalized_key"]].append(r)
            if not r["raw_value"].strip():
                s["empty_values"] += 1
                anomalies.append(["empty_value", name, r["record_id"], r["key"], r["raw_value"]])
            if any(x["expression"] for x in r["senses"]):
                s["with_curly_expression"] += 1
            if any(x["expansion"] for x in r["senses"]):
                s["with_expansion"] += 1
            if not HEBREW_LETTER_RE.search(r["key"]):
                s["keys_non_hebrew_chars"] += 1
                anomalies.append(["key_without_hebrew_letters", name, r["record_id"], r["key"], r["raw_value"]])
            if INVISIBLE_RE.search(r["key"] + r["raw_value"]):
                s["invisible_chars"] += 1
                anomalies.append(["invisible_chars", name, r["record_id"], r["key"], r["raw_value"]])
            if "  " in r["raw_value"]:
                s["double_spaces_in_value"] += 1
            v = r["raw_value"]
            if v.count("{") != v.count("}") or v.count("(") != v.count(")"):
                s["unbalanced_markup"] += 1
                anomalies.append(["unbalanced_markup", name, r["record_id"], r["key"], v])
            if v.count("***") and any(not p.strip() for p in v.split("***")):
                anomalies.append(["empty_sense_segment", name, r["record_id"], r["key"], v])
        stats["dictionaries"][name] = s

    # כפילויות בתוך מילון
    for name, idx in norm_index.items():
        dup_keys = [k for k, v in idx.items() if len(v) > 1]
        stats["dictionaries"][name]["duplicate_normalized_keys_within"] = len(dup_keys)
        for k in sorted(dup_keys):
            recs = idx[k]
            duplicates.append(
                [
                    "within_dictionary",
                    name,
                    k,
                    " | ".join(r["record_id"] for r in recs),
                    " | ".join(r["key"] for r in recs),
                    " | ".join(r["raw_value"] for r in recs),
                ]
            )
    # כפילויות בין מילונים
    names = list(norm_index)
    cross: dict[str, int] = {}
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            shared = sorted(set(norm_index[a]) & set(norm_index[b]))
            cross[f"{a} ∩ {b}"] = len(shared)
            for k in shared:
                duplicates.append(
                    [
                        "across_dictionaries",
                        f"{a} / {b}",
                        k,
                        " | ".join(r["record_id"] for r in norm_index[a][k] + norm_index[b][k]),
                        " | ".join(r["key"] for r in norm_index[a][k] + norm_index[b][k]),
                        " | ".join(r["raw_value"] for r in norm_index[a][k] + norm_index[b][k]),
                    ]
                )
    stats["cross_dictionary_overlap"] = cross
    stats["marker_usage"] = Counter(
        marker
        for rec in records
        for marker in ("***", "{", "(=", "(")
        if marker in rec["raw_value"]
    )
    return stats, duplicates, anomalies


def git_info(root: Path) -> dict:
    def run(*args: str) -> str:
        try:
            return subprocess.run(
                ["git", *args], cwd=root, capture_output=True, text=True, encoding="utf-8", check=True
            ).stdout.strip()
        except Exception as exc:  # noqa: BLE001 - דיווח בלבד
            return f"<unavailable: {exc}>"

    return {
        "branch": run("rev-parse", "--abbrev-ref", "HEAD"),
        "commit": run("rev-parse", "HEAD"),
        "commit_subject": run("log", "-1", "--format=%s"),
        "asset_last_commit": run("log", "-1", "--format=%h %ci %an %s", "--", "assets/dictionary.json"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--refresh-backup", action="store_true", help="דריסת הגיבוי הקיים (ברירת מחדל: לא נוגעים בגיבוי)")
    args = parser.parse_args()

    cfg = load_config()
    root = repo_root(cfg)
    asset = root / cfg["dictionary_asset"]
    backup = work_dir(cfg, "baseline", "dictionary.original.json")
    if args.refresh_backup or not backup.exists():
        # הגיבוי נלקח מהתוכן המקומט (blob) ולא מעותק העבודה, כדי שלא יושפע מהמרת סוף-שורה
        blob = subprocess.run(["git", "show", f"HEAD:{cfg['dictionary_asset']}"], cwd=root, capture_output=True)
        if blob.returncode == 0 and blob.stdout:
            backup.write_bytes(blob.stdout)
        else:
            shutil.copyfile(asset, backup)
    original = json.loads(backup.read_text(encoding="utf-8"))

    records = build_records(original)
    write_jsonl(work_dir(cfg, "baseline", "existing_records.jsonl"), records)

    snapshot = {
        rec["record_id"]: {
            "dictionary": rec["dictionary"],
            "key": rec["key"],
            "senses": [s["raw"] for s in rec["senses"]],
        }
        for rec in records
    }
    write_json(work_dir(cfg, "baseline", "regression_snapshot.json"), snapshot, indent=None)

    stats, duplicates, anomalies = analyze(records)
    stats["source_file"] = {"path": cfg["dictionary_asset"], "sha256": sha256_file(backup), "bytes": backup.stat().st_size}
    stats["git"] = git_info(root)
    write_json(work_dir(cfg, "reports", "baseline_stats.json"), stats)
    for filename, rows in (("baseline_duplicates.csv", duplicates), ("baseline_anomalies.csv", anomalies)):
        with open(work_dir(cfg, "reports", filename), "w", encoding="utf-8-sig", newline="") as fh:
            csv.writer(fh).writerows(rows)
    print(json.dumps(stats, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
