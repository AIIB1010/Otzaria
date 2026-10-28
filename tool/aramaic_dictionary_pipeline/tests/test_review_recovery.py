"""שמירת החלטות לאחר כתיבה שנקטעה, דרך נקודת הכניסה של שרת הבקרה."""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from common import read_jsonl
from export import build_target_list
from merge import build_model, load_decisions
from review import server


class ReviewRecoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "decisions.jsonl"
        self.claims = [
            {"claim_id": key, "display_key": key, "origin": "siftey", "sources": [], "attestations": 1, "occurrences": []}
            for key in ("א", "ב")
        ]
        self.queue = [
            {
                "item_id": key, "normalized_key": key, "groups": [[claim]], "existing_senses": [],
                "system_proposal": {
                    "classes": ["distinct_sense"], "add_senses": [{"text": "פירוש " + key, "claim_ids": [key]}],
                    "support": [], "modify_existing": [],
                },
            }
            for key, claim in zip(("א", "ב"), self.claims)
        ]
        state = SimpleNamespace(decisions_path=self.path, by_id={item["item_id"]: item for item in self.queue})
        self.state_patch = patch.object(server, "STATE", state)
        self.state_patch.start()
        self.addCleanup(self.state_patch.stop)

    def post(self, item_id: str, action: str = "accept_proposal") -> None:
        body = json.dumps({"item_id": item_id, "action": action}).encode("utf-8")
        handler = server.Handler.__new__(server.Handler)
        handler.path = "/api/decision"
        handler.headers = {"Content-Type": "application/json", "Content-Length": str(len(body))}
        handler.rfile = io.BytesIO(body)
        handler._local_only = Mock(return_value=True)
        handler._json = Mock()
        handler.do_POST()
        handler._json.assert_called_once_with({"ok": True})

    def test_recover_append_reload_merge_and_revert(self) -> None:
        original = (json.dumps({"item_id": "א", "action": "reject"}, ensure_ascii=False) + "\n").encode("utf-8")
        for tail in (
            b'{"item_id":"b","action":', b'{"item_id":"b","action":\n', b'{"item_id":"b","action":\n\n  ',
            b'{"item_id":"b","notes":"' + "א".encode("utf-8")[:1],
        ):
            with self.subTest(tail=tail):
                self.path.write_bytes(original + tail)
                self.assertEqual(list(load_decisions(self.path)), ["א"])
                self.assertEqual(self.path.read_bytes(), original + tail)
                self.post("ב")
                self.assertEqual(load_decisions(self.path)["ב"]["action"], "accept_proposal")
                self.post("א")
                self.assertTrue(self.path.read_bytes().startswith(original))
                self.assertEqual(len(read_jsonl(self.path)), 3)
                entries, _, pending = build_model([], self.claims, [], self.queue, load_decisions(self.path), {}, "מילון פשיטא", False)
                self.assertEqual(build_target_list(entries), [{"א": "פירוש א"}, {"ב": "פירוש ב"}])
                self.assertEqual(pending, [])
                self.post("א", "revert")
                self.assertEqual(load_decisions(self.path)["א"]["action"], "reject")

    def test_valid_last_record_without_newline_is_preserved(self) -> None:
        original = json.dumps({"item_id": "א", "action": "reject"}, ensure_ascii=False).encode("utf-8")
        self.path.write_bytes(original)
        self.post("ב")
        self.assertTrue(self.path.read_bytes().startswith(original + b"\n"))
        self.assertEqual(set(load_decisions(self.path)), {"א", "ב"})

    def test_internal_corruption_is_rejected_without_changing_log(self) -> None:
        original = b'{"item_id":"broken","action":\n{"item_id":"valid","action":"reject"}\n'
        self.path.write_bytes(original)
        with self.assertRaises(json.JSONDecodeError):
            self.post("ב")
        self.assertEqual(self.path.read_bytes(), original)

    def test_invalid_utf8_inside_log_is_not_ignored(self) -> None:
        original = b'{"item_id":"broken","notes":"' + "א".encode("utf-8")[:1] + b'\n{"item_id":"valid","action":"reject"}\n'
        self.path.write_bytes(original)
        with self.assertRaises(UnicodeDecodeError):
            load_decisions(self.path)
        with self.assertRaises(UnicodeDecodeError):
            self.post("ב")
        self.assertEqual(self.path.read_bytes(), original)

    def test_first_decision_creates_log(self) -> None:
        self.post("א")
        self.assertEqual(load_decisions(self.path)["א"]["action"], "accept_proposal")


if __name__ == "__main__":
    unittest.main()
