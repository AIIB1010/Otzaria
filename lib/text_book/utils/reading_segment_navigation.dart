import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

export 'package:otzaria/text_book/utils/reading_extent_estimates.dart';

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
