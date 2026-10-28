"""הרצה חוזרת של כל הצינור לפי הסדר: חילוץ → נרמול → סיווג → מיזוג → ייצוא → בקרה.

דוגמאות:
  py run_all.py                       # הכול (כולל חילוץ מחדש של ה-PDF וויקימילון)
  py run_all.py --skip-extract        # מהנרמול והלאה (מהנתונים שכבר חולצו)
  py run_all.py --only siftey_gitin   # חילוץ מקור אחד בלבד (ואז המשך בשלבים הבאים)
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run(script: str, *args: str) -> None:
    print(f"\n=== {script} {' '.join(args)}")
    subprocess.run([sys.executable, str(HERE / script), *args], check=True, cwd=HERE)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-extract", action="store_true", help="דלג על חילוץ ה-PDF/ויקימילון")
    parser.add_argument("--only", choices=["siftey_gitin", "siftey_brachot", "wiktionary"], help="חלץ מקור אחד בלבד")
    parser.add_argument("--include-agent-suggestions", action="store_true", help="תצוגה מקדימה כולל הצעות סוכן (לא להפצה)")
    args = parser.parse_args()
    run("baseline.py")
    if not args.skip_extract:
        if args.only in (None, "siftey_gitin", "siftey_brachot"):
            run("extract_pdfs.py", "--source", args.only or "all")
        if args.only in (None, "wiktionary"):
            run("extract_wiktionary.py")
    run("normalize.py")
    run("classify_senses.py")
    run("merge.py")
    run("export.py")
    run("validate.py")
    if args.include_agent_suggestions:
        run("merge.py", "--include-agent-suggestions", "--tag", "preview")
        run("export.py", "--tag", "preview")
        run("validate.py", "--tag", "preview")


if __name__ == "__main__":
    main()
