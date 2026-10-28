"""מחלק את תור הבקרה (קיבוצי פירושים) לקבצי קלט קומפקטיים לסוכני AI מסייעים.

  py review/make_agent_chunks.py [--chunks 10]
פלט: work/review/agent_input/chunk_XX.jsonl  (ויקימילון לא נכלל: נסקר בנפרד, פריט-פריט)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from common import load_config, read_jsonl, work_dir, write_jsonl  # noqa: E402


def compact(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "item_id": item["item_id"],
        "key": item["display_key"],
        "existing": [{"sense_id": s["sense_id"], "raw": s["raw"], "text": s["text"]} for s in item["existing_senses"]],
        "evidence_other": [f"[{s['dictionary']}] {s['raw']}" for s in item["evidence_other_dictionaries"]],
        "groups": [
            [
                {
                    "claim_id": c["claim_id"],
                    "gloss": c["gloss"],
                    "sources": c["sources"],
                    "n": c["attestations"],
                    "conf": c["min_confidence"],
                    "issues": c["issues"],
                    "records": [o["record_id"] for o in c["occurrences"][:3]],
                }
                for c in g
            ]
            for g in item["groups"]
        ],
        "proposal": {
            "classes": item["system_proposal"]["classes"],
            "add": [s["text"] for s in item["system_proposal"]["add_senses"]],
            "support": [f"{s['relation']}→{s['target_sense_id']}" for s in item["system_proposal"]["support"]],
            "modify": [f"{m['old_text']} ⟶ {m['new_text']}" for m in item["system_proposal"]["modify_existing"]],
            "notes": item["system_proposal"]["notes"],
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--chunks", type=int, default=10)
    args = parser.parse_args()
    cfg = load_config()
    items = [i for i in read_jsonl(work_dir(cfg, "merge", "queue.jsonl")) if i["kind"] == "sense_cluster"]
    items.sort(key=lambda i: i["item_id"])
    size = -(-len(items) // args.chunks)
    for n in range(args.chunks):
        part = items[n * size : (n + 1) * size]
        path = work_dir(cfg, "review", "agent_input", f"chunk_{n + 1:02d}.jsonl")
        write_jsonl(path, (compact(i) for i in part))
        print(path, len(part))


if __name__ == "__main__":
    main()
