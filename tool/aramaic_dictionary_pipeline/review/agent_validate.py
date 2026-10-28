"""אימות הצעות סוכן (AI) לתור הבקרה, ומיזוגן ל-work/review/agent_suggestions.jsonl.

הצעת סוכן אינה החלטה: היא נשמרת בנפרד מהחלטות הבודק ואינה נכנסת לייצוא ללא אישור אנושי.
המאמת אוכף שהסוכן *אינו ממציא* תרגומים: כל מילה בטקסט משמעות מוצעת חייבת להופיע בטענה
כלשהי בפריט (או בפירוש קיים, בהרחבת פירוש קיים).

שימוש:
  py review/agent_validate.py check  <קובץ.jsonl> [<קובץ.jsonl> ...]   # בדיקה בלבד
  py review/agent_validate.py apply  <קובץ.jsonl> [...]               # בדיקה + הוספה לקובץ ההצעות
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from common import load_config, normalize_gloss, read_jsonl, strip_marks, work_dir, write_jsonl  # noqa: E402
from merge import load_decisions  # noqa: E402
from normalize import gloss_issues  # noqa: E402

ACTIONS = {"accept_proposal", "custom", "reject", "defer"}
CLASSES = {
    "exact_duplicate", "semantic_duplicate", "distinct_sense", "grammatical_variant",
    "orthographic_variant", "conflicting_sources", "uncertain", "rejected",
}
WORD_RE = re.compile(r"[א-ת]+(?:['\"״׳][א-ת]+)*")


def words(text: str) -> set[str]:
    return set(WORD_RE.findall(normalize_gloss(strip_marks(text))))


def check_record(rec: dict[str, Any], item: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if rec.get("action") not in ACTIONS:
        errors.append(f"action לא חוקי: {rec.get('action')}")
        return errors
    if not str(rec.get("reviewer", "")).startswith("agent"):
        errors.append("reviewer חייב להתחיל ב-agent")
    if rec.get("class") not in CLASSES:
        errors.append(f"class לא חוקי: {rec.get('class')}")
    conf = rec.get("confidence")
    if not isinstance(conf, (int, float)) or not 0 <= conf <= 1:
        errors.append("confidence חייב להיות מספר בין 0 ל-1")
    if len(str(rec.get("rationale", "")).strip()) < 8:
        errors.append("rationale חסר/קצר מדי")
    if not isinstance(rec.get("needs_human"), bool):
        errors.append("needs_human חייב להיות true/false")
    claim_ids = {c["claim_id"] for g in item["groups"] for c in g}
    claim_glosses = [c["gloss"] for g in item["groups"] for c in g]
    allowed = set().union(*(words(g) for g in claim_glosses)) if claim_glosses else set()
    existing = {s["sense_id"]: s for s in item["existing_senses"]}
    allowed_for_modify = allowed.union(*(words(s["text"]) for s in existing.values())) if existing else allowed
    if rec["action"] == "custom":
        for sense in rec.get("add_senses", []):
            text = sense.get("text", "")
            if not text.strip():
                errors.append("add_senses: טקסט ריק")
                continue
            bad = gloss_issues(text)
            if bad:
                errors.append(f"add_senses «{text}»: {bad}")
            invented = words(text) - allowed
            if invented:
                errors.append(f"add_senses «{text}»: מילים שאינן באף טענה בפריט (המצאה?): {sorted(invented)}")
            if not sense.get("claim_ids") or not set(sense["claim_ids"]) <= claim_ids:
                errors.append(f"add_senses «{text}»: claim_ids חסר/לא שייך לפריט")
        for sup in rec.get("support", []):
            if sup.get("target_sense_id") not in existing:
                errors.append(f"support: target_sense_id לא קיים: {sup.get('target_sense_id')}")
            if not set(sup.get("claim_ids", [])) <= claim_ids:
                errors.append("support: claim_ids לא שייך לפריט")
        for mod in rec.get("modify_existing", []):
            target = existing.get(mod.get("sense_id"))
            if target is None:
                errors.append(f"modify_existing: sense_id לא קיים: {mod.get('sense_id')}")
                continue
            if mod.get("old_text") != target["text"]:
                errors.append("modify_existing: old_text אינו זהה לפירוש הקיים")
            if words(mod.get("new_text", "")) - allowed_for_modify:
                errors.append(f"modify_existing: מילים חדשות שאינן בפריט: {sorted(words(mod.get('new_text', '')) - allowed_for_modify)}")
        if not (rec.get("add_senses") or rec.get("support") or rec.get("modify_existing")):
            errors.append("custom בלי add_senses/support/modify_existing — השתמשו ב-reject או defer")
    return errors


def main() -> None:
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "apply"):
        print(__doc__)
        sys.exit(2)
    mode, files = sys.argv[1], [Path(p) for p in sys.argv[2:]]
    cfg = load_config()
    queue = {item["item_id"]: item for item in read_jsonl(work_dir(cfg, "merge", "queue.jsonl"))}
    good: list[dict[str, Any]] = []
    bad = 0
    for path in files:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"{path.name}:{number}: JSON שבור: {exc}")
                bad += 1
                continue
            item = queue.get(rec.get("item_id"))
            if item is None:
                print(f"{path.name}:{number}: item_id לא קיים בתור: {rec.get('item_id')}")
                bad += 1
                continue
            errors = check_record(rec, item)
            if errors:
                bad += 1
                print(f"{path.name}:{number}: [{item['display_key']}] " + " | ".join(errors))
            else:
                good.append(rec)
    print(f"תקינים: {len(good)} | פסולים: {bad}")
    if mode == "apply" and good:
        out = work_dir(cfg, "review", "agent_suggestions.jsonl")
        existing = load_decisions(out) if out.exists() else {}
        for rec in good:
            existing[rec["item_id"]] = rec
        write_jsonl(out, [existing[k] for k in sorted(existing)])
        print(f"נכתבו {len(existing)} הצעות ל-{out}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
