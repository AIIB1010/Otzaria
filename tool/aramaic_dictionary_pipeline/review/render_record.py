"""מרנדר לקובץ PNG את אזור הערך בעמוד ה-PDF המקורי (לבדיקה ויזואלית של חילוץ).

  py review/render_record.py <record_id> [<out.png>]
  py review/render_record.py siftey_gitin-p013-R14

record_id מופיע בשדה occurrences של פריטי התור. ברירת מחדל לפלט: work/review/page_cache/<record_id>.png
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pymupdf  # noqa: E402

from common import load_config, read_jsonl, work_dir  # noqa: E402


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    record_id = sys.argv[1]
    cfg = load_config()
    source = record_id.rsplit("-p", 1)[0]
    rows = {r["record_id"]: r for r in read_jsonl(work_dir(cfg, "extract", f"{source}_entries.jsonl"))}
    rec = rows[record_id]
    doc = pymupdf.open(cfg["sources"][source]["pdf"])
    page = doc[rec["pdf_page"] - 1]
    x0, y0, x1, y1 = rec["bbox"]
    page.draw_rect(pymupdf.Rect(x0 - 2, y0 - 2, x1 + 2, y1 + 2), color=(1, 0, 0), width=1.2)
    clip = pymupdf.Rect(max(0, x0 - 140), max(0, y0 - 60), min(page.rect.x1, x1 + 140), min(page.rect.y1, y1 + 60))
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else work_dir(cfg, "review", "page_cache", f"{record_id}.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    page.get_pixmap(dpi=150, clip=clip).save(out)
    print(out)


if __name__ == "__main__":
    main()
