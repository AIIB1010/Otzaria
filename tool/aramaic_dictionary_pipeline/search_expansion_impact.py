"""השפעת המילון החדש על הרחבת "תרגום ארמי" במנוע החיפוש (Rust: rust/src/lexicons.rs, otzaria_search_engine).

המנוע ממזג את *כל* המילונים שבקובץ, מפרק כל פירוש למילים בודדות (לפי `***`, פסיק, נקודה,
נקודה-פסיק, נקודתיים; בלי `{...}` ובלי `(...)`) ושומר רק פריטים של מילה אחת. לכל מילה עד 16
הרחבות בשני הכיוונים; סדר הקובץ מכריע מי נכנס כשיש יותר מ-16 (מפה "ראשונים מנצחים").
הסקריפט מעתיק את ההיגיון הזה לפייתון (בלי להריץ את המנוע) ומשווה בין המקור למילון החדש.

  py search_expansion_impact.py [קובץ-חדש]  # ברירת מחדל: work/export/merged.dictionary.json
פלט: work/reports/search_expansion_impact.json + CSV של מילים שהרחבותיהן השתנו.
"""

from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

from common import load_config, normalize_key, work_dir

MAX_EXPANSIONS = 16
_PAREN_BLOCKS = re.compile(r"\{[^{}]*\}|\([^()]*\)")


def gloss_words(gloss: str) -> list[str]:
    cleaned = _PAREN_BLOCKS.sub("", gloss)
    out: list[str] = []
    for meaning in cleaned.split("***"):
        for piece in re.split(r"[,;.:]", meaning):
            word = piece.strip()
            if not word or len(word.split()) != 1:
                continue
            norm = normalize_key(word).replace("'", "").replace('"', "")
            if norm and norm not in out:
                out.append(norm)
    return out


def build(data: dict) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    forward: dict[str, list[str]] = {}
    reverse: dict[str, list[str]] = {}

    def push(m: dict[str, list[str]], k: str, v: str) -> None:
        if k == v:
            return
        lst = m.setdefault(k, [])
        if len(lst) < MAX_EXPANSIONS and v not in lst:
            lst.append(v)

    # serde_json ממיין את שמות המילונים העליונים אלפביתית (אין preserve_order) — כמו במנוע
    for name in sorted(data):
        for entry in data[name]:
            for head, gloss in entry.items():
                h = normalize_key(head).replace("'", "").replace('"', "")
                if not h:
                    continue
                for w in gloss_words(gloss):
                    push(forward, h, w)
                    push(reverse, w, h)
    return forward, reverse


def expansions(forward: dict, reverse: dict, token: str) -> list[str]:
    out: list[str] = []
    for lst in (forward.get(token), reverse.get(token)):
        for w in lst or []:
            if w != token and w not in out:
                out.append(w)
                if len(out) >= MAX_EXPANSIONS:
                    return out
    return out


def main() -> None:
    cfg = load_config()
    new_path = Path(sys.argv[1]) if len(sys.argv) > 1 else work_dir(cfg, "export", "merged.dictionary.json")
    old = json.loads(work_dir(cfg, "baseline", "dictionary.original.json").read_text(encoding="utf-8"))
    new = json.loads(new_path.read_text(encoding="utf-8"))
    of, orv = build(old)
    nf, nrv = build(new)
    tokens = set(of) | set(orv) | set(nf) | set(nrv)
    gained, lost, reshuffled, unchanged, capped_new = [], [], [], 0, 0
    for t in sorted(tokens):
        a, b = expansions(of, orv, t), expansions(nf, nrv, t)
        if a == b:
            unchanged += 1
        elif not a:
            gained.append((t, b))
        elif set(a) <= set(b):
            reshuffled.append((t, a, b)) if len(b) >= MAX_EXPANSIONS and a != b[: len(a)] else gained.append((t, b))
        else:
            lost.append((t, [x for x in a if x not in b], a, b))
        capped_new += len(b) >= MAX_EXPANSIONS
    summary = {
        "tokens_total": len(tokens),
        "tokens_unchanged": unchanged,
        "tokens_gaining_expansions": len(gained),
        "tokens_losing_some_original_expansion": len(lost),
        "tokens_reordered_by_cap": len(reshuffled),
        "tokens_at_cap_16_after": capped_new,
        "note": "אובדן הרחבה קיים אפשרי מסיבות: (1) תקרת 16 (ראשונים מנצחים בסדר הקובץ); (2) שינוי מאושר של פירוש קיים ממילה בודדת לצירוף (המנוע מדלג על פירושים של כמה מילים). הרשימה המלאה ב-search_expansion_lost.csv",
    }
    out_json = work_dir(cfg, "reports", "search_expansion_impact.json")
    out_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    with open(work_dir(cfg, "reports", "search_expansion_lost.csv"), "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["token", "lost_expansions", "before", "after"])
        for t, l, a, b in lost:
            w.writerow([t, " ".join(l), " ".join(a), " ".join(b)])
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
