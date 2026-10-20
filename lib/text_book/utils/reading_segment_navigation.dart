import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// קו העוגן (חלק מ-0..1 מגובה ה-viewport) שאליו הניווט מיישר את תחילת הקטע,
/// וגם הקו שלפיו נקבע "המיקום הנוכחי" בספר (ההדגשה בסרגל הניווט). שני הצדדים
/// חייבים להשתמש באותו ערך כדי שההדגשה תתאים בדיוק למקום שהניווט מוביל אליו.
const double kReadingAnchorAlignment = 0.05;

/// היישור שבו נפתחת רשימת הקריאה. מעל הפריט הראשון אין תוכן, ולכן קו העוגן
/// אינו בר-השגה שם: הפתיחה מציגה רווח ריק שנעלם בגלילה הראשונה ואינו חוזר.
double initialReadingAlignment(int initialIndex) =>
    initialIndex == 0 ? 0 : kReadingAnchorAlignment;

/// טווח המטמון של רשימות הקריאה, במסכים לכל צד. כל קפיצה בונה אותו מחדש,
/// וברירת המחדל של החבילה (2) בונה כחמישה מסכים של פסקאות.
const double kReaderCacheExtentScreens = 1.5;

/// גובה משוער של פריט קריאה שטרם נפרס, לפי אורך הטקסט ורוחב הרשימה. גס
/// בכוונה: הקפיצות מדויקות בכל מקרה, וההערכה רק מקרבת את טווח הגלילה.
ItemExtentEstimator readingExtentEstimator(
  ReadingSegments segments,
  double fontSize,
) {
  final lineExtent = fontSize * 1.6;
  final charWidth = fontSize * 0.45;
  final layout = segments.layout;
  return (index, width) {
    if (index >= layout.itemCount || width <= charWidth) return lineExtent;
    final sums = _visibleLengthSums[segments] ??= _VisibleLengthSums(segments);
    final chars = sums.charsBetween(
      layout.firstLineOf(index),
      layout.lastLineOf(index),
    );
    final lines = (chars * charWidth / width).ceil();
    return (lines < 1 ? 1 : lines) * lineExtent + fontSize;
  };
}

final Expando<_VisibleLengthSums> _visibleLengthSums = Expando(
  'visibleLengthSums',
);

/// סכומים מצטברים של תווים נראים ושל שורות שלא נטענו, כדי שהערכת פריט תהיה
/// O(1) בלי לבנות את הפסקה. שורה שלא נטענה נספרת כאורך הממוצע של הטעונות.
class _VisibleLengthSums {
  _VisibleLengthSums(ReadingSegments segments)
    : _chars = Int64List(segments.content.length + 1),
      _unloaded = Int32List(segments.content.length + 1) {
    final content = segments.content;
    final flags = segments.loadedLineFlags;
    var loadedLines = 0;
    for (var line = 0; line < content.length; line++) {
      final loaded = flags == null || (line < flags.length && flags[line]);
      _chars[line + 1] =
          _chars[line] + (loaded ? visibleReadingCharCount(content[line]) : 0);
      _unloaded[line + 1] = _unloaded[line] + (loaded ? 0 : 1);
      if (loaded) loadedLines++;
    }
    _unloadedLineChars = loadedLines == 0
        ? _defaultLineChars
        : _chars[content.length] / loadedLines;
  }

  static const double _defaultLineChars = 200;

  final Int64List _chars;
  final Int32List _unloaded;
  late final double _unloadedLineChars;

  double charsBetween(int first, int last) {
    final end = (last + 1).clamp(0, _chars.length - 1);
    final start = first.clamp(0, end);
    return (_chars[end] - _chars[start]) +
        (_unloaded[end] - _unloaded[start]) * _unloadedLineChars;
  }
}

/// מספר התווים שתופסים רוחב בשורה: בלי תגיות HTML ובלי ניקוד וטעמים
/// (U+0591–U+05C7), שאינם מוסיפים רוחב לאות שעליה הם יושבים.
@visibleForTesting
int visibleReadingCharCount(String text) {
  var count = 0;
  var inTag = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inTag) {
      if (c == 0x3E) inTag = false;
    } else if (c == 0x3C) {
      inTag = true;
    } else if (c < 0x0591 || c > 0x05C7) {
      count++;
    }
  }
  return count;
}

