/// פריסת הקריאה: מיפוי שורות מקור לפריטי `ScrollablePositionedList`.
///
/// הפריסה נגזרת ממבנה הספר בלבד (מספר השורות, שורות ה-TOC ומצב הרצף) ולא
/// מהתוכן שנטען, ולכן מספור הפריטים אינו זז בטעינת טווחים או בשחרור תוכן.
library;

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// מספר הרצות תבניות הכותרת/היישור; נספר רק במצב debug.
int debugReadingTagPatternChecks = 0;

/// מתחת ל-U+1680, `\s` של RegExp ב-Dart תופס רק תווים עד 0x20 ואת U+00A0.
bool _mayBeRegExpSpace(int c) => c <= 0x20 || c == 0xA0 || c >= 0x1680;

/// שתי התבניות דורשות `<` אחרי רווח מוביל, ולכן שורה שמתחילה באות נפסלת בלי RegExp.
bool _matchesLeadingTag(RegExp pattern, String line) {
  if (line.isEmpty) return false;
  final c = line.codeUnitAt(0);
  if (c != 0x3C && !_mayBeRegExpSpace(c)) return false;
  assert(() {
    debugReadingTagPatternChecks++;
    return true;
  }());
  return pattern.hasMatch(line);
}

bool isReadingHeaderLine(String line) =>
    _matchesLeadingTag(_headerPattern, line);

final RegExp _headerPattern = RegExp(r'^\s*<h[1-6]', caseSensitive: false);

/// שורה מיושרת במפורש (`text-align` / `<center>`) היא בלוק: בתוך פסקה רציפה
/// היישור אובד. עוגנים ריקים ו-`<br>` בתחילתה אינם משנים זאת.
bool isAlignedBlockLine(String line) =>
    _matchesLeadingTag(_alignedBlockPattern, line);

final RegExp _alignedBlockPattern = RegExp(
  r'^\s*(?:(?:<a\b[^>]*>\s*</a>|<br\s*/?>)\s*)*'
  r'<(?:center\b|div\b[^>]*\btext-align\s*:)',
  caseSensitive: false,
);

/// פריסה בלתי-משתנה: במצב רגיל פריט לכל שורה; במצב רציף כל שורת שבירה
/// היא פריט לבדה, וכל רצף מרבי של שורות אחרות הוא פסקה אחת.
@immutable
class ReadingLayout {
  /// מצב רגיל — פריט לכל שורה.
  const ReadingLayout.identity(this.lineCount)
    : continuous = false,
      _starts = null,
      _breakItems = null;

  const ReadingLayout._continuous(
    this.lineCount,
    this._starts,
    this._breakItems,
  ) : continuous = true;

  /// [breakLines] מחוץ לטווח השורות מתעלמים מהן.
  factory ReadingLayout.continuous({
    required int lineCount,
    required Iterable<int> breakLines,
  }) {
    final breaks =
        breakLines
            .where((line) => line >= 0 && line < lineCount)
            .toSet()
            .toList()
          ..sort();
    final starts = <int>[];
    final breakItems = <bool>[];
    var cursor = 0;
    for (final line in breaks) {
      if (line > cursor) {
        starts.add(cursor);
        breakItems.add(false);
      }
      starts.add(line);
      breakItems.add(true);
      cursor = line + 1;
    }
    if (cursor < lineCount) {
      starts.add(cursor);
      breakItems.add(false);
    }
    return ReadingLayout._continuous(
      lineCount,
      Int32List.fromList(starts),
      List<bool>.unmodifiable(breakItems),
    );
  }

  final int lineCount;
  final bool continuous;
  final Int32List? _starts;
  final List<bool>? _breakItems;

  int get itemCount => _starts?.length ?? lineCount;

  bool get isEmpty => itemCount == 0;

  bool get isNotEmpty => itemCount > 0;

