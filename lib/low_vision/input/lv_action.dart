import 'package:flutter/services.dart';

/// פעולות שאפשר להפעיל ממקלדת חיצונית או ממקשי מאקרו.
enum LvAction {
  next('עמוד הבא', [
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.space,
  ]),
  previous('עמוד קודם', [LogicalKeyboardKey.pageUp]),
  down('למטה / הפריט הבא', [LogicalKeyboardKey.arrowDown]),
  up('למעלה / הפריט הקודם', [LogicalKeyboardKey.arrowUp]),
  select('בחירה / אישור', [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]),
  back('חזרה', [LogicalKeyboardKey.escape, LogicalKeyboardKey.goBack]),
  first('להתחלה', [LogicalKeyboardKey.home]),
  last('לסוף', [LogicalKeyboardKey.end]),
  nextSection('הסעיף הבא', [LogicalKeyboardKey.arrowLeft]),
  previousSection('הסעיף הקודם', [LogicalKeyboardKey.arrowRight]),
  openBooks('רשימת הספרים', [LogicalKeyboardKey.f13]),
  openSearch('חיפוש ספרים', [LogicalKeyboardKey.f14]),
  zoomIn('הגדלה', [
    LogicalKeyboardKey.f15,
    LogicalKeyboardKey.numpadAdd,
    LogicalKeyboardKey.equal,
    LogicalKeyboardKey.zoomIn,
  ]),
  zoomOut('הקטנה', [
    LogicalKeyboardKey.f16,
    LogicalKeyboardKey.numpadSubtract,
    LogicalKeyboardKey.minus,
    LogicalKeyboardKey.zoomOut,
  ]),
  contents('תוכן העניינים', [LogicalKeyboardKey.f17]),
  contrast('החלפת צבעים', [LogicalKeyboardKey.f18]),
  togglePin('קבע / בטל קביעת ספר', [LogicalKeyboardKey.f19]),
  previousBook('הספר הקודם ברשימה', [LogicalKeyboardKey.f20]),
  nextBook('הספר הבא ברשימה', [LogicalKeyboardKey.f21]),
  home('מסך הבית', [LogicalKeyboardKey.f22]);

  const LvAction(this.label, this.defaultKeys);

  final String label;
  final List<LogicalKeyboardKey> defaultKeys;
}