/// קו העוגן לניווט אל תוצאת חיפוש — ממקם את המילה שנמצאה סביב מרכז-עליון
/// התצוגה (ולא בראש), כדי שיהיה הקשר גם מעל המילה. זהה לסרגל התוצאות בחלונית
/// ולפתיחת ספר מהחיפוש הכללי.
const double kSearchResultAnchorAlignment = 0.35;

/// סבילות סיווג סביב קו העוגן. חייבת להיות גדולה מ-[kAnchorLandingEpsilon]
/// (שגיאת נחיתה מותרת) וקטנה מגובה שורת טקסט (~0.025) - אחרת הסיווג מתהפך.
const double _anchorRemnantTolerance = 0.008;

/// סף עצירה לדיוק העדין האיטרטיבי (חלק מה-viewport): מתחת למרחק הזה מהעוגן
/// הניווט נחשב "הגיע". חייב להישאר קטן מ-[_anchorRemnantTolerance].
const double kAnchorLandingEpsilon = 0.003;

/// כמה מהקטע (חלק מה-viewport) נמצא ב"אזור הקריאה" - מתחת לקו העוגן.
double _readingZonePresence(double leadingEdge, double trailingEdge) {
  final top = leadingEdge < kReadingAnchorAlignment
      ? kReadingAnchorAlignment
      : leadingEdge;
  final bottom = trailingEdge > 1.0 ? 1.0 : trailingEdge;
  final presence = bottom - top;
  return presence < 0 ? 0 : presence;
}

/// האם קטע ([leadingEdge]..[trailingEdge]) הוא שייר של הסעיף הקודם: מתחיל
/// משמעותית מעל קו העוגן ונגמר בו. קטע שמתחיל בעוגן עצמו הוא יעד הניווט.
bool isRemnantAbovePositionAnchor(double leadingEdge, double trailingEdge) =>
    kReadingAnchorAlignment - leadingEdge > _anchorRemnantTolerance &&
    _readingZonePresence(leadingEdge, trailingEdge) <= _anchorRemnantTolerance;

/// סוגר את חלונית הצד רק אחרי שגלילת [navigation] הסתיימה: סגירה תוך כדי
/// הגלילה מפעילה עיגון-מחדש של הטקסט שמבטל את האנימציה והניווט לא מתבצע.
Future<void> closePaneAfterNavigation({
  required Future<void> navigation,
  required void Function() closePane,
}) async {
  try {
    await navigation;
  } finally {
    closePane();
  }
}

ItemPosition? _findPosition(ItemPositionsListener listener, int segmentIndex) {
  for (final position in listener.itemPositions.value) {
    if (position.index == segmentIndex) {
      return position;
    }
  }
  return null;
}