  /// הפריט שמכיל את [line]; שורה מחוץ לטווח נצמדת לפריט הקרוב.
  int itemForLine(int line) {
    final starts = _starts;
    if (starts == null) {
      if (lineCount == 0) return 0;
      return line.clamp(0, lineCount - 1);
    }
    if (starts.isEmpty || line <= 0) return 0;
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (starts[mid] <= line) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  int firstLineOf(int item) {
    final starts = _starts;
    if (starts == null) return item;
    return starts[item];
  }

  int lastLineOf(int item) {
    final starts = _starts;
    if (starts == null) return item;
    return item + 1 < starts.length ? starts[item + 1] - 1 : lineCount - 1;
  }

  int lineCountOf(int item) => lastLineOf(item) - firstLineOf(item) + 1;

  /// פריט של שורת שבירה (כותרת TOC או בלוק מיושר) במצב רציף.
  bool isBreakItem(int item) => _breakItems?[item] ?? false;

  bool hasSameStructure(ReadingLayout other) {
    if (identical(this, other)) return true;
    if (lineCount != other.lineCount || continuous != other.continuous) {
      return false;
    }
    final starts = _starts;
    final otherStarts = other._starts;
    if (starts == null || otherStarts == null) {
      return starts == otherStarts;
    }
    return listEquals(starts, otherStarts) &&
        listEquals(_breakItems, other._breakItems);
  }
}

/// שורות השבירה של ספר במצב רציף: שורות ה-TOC, ובלוקים מיושרים רק כשכל
/// התוכן כבר טעון (אחרת היו מופיעים באמצע הקריאה ומזיזים את המספור).
Set<int> readingBreakLines({
  required List<TocEntry> tableOfContents,
  required List<String> content,
  List<bool>? loadedLineFlags,
}) {
  final breaks = <int>{
    for (final entry in flattenToc(tableOfContents)) entry.index,
  };
  final allLoaded = loadedLineFlags == null
      ? true
      : loadedLineFlags.length >= content.length &&
            !loadedLineFlags.take(content.length).contains(false);
  if (allLoaded) {
    for (var line = 0; line < content.length; line++) {
      if (isAlignedBlockLine(content[line])) breaks.add(line);
    }
  }
  return breaks;
}

class _LayoutMemo {
  _LayoutMemo(TextBookLoaded state, this.layout)
    : bookTitle = state.book.title,
      lineCount = state.content.length,
      tableOfContents = state.tableOfContents,
      continuous = state.continuousReadingMode;

  final String bookTitle;
  final int lineCount;
  final List<TocEntry> tableOfContents;
  final bool continuous;
  final ReadingLayout layout;

  bool matches(TextBookLoaded state) =>
      bookTitle == state.book.title &&
      lineCount == state.content.length &&
      identical(tableOfContents, state.tableOfContents) &&
      continuous == state.continuousReadingMode;
}

/// ה-controller נשמר לאורך כל ה-states של אותו קורא, ולכן משמש מפתח לזיכרון.
/// משבצת לכל מצב, כדי ש-state ישן שנקרא אחרי החלפת מצב לא ידרוס את הפריסה.
final Expando<List<_LayoutMemo?>> _layoutMemos = Expando<List<_LayoutMemo?>>(
  'readingLayout',
);

/// הפריסה של [state]. נבנית מחדש רק כשהספר, אורכו, ה-TOC או מצב הרצף
/// משתנים — טעינת תוכן או שחרורו מחזירים את אותו מופע.
ReadingLayout readingLayoutOf(TextBookLoaded state) {
  final slots = _layoutMemos[state.scrollController] ??= [null, null];
  final slot = state.continuousReadingMode ? 1 : 0;
  final memo = slots[slot];
  if (memo != null && memo.matches(state)) return memo.layout;

  final built = state.continuousReadingMode
      ? ReadingLayout.continuous(
          lineCount: state.content.length,
          breakLines: readingBreakLines(
            tableOfContents: state.tableOfContents,
            content: state.content,
            loadedLineFlags: state.loadedLineFlags,
          ),
        )
      : ReadingLayout.identity(state.content.length);
  final layout = memo != null && memo.layout.hasSameStructure(built)
      ? memo.layout
      : built;
  slots[slot] = _LayoutMemo(state, layout);
  return layout;
}
