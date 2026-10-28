"""הצעות סוכן לפריטי ויקימילון — סקירה פריט-פריט (נעשתה ידנית על ידי הסוכן, מול טקסט הדף).

*אינן החלטות*: כל פריט ויקימילון חייב אישור אנושי מפורש (needs_human תמיד true).
הטבלה מפתחת לפי מזהה הרשומה בוויקימילון (wikt-<pageid>-s<סעיף>-d<הגדרה>). כתיבים חלופיים וכתיב
מלא (key_variants) יורשים את ההחלטה של הלמה הראשית, אלא אם צוין אחרת ב-VARIANT_OVERRIDES.

  py review/wikt_suggestions.py        # כותב work/review/wikt_agent_suggestions.jsonl
  py review/agent_validate.py apply work/review/wikt_agent_suggestions.jsonl
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from common import load_config, read_jsonl, work_dir, write_jsonl  # noqa: E402

# verdict: dup (תמיכה בפירוש קיים) | add (הוספת משמעות) | ext (הרחבת פירוש קיים) | defer | reject
V: dict[str, tuple[str, str | None, str]] = {
    "wikt-23150-s1-d1": ("defer", None, "«אסל» לבדה היא מילה עברית נדירה וחסרת הסבר; בדף עצמו הפירוש הוא «מוט כפוף לנשיאת משא על הכתף» (רש\"י). אי אפשר לנסח זאת בלי להמציא."),
    "wikt-23150-s2-d1": ("dup", None, "אותה משמעות כמו הפירוש הקיים «שכר»; «תשלום» מוסיף מילה נרדפת בלבד."),
    "wikt-23150-s3-d1": ("add", "גג", "אִגָּרָא = גג (מאיגרא רמא); משמעות נבדלת מ«שכר». הכתיב המלא «איגרא» מופיע בגמרא — נוסף כמפתח משלים."),
    "wikt-5731-s4-d1": ("defer", None, "אִדַּר = גורן (ארמית מקראית, דניאל ב). אך המפתח «אדר» הוא החודש העברי: חלון הקשר בכל «אדר» בטקסט יציג «גורן». מומלץ לשקול פסילה."),
    "wikt-58647-s1-d1": ("defer", None, "אחמתא: שני הפירושים בדף — כלי לשמירת מסמכים (שכבה ב') ושם העיר אחמתא (עזרא). לא אומת שהמשמעות הראשונה מתועדת בגמרא."),
    "wikt-53441-s1-d1": ("add", None, "אילא דספינתא (נדרים נ ע\"א): דמות איל בחרטום הספינה — תואם את רש\"י ור\"ן שבדף. ניסוח ארוך אך נאמן למקור."),
    "wikt-56475-s1-d1": ("add", None, "מונח ימי טכני (לשון חז\"ל); תואם את ההגדרה בדף. מומלץ לבדוק מול מקור נוסף."),
    "wikt-20369-s3-d1": ("reject", None, "אִמָּר = טלה/כבש (נכון לשונית), אך המפתח «אמר» הוא הפועל השכיח ביותר בגמרא: חלון הקשר ב«אמר» יציג «טלה». הכתיב «אימר» נוסף כמפתח נפרד."),
    "wikt-25254-s1-d1": ("dup", None, "זהה בפירוש לקיים «מרפא. רפואה»."),
    "wikt-63318-s1-d1": ("dup", None, "זהה לקיים «רופא»."),
    "wikt-58666-s1-d1": ("add", "צפון (אחד מרוחות השמים)", "אסתן = רוח צפונית (לשון חז\"ל); ההגדרה בדף תקינה. ניסוח מקוצר מהמקור."),
    "wikt-22603-s1-d1": ("dup", None, "זהה לקיים «ארמון»."),
    "wikt-22603-s1-d2": ("defer", None, "המשמעות «חומה» נסמכת על ברכות נו ע\"א, שם רש\"י מפרש «פלטרין» (ארמון). ספק אם המשמעות השנייה נכונה."),
    "wikt-22967-s1-d1": ("dup", None, "זהה לקיים «אלמנה»."),
    "wikt-57487-s2-d1": ("add", None, "אֲרַע = ארץ, אדמה (ארמית מקראית); מתאים לראיה ממילון אחר בקובץ ({אֲרַע} אֶרֶץ)."),
    "wikt-61300-s2-d1": ("dup", None, "זהה לקיים «נאמר»."),
    "wikt-22911-s1-d1": ("add", None, "אתערותא = התעוררות; שכבה: ימי הביניים (לא תלמודית) — לשקול התאמה להיקף המילון."),
    "wikt-11968-s5-d1": ("dup", None, "«בית» כבר בפירוש הקיים."),
    "wikt-24869-s1-d1": ("dup", None, "זהה לקיים «רע»."),
    "wikt-53185-s2-d1": ("add", None, "בָּעָה = שאל, ביקש (ארמית מקראית/תרגומית). הצורה הנפוצה בגמרא «בעי»/«בעא»."),
    "wikt-57809-s1-d1": ("add", "גר (לא יהודי שבא לחיק היהדות)", "גיורא = גר; נאמן להגדרה בדף; ניסוח מקוצר."),
    "wikt-17748-s3-d1": ("defer", None, "גרב: «שדד, החרים, החזיק בכח» — רשימה רחבה לשלוש משמעויות קרובות בלי הכרעה; הציטוט (שבת קמח א) אינו מכריע."),
    "wikt-7630-s1-d3": ("defer", None, "ד־ היא תחילית דקדוקית ולא מילה; המפתח «ד» יתאים לכל סימון האות. לשקול ערך «ד-» או פסילה."),
    "wikt-22001-s2-d1": ("add", None, "דִּי = אשר, ש- (ארמית מקראית); המפתח «די» הוא גם «דַּי» העברי."),
    "wikt-22001-s2-d2": ("add", None, "דִּי = של (קניין); משמעות משלימה לקודמת, באותו ערך."),
    "wikt-8727-s1-d1": ("add", "דיו", "דיותא = דיו. ההמשך בהגדרה הוא הסבר אנציקלופדי ולכן קוצר."),
    "wikt-31081-s2-d1": ("add", None, "זְבַן = קנה (גם מכר); «קנה» נבדל מהקיים «מכר» ומאושר גם במילון שיח ישראל."),
    "wikt-19048-s1-d1": ("add", None, "חברותא = חברות. המפתח נוקה מ«(וגם: חברותה)»; «חברותה» נוסף כמפתח משלים."),
    "wikt-59847-s1-d1": ("add", None, "חוכא = צחוק; תואם מילון אחר בקובץ (שחוק)."),
    "wikt-50182-s1-d6": ("defer", None, "«ממתקים חלי – דבר מתוק»: ניסוח מקולקל (מקור: «חוליא», מגילה ז ע\"ב = מעדן); הדף עצמו ערך עברי «חוליה». נדרש ניסוח מחדש."),
    "wikt-60208-s1-d1": ("add", None, "חֲקַל = שדה; תואם מילון אחר בקובץ."),
    "wikt-40650-s2-d1": ("dup", None, "זהה לקיים «טוב»."),
    "wikt-23833-s1-d1": ("dup", None, "זהה לקיים «מס קרקע»."),
    "wikt-47332-s3-d1": ("reject", None, "טְעֵם = צו (ארמית מקראית), אך המפתח «טעם» הוא המילה העברית השכיחה: חלון הקשר מטעה."),
    "wikt-50031-s1-d1": ("dup", None, "«גלעד» (שם המקום) הוא התרגום; הקיים «גל עד» הוא הפירוש המילולי הטוב יותר."),
    "wikt-42906-s1-d2": ("defer", None, "יציב = אזרח/תושב קבע: משמעות מצומצמת, והמפתח הוא «יציב» העברי. נדרש אימות."),
    "wikt-23152-s2-d1": ("defer", None, "«כלוב» = קרדום/גרזן: המפתח הוא «כלוב» העברי הנפוץ, והמשמעות אינה מבוססת בדף."),
    "wikt-23834-s1-d1": ("add", None, "כַּרְגָּא = מס גולגולת; תואם מילון אחר בקובץ."),
    "wikt-23168-s1-d1": ("add", "חולדה", "כרכושתא = חולדה; ההמשך (טקסונומיה) הוא הסבר אנציקלופדי ולכן קוצר. המפתח נוקה מ«(גם: ...)»."),
    "wikt-50161-s1-d1": ("dup", None, "קיים «כרישין, ירוק»: אותה משמעות (כרתי = כרישה). הגדרת ויקימילון ארוכה ומנוקדת — לא מוסיפים."),
    "wikt-7152-s1-d3": ("defer", None, "הגדרה עם הסתייגות («כנראה גם בעברית») וציטוט — לא פירוש נקי; הדוגמה מתארת חייל ולא מפקד. הקיים: «שׂר»."),
    "wikt-56056-s1-d1": ("dup", None, "זהה לקיים «אין»."),
    "wikt-60263-s1-d1": ("dup", None, "זהה לקיים «לפי, על פי»."),
    "wikt-42581-s2-d1": ("defer", None, "«מזור» = מחבט (משנה, כלים) — ככל הנראה עברית משנאית ולא ארמית; המפתח הוא «מזור» העברי."),
    "wikt-58467-s1-d1": ("defer", None, "«כסף מזוקק מסיגים» אינו מאומת; בגמרא ייתכן שמטקסא = משי/חוטי משי. נדרש אימות."),
    "wikt-6278-s1-d2": ("defer", None, "הגדרה דקדוקית ארוכה («מילת שאלה רטורית»), לא תרגום; המפתח «מי» הוא העברי. אפשרי ניסוח: «האם»."),
    "wikt-45670-s3-d1": ("reject", None, "מַן = מי; המפתח «מן» הוא מילת היחס השכיחה. הצורה הנפוצה «מאן» נוספה כמפתח נפרד."),
    "wikt-14610-s2-d1": ("defer", None, "מעברת = קו חלוקה בשיער (משנה): ככל הנראה עברית משנאית, והמפתח «מעברת» נפוץ בעברית."),
    "wikt-59730-s1-d1": ("dup", None, "זהה לקיים «ישיבה»."),
    "wikt-45761-s1-d1": ("add", None, "נוּן = דג (ארמית)."),
    "wikt-47929-s1-d1": ("add", None, "נרגילה = קוקוס (לשון חז\"ל)."),
    "wikt-36286-s1-d1": ("add", "משחק לוח", "נרדשיר = משחק לוח (שש-בש); ההגדרה המורחבת קוצרה. הכתיב «נדרשיר» נוסף כמפתח משלים."),
    "wikt-8573-s2-d1": ("reject", None, "«סימן» = מטמון/אוצר: משמעות נדירה ובלתי מאומתת תחת מפתח עברי שכיח מאוד."),
    "wikt-13259-s1-d1": ("add", None, "סָלַק = עלה (ארמית); תואם מילון אחר בקובץ."),
    "wikt-26492-s1-d1": ("add", None, "עִזְקְתָא = טבעת (דניאל ו, יח; גם בגמרא)."),
    "wikt-13644-s2-d1": ("dup", None, "זהה לקיים «מלאך»."),
    "wikt-32366-s2-d1": ("add", None, "עלמא/עלם = עולם. הלמה הראשית בדף היא «עָלַם (גם: עָלְמָא)»; הצורה הנפוצה בגמרא היא «עלמא»."),
    "wikt-2231-s3-d1": ("add", None, "עֲמַר = צמר (ארמית מקראית)."),
    "wikt-62191-s1-d1": ("add", "ערום", "ערטילאי = ערום; ההגדרה בדף חוזרת על עצמה, קוצרה."),
    "wikt-60265-s1-d1": ("dup", None, "זהה לקיים «פה»."),
    "wikt-6513-s1-d5": ("reject", None, "«בגד עליון» (פטיש/פטישיהון, דניאל ג) תחת מפתח «פטיש» העברי (כלי) — מטעה ונדיר."),
    "wikt-8862-s4-d1": ("reject", None, "ההגדרה בדף עברית (לשון המקרא), והמפתח «צבע» שכיח; אינה משמעות ארמית של הגמרא."),
    "wikt-57633-s2-d1": ("add", None, "צִלָּה = התפלל (מצלינן: ברכות). הכתיב המלא «צילה» נוסף כמפתח משלים."),
    "wikt-20034-s1-d1": ("ext", None, "קַמָּא = ראשון/הקודם; מרחיב את הקיים «ראשון» במילה «הקודם» (שינוי בפירוש קיים — לאישור בלבד)."),
    "wikt-26115-s2-d1": ("add", "דלעת", "קָרָא = דלעת (משמעות שונה מהקיים «הכתוב, מקרא»)."),
    "wikt-28132-s1-d1": ("add", "ריצה", "רהטא = ריצה. המשפט שאחריו הוא הסבר שימוש. הכתיב המלא «ריהטא» נוסף כמפתח משלים."),
    "wikt-12180-s2-d1": ("reject", None, "רוּמָא = גובה, אך המפתח «רומא» הוא העיר רומא — חלון הקשר מטעה."),
    "wikt-52743-s3-d1": ("add", "ערב", "רְמַשׁ = ערב (ארמית מקראית); תואם מילון אחר בקובץ. ההרחבה בדף קוצרה."),
    "wikt-52737-s1-d1": ("dup", None, "זהה לקיים «עזב»."),
    "wikt-6019-s1-d1": ("dup", None, "זהה לקיים «חתול»."),
    "wikt-63866-s1-d1": ("add", None, "שֵׁיזָבוּת = ישועה, פדות, הצלה (ארמית מקראית/תרגומית)."),
    "wikt-38575-s1-d1": ("add", "נר", "שרגא = נר; תואם מילון אחר בקובץ."),
    "wikt-22751-s1-d1": ("add", "שישית (חלק אחד מששה)", "שתות = שישית; ניסוח מקוצר ומסודר."),
    "wikt-59363-s2-d1": ("dup", None, "זהה לקיים «שישים»."),
    "wikt-2157-s3-d1": ("dup", None, "«עוד» כבר בפירוש הקיים; «פעם נוספת» = «שוב»."),
    "wikt-24070-s1-d1": ("add", "שנים עשר", "תְּרֵי עֲשַׂר = שנים עשר (זכר) לעומת הקיים «שתים-עשרה» (נקבה): הבדל מין — לא ממזגים בלי הוכחה."),
}

# כתיבים חלופיים שאינם יורשים את החלטת הלמה הראשית
VARIANT_OVERRIDES: dict[str, tuple[str, str | None, str]] = {
    "אימר": ("add", "טלה, כבש", "הכתיב המלא «אימר» אינו מתנגש במילה «אמר» — נוסף כמפתח נפרד."),
    "מאן": ("add", "מי", "«מאן» = מי: הצורה הנפוצה בגמרא; אינה מתנגשת ב«מן»."),
}


def main() -> None:
    cfg = load_config()
    queue = [i for i in read_jsonl(work_dir(cfg, "merge", "queue.jsonl")) if i["kind"] == "wiktionary_candidate"]
    by_primary: dict[str, dict[str, Any]] = {}
    for item in queue:
        for occ in item["groups"][0][0]["occurrences"]:
            by_primary[occ["record_id"]] = item
    out: list[dict[str, Any]] = []
    missing: list[str] = []
    for item in queue:
        claim = item["groups"][0][0]
        occ = claim["occurrences"][0]
        variant_of = occ.get("variant_of")
        base_id = variant_of or occ["record_id"].split("~")[0]
        verdict = V.get(base_id)
        if verdict is None:
            missing.append(base_id)
            continue
        kind, text, why = verdict
        if variant_of and item["normalized_key"] in VARIANT_OVERRIDES:
            kind, text, why = VARIANT_OVERRIDES[item["normalized_key"]]
        proposal = item["system_proposal"]
        ids = [claim["claim_id"]]
        rec: dict[str, Any] = {"item_id": item["item_id"], "needs_human": True, "reviewer": "agent:wiktionary-main", "rationale": why}
        if variant_of and kind not in ("reject", "defer"):
            rec["rationale"] += " (כתיב חלופי/מלא של הלמה בדף.)"
        if kind == "dup" and not proposal["support"] and item["existing_senses"]:
            # הגדרת ויקימילון שונה בניסוח מהקיים (למשל ארוכה/מנוקדת) אך זהה במשמעות לפי הבדיקה הידנית
            ex = item["existing_senses"][0]
            rec.update(action="custom", **{"class": "semantic_duplicate"}, add_senses=[], support=[{"target_sense_id": ex["sense_id"], "claim_ids": ids}], modify_existing=[], confidence=0.7)
        elif kind == "dup" and proposal["support"]:
            sup = proposal["support"][0]
            rec.update(action="custom", **{"class": "exact_duplicate" if sup["relation"] == "identical" else "semantic_duplicate"},
                       add_senses=[], support=[{"target_sense_id": sup["target_sense_id"], "claim_ids": ids}], modify_existing=[], confidence=0.85)
        elif kind == "ext" and proposal["modify_existing"]:
            mod = proposal["modify_existing"][0]
            rec.update(action="custom", **{"class": "semantic_duplicate"}, add_senses=[], support=[], modify_existing=[{**mod, "claim_ids": ids}], confidence=0.5)
        elif kind == "add" or (kind == "dup" and not proposal["support"]):
            if variant_of and item["existing_senses"] and proposal["support"]:
                sup = proposal["support"][0]
                rec.update(action="custom", **{"class": "semantic_duplicate"}, add_senses=[], support=[{"target_sense_id": sup["target_sense_id"], "claim_ids": ids}], modify_existing=[], confidence=0.8)
            else:
                rec.update(action="custom", **{"class": "grammatical_variant" if base_id == "wikt-24070-s1-d1" else "distinct_sense"},
                           add_senses=[{"text": text or claim["gloss"], "claim_ids": ids}], support=[], modify_existing=[], confidence=0.7)
        elif kind == "reject":
            rec.update(action="reject", **{"class": "rejected"}, confidence=0.75)
        else:
            rec.update(action="defer", **{"class": "uncertain"}, confidence=0.4)
        out.append(rec)
    write_jsonl(work_dir(cfg, "review", "wikt_agent_suggestions.jsonl"), out)
    print(f"{len(out)} הצעות; חסרות בטבלה: {missing}")


if __name__ == "__main__":
    main()