/// גלילה לשורת מקור [lineIndex] תוך תרגום אוטומטי לסגמנט.
///
/// [intraLineFraction] (0..1) הוא מיקום היעד בתוך השורה (למשל מילת חיפוש בתוך
/// פסקה ארוכה). הגלילה מכוונת ישר אל השורה ולא לתחילת הסגמנט.
///
/// אחרי הנחיתה היעד נמדד ומתוקן בקפיצה מדויקת: תוכן שנטען תוך כדי הגלילה
/// (טעינה הדרגתית) או הפרעה לאנימציה מסיטים אותו.
///
/// [latestSegments] מחשב מחדש את מיקום השורה בפסקה כשתוכנה נטען תוך כדי
/// הגלילה; בלעדיו משתמשים ב-[segments] לאורך כל הגלילה. [measure] — גבולות
/// השורה מהרינדור כשהפריט בנוי; בלעדיו לפי אורך הטקסט.
Future<void> scrollToSourceLine({
  required ItemScrollController scrollController,
  required ItemPositionsListener? positionsListener,
  required ReadingSegments segments,
  required int lineIndex,
  required double viewportExtent,
  double alignment = kReadingAnchorAlignment,
  double intraLineFraction = 0,
  Duration duration = const Duration(milliseconds: 250),
  Curve curve = Curves.ease,
  ReadingSegments Function()? latestSegments,
  bool Function()? isCurrent,
  MeasuredLineExtent? measure,
}) async {
  if (segments.isEmpty || !scrollController.isAttached) {
    return;
  }

  var segmentIndex = -1;
  var fraction = 0.0;
  var safeLineIndex = lineIndex;
  bool resolveTarget() {
    final current = latestSegments?.call() ?? segments;
    if (current.isEmpty) return false;
    safeLineIndex = lineIndex.clamp(0, current.layout.lineCount - 1).toInt();
    segmentIndex = segmentIndexForLine(current, safeLineIndex);
    fraction = lineFractionInItem(
      current,
      segmentIndex,
      safeLineIndex,
      intraLineFraction: intraLineFraction,
      measure: measure,
    );
    return true;
  }

  // היסט השורה מתחילת הפריט; לפריט שטרם נפרס לפי גובהו המוערך.
  double lineOffset() {
    // הלקוח של הבקר מתחבר לפני ה-sliver; אז אין עדיין גובה פריט.
    final list = scrollController.listController;
    final extent = list != null && list.isAttached
        ? list.extentForIndex(segmentIndex).$1
        : 0.0;
    return -fraction * extent;
  }

  // ניווט ליעד שבמסך ותיקוני הנחיתה אינם קפיצה: הבחירה בטקסט נשמרת.
  T quietly<T>(T Function() move) {
    final controller = scrollController;
    return controller is JumpAwareItemScrollController
        ? controller.withoutNotifying(move)
        : move();
  }

  if (!resolveTarget()) return;
  final visible = positionsListener?.itemPositions.value.any(
    (p) =>
        p.index == segmentIndex &&
        p.itemTrailingEdge > 0 &&
        p.itemLeadingEdge < 1,
  );
  T initialMove<T>(T Function() move) =>
      visible == true ? quietly(move) : move();
  if (duration == Duration.zero) {
    initialMove(
      () => scrollController.jumpTo(
        index: segmentIndex,
        alignment: alignment,
        offset: lineOffset(),
      ),
    );
  } else {
    await initialMove(
      () => scrollController.scrollTo(
        index: segmentIndex,
        alignment: alignment,
        offset: lineOffset(),
        duration: duration,
        curve: curve,
      ),
    );
  }
  if (positionsListener == null) return;
  await WidgetsBinding.instance.endOfFrame;

  var previousDistance = double.infinity;
  var confirmed = false;
  for (var attempt = 0; attempt < 5; attempt++) {
    // הרשימה יורדת מהעץ באמצע האנימציה (מעבר כרטיסיה, סגירתה, העברתה לחלון
    // אחר), או מוחלפת בקורא חיצוני — מדידות ישנות אינן מעידות שהרשימה חיה.
    if (!scrollController.isAttached || !(isCurrent?.call() ?? true)) {
      return;
    }
    final previousTarget = (segmentIndex, fraction);
    if (!resolveTarget()) return;
    // תוכן שנטען הזיז את היעד: המרחק הקודם אינו בסיס להשוואה.
    if (previousTarget != (segmentIndex, fraction)) {
      previousDistance = double.infinity;
    }
    final scroll = scrollController.scrollController;
    final viewport = scroll != null && scroll.hasClients
        ? scroll.position.viewportDimension
        : viewportExtent;
    final measured = _findPosition(positionsListener, segmentIndex);
    if (measured != null) {
      final extent =
          (measured.itemTrailingEdge - measured.itemLeadingEdge) * viewport;
      final distance =
          ((measured.itemLeadingEdge - alignment) * viewport +
                  fraction * extent)
              .abs();
      if (distance <= viewport * kAnchorLandingEpsilon) {
        // מאמתים בפריים הבא: מדידת השורות בפריט החדש מגיעה אחרי פריסתו.
        if (confirmed) return;
        confirmed = true;
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      // קצה הספר אינו מאפשר ליישר את היעד לעוגן; אז המרחק לא קטן.
      if (distance >= previousDistance) return;
      previousDistance = distance;
    }
    confirmed = false;
    quietly(
      () => scrollController.jumpTo(
        index: segmentIndex,
        alignment: alignment,
        offset: lineOffset(),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
  }
}
