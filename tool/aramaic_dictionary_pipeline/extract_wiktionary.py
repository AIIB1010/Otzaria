"""שלב 3א: חילוץ ערכים ארמיים מוויקימילון העברי דרך MediaWiki API.

הקטגוריה "ערכים בשפה הארמית" נוצרת אוטומטית מהתבנית {{ארמית}} שמסמנת *הגדרה* בודדת
בתוך דף, ולכן דף בקטגוריה עשוי להיות ערך עברי עם הגדרה ארמית אחת בלבד. החילוץ מפרק
כל דף לכותרות-משנה (כותרת רמה 2 = לֶמה מנוקדת) ולהגדרות מסומנות {{ארמית}}.

נשמרים: מזהה דף, מזהה גרסה (revid), חותמת זמן של הגרסה, קישור קבוע לגרסה, ומועד החילוץ
(בקובץ meta נפרד, כדי שפלט הערכים יישאר דטרמיניסטי).

רישיון התוכן: Creative Commons Attribution-ShareAlike 4.0 (ראו README).

פלט (work/extract/): wiktionary_pages.jsonl, wiktionary_entries.jsonl, wiktionary_meta.json
"""

from __future__ import annotations

import argparse
import json
import re
import ssl
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any

from common import clean_text, load_config, normalize_key, stable_id, work_dir, write_json, write_jsonl

USER_AGENT = "OtzariaAramaicDictPipeline/0.1 (https://github.com/Otzaria/otzaria)"


def _ssl_context(relaxed: bool) -> ssl.Context:
    ctx = ssl.create_default_context()
    if relaxed:
        # מסנני רשת (NetFree) מחתימים תעודות ללא Authority Key Identifier; Python 3.13+ דוחה
        # אותן במצב strict. מכבים רק את דגל ה-strict, האימות עצמו נשאר.
        ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
    return ctx


class Api:
    def __init__(self, endpoint: str) -> None:
        self.endpoint = endpoint
        self._relaxed = False

    def get(self, **params: Any) -> dict[str, Any]:
        params.update(format="json", formatversion="2")
        url = f"{self.endpoint}?{urllib.parse.urlencode(params)}"
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=60, context=_ssl_context(self._relaxed)) as resp:
                    return json.load(resp)
            except ssl.SSLError:
                if self._relaxed:
                    raise
                self._relaxed = True
            except OSError as exc:  # noqa: PERF203 - ניסיון חוזר פשוט
                if getattr(exc, "reason", None) and isinstance(exc.reason, ssl.SSLError) and not self._relaxed:  # type: ignore[attr-defined]
                    self._relaxed = True
                    continue
                if attempt == 3:
                    raise
                time.sleep(2 * (attempt + 1))
        raise RuntimeError("unreachable")


# ───────────────────────── שליפה ─────────────────────────


def list_category(api: Api, category: str) -> list[dict[str, Any]]:
    members: list[dict[str, Any]] = []
    cont: dict[str, Any] = {}
    while True:
        data = api.get(action="query", list="categorymembers", cmtitle=category, cmlimit=500, cmprop="ids|title|type|timestamp", **cont)
        members.extend(data["query"]["categorymembers"])
        if "continue" not in data:
            return members
        cont = data["continue"]


def fetch_pages(api: Api, titles: list[str]) -> list[dict[str, Any]]:
    pages: list[dict[str, Any]] = []
    for start in range(0, len(titles), 40):
        chunk = titles[start : start + 40]
        data = api.get(
            action="query",
            prop="revisions|categories",
            titles="|".join(chunk),
            rvprop="ids|timestamp|content|user|comment",
            rvslots="main",
            cllimit="max",
        )
        pages.extend(data["query"]["pages"])
    return pages


# ───────────────────────── פענוח wikitext ─────────────────────────

