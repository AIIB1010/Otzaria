"""כלי בקרה ידנית מקומי: שרת HTTP על 127.0.0.1 + ממשק HTML (index.html).

הרצה:  py review/server.py            (ואז לפתוח http://127.0.0.1:8765)

* תור הבקרה נקרא מ-work/merge/queue.jsonl; הצעות הסוכן מ-work/review/agent_suggestions.jsonl.
* החלטות נכתבות בהוספה בלבד (append-only, fsync) ל-work/review/decisions.jsonl — שמירת התקדמות
  וחידוש עבודה בלי אובדן. "חזרה להחלטה קודמת" = רשומת revert (ההיסטוריה נשמרת).
* תצוגת העמוד המקורי ב-PDF עם הדגשת האזור: /api/page/<source>/<page>.png?bbox=x0,y0,x1,y1
* אין תלות בקוד אוטריה, ואין גישה חיצונית: השרת מאזין ללולאה המקומית בלבד.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from common import load_config, read_jsonl, work_dir  # noqa: E402
from merge import load_decisions, proposal_sha  # noqa: E402

HERE = Path(__file__).resolve().parent
LOCK = threading.Lock()


class State:
    def __init__(self) -> None:
        self.cfg = load_config()
        self.queue_path = work_dir(self.cfg, "merge", "queue.jsonl")
        self.decisions_path = work_dir(self.cfg, "review", "decisions.jsonl")
        self.agent_path = work_dir(self.cfg, "review", "agent_suggestions.jsonl")
        self.cache_dir = work_dir(self.cfg, "review", "page_cache", "x").parent
        self.queue = read_jsonl(self.queue_path)
        self.by_id = {item["item_id"]: item for item in self.queue}
        self._records: dict[str, dict[str, Any]] | None = None

    def record(self, record_id: str) -> dict[str, Any] | None:
        """רשומת חילוץ של PDF לפי מזהה (נטענת בעצלתיים), לקישור לעמוד המקורי."""
        if self._records is None:
            self._records = {}
            for source in ("siftey_gitin", "siftey_brachot"):
                path = work_dir(self.cfg, "extract", f"{source}_entries.jsonl")
                if path.exists():
                    self._records.update({row["record_id"]: row for row in read_jsonl(path)})
        return self._records.get(record_id)

    def decisions(self) -> dict[str, dict[str, Any]]:
        return load_decisions(self.decisions_path)

    def agent(self) -> dict[str, dict[str, Any]]:
        return load_decisions(self.agent_path) if self.agent_path.exists() else {}

    def mods(self) -> list[dict[str, Any]]:
        """החלטות שכוללות שינוי של פירוש קיים ועדיין אין להן אישור/דחייה מפורשים של השינוי."""
        out: list[dict[str, Any]] = []
        for item_id, decision in self.decisions().items():
            item = self.by_id.get(item_id)
            if not item or decision["action"] in ("reject", "defer") or "confirm_modify_existing" in decision:
                continue
            source = decision if decision["action"] == "custom" else item["system_proposal"]
            for mod in source.get("modify_existing", []):
                existing = next((s["raw"] for s in item["existing_senses"] if s["sense_id"] == mod["sense_id"]), mod.get("old_text"))
                out.append({"item_id": item_id, "key": item["display_key"], "existing": existing, "old_text": mod["old_text"], "new_text": mod["new_text"]})
        out.sort(key=lambda m: m["key"])
        return out

    def summary(self, item: dict[str, Any], decisions: dict, agent: dict) -> dict[str, Any]:
        proposal = item["system_proposal"]
        group_glosses = [[c["gloss"] for c in g] for g in item["groups"]]
        sources = sorted({s for g in item["groups"] for c in g for s in c["sources"]})
        return {
            "item_id": item["item_id"],
            "kind": item["kind"],
            "key": item["display_key"],
            "classes": proposal["classes"],
            "confidence": proposal["confidence"],
            "modifies_existing": bool(proposal["modify_existing"]),
            "existing_count": len(item["existing_senses"]),
            "claims": group_glosses,
            "sources": sources,
            "issues": item["issues"],
            "status": "decided" if decisions.get(item["item_id"], {}).get("action") not in (None, "defer", "skip") else ("agent" if item["item_id"] in agent else "pending"),
            "decision_action": decisions.get(item["item_id"], {}).get("action"),
            "agent_action": agent.get(item["item_id"], {}).get("action"),
            "agent_confidence": agent.get(item["item_id"], {}).get("confidence"),
            "agent_needs_human": agent.get(item["item_id"], {}).get("needs_human"),
        }


STATE: State | None = None


def validate_decision(item: dict[str, Any], body: dict[str, Any]) -> None:
    """דוחה החלטה שמייצרת מידע לא קוהרנטי (מונע קריסת merge.py): מזהים חייבים להיות של הפריט עצמו."""
    claim_ids = {c["claim_id"] for g in item["groups"] for c in g}
    sense_ids = {s["sense_id"] for s in item["existing_senses"]}
    if "confirm_modify_existing" in body and not isinstance(body["confirm_modify_existing"], bool):
        raise ValueError("confirm_modify_existing must be boolean")
    if body["action"] != "custom":
        return

    def claims_ok(row: Any) -> bool:
        ids = row.get("claim_ids") if isinstance(row, dict) else None
        return isinstance(ids, list) and bool(ids) and all(i in claim_ids for i in ids)

    adds, support, mods = body.get("add_senses", []), body.get("support", []), body.get("modify_existing", [])
    if not all(isinstance(x, list) for x in (adds, support, mods)):
        raise ValueError("add_senses/support/modify_existing must be lists")
    for add in adds:
        if not (isinstance(add, dict) and isinstance(add.get("text"), str) and add["text"].strip() and claims_ok(add)):
            raise ValueError("bad add_senses row")
    for sup in support:
        if not (claims_ok(sup) and sup.get("target_sense_id") in sense_ids):
            raise ValueError("bad support row")
    for mod in mods:
        if not (isinstance(mod, dict) and mod.get("sense_id") in sense_ids and isinstance(mod.get("old_text"), str) and isinstance(mod.get("new_text"), str) and mod["new_text"].strip()):
            raise ValueError("bad modify_existing row")
        if mod.get("claim_ids") and not claims_ok(mod):
            raise ValueError("bad modify_existing claim_ids")


def render_page(source: str, page: int, bbox: list[float] | None) -> bytes:
    import pymupdf

    cfg = STATE.cfg  # type: ignore[union-attr]
    pdf = Path(cfg["sources"][source]["pdf"])
    cache = STATE.cache_dir / f"{source}_{page}_{'-'.join(f'{v:.0f}' for v in bbox) if bbox else 'full'}.png"  # type: ignore[union-attr]
    if cache.exists():
        return cache.read_bytes()
    doc = pymupdf.open(pdf)
    try:
        return _render_page(doc, page, bbox, cache)
    finally:
        doc.close()


def _render_page(doc, page: int, bbox: list[float] | None, cache: Path) -> bytes:
    import pymupdf

    pg = doc[page - 1]
    if bbox:
        x0, y0, x1, y1 = bbox
        pg.draw_rect(pymupdf.Rect(x0 - 2, y0 - 2, x1 + 2, y1 + 2), color=(1, 0, 0), width=1.2)
        clip = pymupdf.Rect(max(0, x0 - 140), max(0, y0 - 60), min(pg.rect.x1, x1 + 140), min(pg.rect.y1, y1 + 60))
        pix = pg.get_pixmap(dpi=150, clip=clip)
    else:
        pix = pg.get_pixmap(dpi=100)
    data = pix.tobytes("png")
    tmp = cache.with_suffix(".tmp")
    tmp.write_bytes(data)
    tmp.replace(cache)  # כתיבה אטומית: אין PNG חלקי במטמון
    return data


class Handler(BaseHTTPRequestHandler):
    server_version = "AramaicReview/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:  # שקט
        return

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data: Any, status: int = 200) -> None:
        self._send(status, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _local_only(self) -> bool:
        """הגנה מפני דפי אינטרנט זדוניים (CSRF) ו-DNS rebinding: Host ו-Origin חייבים להיות הלולאה המקומית של השרת הזה."""
        port = self.server.server_address[1]
        allowed = {f"127.0.0.1:{port}", f"localhost:{port}"}
        if self.headers.get("Host", "") not in allowed:
            return False
        origin = self.headers.get("Origin")
        return origin is None or origin in {f"http://{h}" for h in allowed}

    def do_GET(self) -> None:  # noqa: N802
        assert STATE is not None
        if not self._local_only():
            self._json({"error": "forbidden"}, 403)
            return
        url = urlparse(self.path)
        path = url.path
        if path in ("/", "/simple"):
            self._send(200, (HERE / "simple.html").read_bytes(), "text/html; charset=utf-8")
        elif path in ("/advanced", "/index.html"):
            self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        elif path == "/mods":
            self._send(200, (HERE / "mods.html").read_bytes(), "text/html; charset=utf-8")
        elif path == "/api/mods":
            self._json(STATE.mods())
        elif path == "/api/queue":
            decisions, agent = STATE.decisions(), STATE.agent()
            self._json([STATE.summary(item, decisions, agent) for item in STATE.queue])
        elif path.startswith("/api/item/"):
            item_id = path.rsplit("/", 1)[-1]
            item = STATE.by_id.get(item_id)
            if not item:
                self._json({"error": "not found"}, 404)
                return
            self._json({"item": item, "decision": STATE.decisions().get(item_id), "agent": STATE.agent().get(item_id)})
        elif path.startswith("/api/rec/"):
            try:
                rec = STATE.record(path.rsplit("/", 1)[-1].removesuffix(".png"))
                if rec is None:
                    raise KeyError("record not found")
                self._send(200, render_page(rec["source"], rec["pdf_page"], rec["bbox"]), "image/png")
            except Exception as exc:  # noqa: BLE001
                self._json({"error": type(exc).__name__}, 500)
        elif path.startswith("/api/page/"):
            try:
                _, _, _, source, name = path.split("/")
                page = int(name.removesuffix(".png"))
                bbox = [float(v) for v in parse_qs(url.query).get("bbox", [""])[0].split(",")] if "bbox" in parse_qs(url.query) else None
                self._send(200, render_page(source, page, bbox), "image/png")
            except Exception as exc:  # noqa: BLE001
                self._json({"error": type(exc).__name__}, 500)
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        assert STATE is not None
        if not self._local_only():
            self._json({"error": "forbidden"}, 403)
            return
        if self.path != "/api/decision":
            self._json({"error": "not found"}, 404)
            return
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            self._json({"error": "Content-Type must be application/json"}, HTTPStatus.UNSUPPORTED_MEDIA_TYPE)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 1_000_000:
                raise ValueError("bad Content-Length")
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(body, dict) or body.get("item_id") not in STATE.by_id:
                raise ValueError("unknown item_id")
            if body.get("action") not in ("accept_proposal", "custom", "reject", "defer", "revert"):
                raise ValueError("bad action")
            validate_decision(STATE.by_id[body["item_id"]], body)
        except Exception as exc:  # noqa: BLE001
            self._json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
            return
        if body["action"] == "accept_proposal":
            body["proposal_sha"] = proposal_sha(STATE.by_id[body["item_id"]]["system_proposal"])
        record = {**body, "reviewer": body.get("reviewer", "human"), "ts": datetime.now(timezone.utc).isoformat(timespec="seconds")}
        with LOCK, open(STATE.decisions_path, "a+b") as fh:
            fh.seek(0)
            valid_end = 0
            for line in fh:
                try:
                    if line.strip():
                        json.loads(line)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    if fh.read().strip():
                        raise
                    # רק סיומת פגומה מותר להסיר; כל ההחלטות השלמות נשמרות.
                    fh.truncate(valid_end)
                    break
                valid_end += len(line)
            fh.seek(0, os.SEEK_END)
            if fh.tell():
                fh.seek(-1, os.SEEK_END)
                if fh.read(1) != b"\n":
                    fh.write(b"\n")
            fh.write((json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8"))
            fh.flush()
            os.fsync(fh.fileno())
        self._json({"ok": True})


def main() -> None:
    global STATE
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    STATE = State()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"http://127.0.0.1:{args.port}  ({len(STATE.queue)} פריטים בתור; החלטות: {STATE.decisions_path})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