_HEADING2_RE = re.compile(r"^==([^=].*?)==\s*$", re.M)
_REF_RE = re.compile(r"<ref[^>]*?/>|<ref[^>]*?>.*?</ref>", re.S)
_TAG_RE = re.compile(r"</?(?:small|sup|sub|span|br|nowiki|u|i|b)[^>]*>", re.I)
_LINK_RE = re.compile(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]")
_TEMPLATE_RE = re.compile(r"\{\{[^{}]*\}\}")
_ARAMAIC_TAG = "{{ארמית}}"


def strip_markup(text: str) -> str:
    """wikitext → טקסט רגיל: קישורים לתצוגתם, הסרת תבניות/הערות/עיצוב."""
    text = _REF_RE.sub("", text)
    text = _LINK_RE.sub(r"\1", text)
    for _ in range(4):  # תבניות מקוננות
        text = _TEMPLATE_RE.sub("", text)
    text = _TAG_RE.sub("", text)
    text = text.replace("'''", "").replace("''", "")
    return clean_text(text)


def parse_sections(wikitext: str) -> list[dict[str, Any]]:
    """רשימת סעיפי רמה 2: כותרת (מילה מנוקדת) וגוף."""
    matches = list(_HEADING2_RE.finditer(wikitext))
    sections = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(wikitext)
        sections.append({"heading": match.group(1).strip(), "body": wikitext[match.end() : end]})
    return sections


def parse_definitions(body: str) -> list[dict[str, Any]]:
    """הגדרות מסעיף: שורות '#' ראשיות עם הדוגמאות (#:) שצמודות אליהן."""
    definitions: list[dict[str, Any]] = []
    for line in body.splitlines():
        if re.match(r"^#(?![:*#])", line):
            definitions.append({"raw": line[1:].strip(), "examples": []})
        elif re.match(r"^#[:*]", line) and definitions:
            definitions[-1]["examples"].append(strip_markup(re.sub(r"^#[:*]+", "", line)))
        elif re.match(r"^##", line) and definitions:
            definitions[-1].setdefault("subdefinitions", []).append(strip_markup(line.lstrip("#").strip()))
    return definitions


_ALT_PAREN_RE = re.compile(r"\s*\((?:וגם|גם|או)[:\s]+([^)]+)\)")
_FULL_SPELLING_RE = re.compile(r"\|\s*כתיב מלא\s*=\s*([^\n|}]*)")


def split_lemma(heading: str) -> tuple[str, list[str]]:
    """כותרת ערך → (למה ראשית, כתיבים חלופיים). "חַבְרוּתָא (וגם: חַבְרוּתָה)" ו"נַרְדְּשִׁיר או נַדְרְשִׁיר"."""
    variants = [m.strip() for m in _ALT_PAREN_RE.findall(heading)]
    primary = _ALT_PAREN_RE.sub("", heading).strip()
    if " או " in primary:
        first, *rest = [part.strip() for part in primary.split(" או ")]
        primary, variants = first, variants + rest
    return primary, [v for v in variants if v]


def parse_page(page: dict[str, Any], cfg: dict[str, Any]) -> list[dict[str, Any]]:
    title = page["title"]
    rev = page["revisions"][0]
    wikitext = rev["slots"]["main"]["content"]
    api_cfg = cfg["sources"]["wiktionary"]
    base = {
        "source": "wiktionary",
        "page_title": title,
        "page_id": page["pageid"],
        "revision_id": rev["revid"],
        "revision_timestamp": rev["timestamp"],
        "revision_user": rev.get("user", ""),
        "page_url": f"https://he.wiktionary.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}",
        "permalink": f"https://he.wiktionary.org/w/index.php?title={urllib.parse.quote(title.replace(' ', '_'))}&oldid={rev['revid']}",
        "history_url": f"https://he.wiktionary.org/w/index.php?title={urllib.parse.quote(title.replace(' ', '_'))}&action=history",
        "license": "CC BY-SA 4.0",
    }
    del api_cfg
    records: list[dict[str, Any]] = []
    for section_index, section in enumerate(parse_sections(wikitext)):
        heading_full = strip_markup(section["heading"])
        heading, alt_forms = split_lemma(heading_full)
        full_spelling = [
            strip_markup(part)
            for m in _FULL_SPELLING_RE.findall(section["body"])
            for part in m.split(",")
            if strip_markup(part) and len(normalize_key(heading)) > 1  # שם האות ("דלת" ל-"ד") אינו כתיב מלא
        ]
        homograph = re.search(r"\{\{משני\|([^}]*)\}\}", section["heading"])
        for def_index, definition in enumerate(parse_definitions(section["body"])):
            raw = definition["raw"]
            if _ARAMAIC_TAG not in raw:
                continue
            gloss = strip_markup(raw)
            record = {
                **base,
                "record_id": f"wikt-{page['pageid']}-s{section_index + 1}-d{def_index + 1}",
                "lemma": heading,
                "lemma_normalized": normalize_key(heading),
                "lemma_heading_full": heading_full,
                "key_variants": sorted(
                    {v for v in alt_forms + full_spelling if normalize_key(v) and normalize_key(v) != normalize_key(heading)}
                ),
                "homograph": homograph.group(1) if homograph else "",
                "gloss_raw": raw,
                "gloss_clean": gloss,
                "examples": definition["examples"][:3],
                "layer_hint": re.search(r"\{\{רובד\|([^}]*)\}\}", raw).group(1) if re.search(r"\{\{רובד\|([^}]*)\}\}", raw) else "",
                "other_headings": [strip_markup(s["heading"]) for s in parse_sections(wikitext)][:8],
                "review_status": "needs_human_review",
                "notes": "",
            }
            records.append(record)
    if not records:
        records.append(
            {
                **base,
                "record_id": f"wikt-{page['pageid']}-none",
                "lemma": title,
                "lemma_normalized": normalize_key(title),
                "lemma_heading_full": title,
                "key_variants": [],
                "homograph": "",
                "gloss_raw": "",
                "gloss_clean": "",
                "examples": [],
                "layer_hint": "",
                "other_headings": [],
                "review_status": "needs_human_review",
                "notes": "no_aramaic_tagged_definition",
            }
        )
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()
    cfg = load_config()
    wcfg = cfg["sources"]["wiktionary"]
    api = Api(wcfg["api"])
    members = [m for m in list_category(api, wcfg["category"]) if m.get("type") == "page" and m.get("ns") == 0]
    members.sort(key=lambda m: m["pageid"])
    pages = fetch_pages(api, [m["title"] for m in members])
    pages.sort(key=lambda p: p["pageid"])
    entries: list[dict[str, Any]] = []
    raw_pages: list[dict[str, Any]] = []
    for page in pages:
        if "revisions" not in page:
            continue
        rev = page["revisions"][0]
        raw_pages.append(
            {
                "page_id": page["pageid"],
                "title": page["title"],
                "revision_id": rev["revid"],
                "revision_timestamp": rev["timestamp"],
                "categories": [c["title"] for c in page.get("categories", [])],
                "wikitext": rev["slots"]["main"]["content"],
                "wikitext_id": stable_id(rev["slots"]["main"]["content"]),
            }
        )
        entries.extend(parse_page(page, cfg))
    write_jsonl(work_dir(cfg, "extract", "wiktionary_pages.jsonl"), raw_pages)
    write_jsonl(work_dir(cfg, "extract", "wiktionary_entries.jsonl"), entries)
    write_json(
        work_dir(cfg, "extract", "wiktionary_meta.json"),
        {
            "retrieved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "api": wcfg["api"],
            "category": wcfg["category"],
            "category_members": len(members),
            "pages_fetched": len(raw_pages),
            "entries": len(entries),
            "pages_without_aramaic_definition": sum(1 for e in entries if e["notes"] == "no_aramaic_tagged_definition"),
            "license": "Creative Commons Attribution-ShareAlike 4.0 — https://creativecommons.org/licenses/by-sa/4.0/",
        },
    )
    print(f"wiktionary: {len(members)} category members, {len(raw_pages)} pages, {len(entries)} candidate senses")


if __name__ == "__main__":
    main()
