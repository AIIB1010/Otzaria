import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

/// מחוות מגע שהאפליקציה מזהה. גרירה באצבע אחת אינה כאן: היא תמיד "תפיסת העמוד"
/// והזזתו לכל כיוון, ולכן אינה ניתנת לשיוך.
enum LvGesture {
  doubleTapLeft('לחיצה כפולה בצד שמאל', LvTouchAction.nextPage),
  doubleTapRight('לחיצה כפולה בצד ימין', LvTouchAction.previousPage),
  twoFingerTap('נגיעה בשתי אצבעות', LvTouchAction.none),
  twoFingerDoubleTap('לחיצה כפולה בשתי אצבעות', LvTouchAction.zoomIn),
  threeFingerTap('נגיעה בשלוש אצבעות', LvTouchAction.none),
  threeFingerDoubleTap('לחיצה כפולה בשלוש אצבעות', LvTouchAction.zoomOut),
  hold('החזקה ארוכה (אצבע אחת, בלי לזוז)', LvTouchAction.back);

  const LvGesture(this.label, this.defaultAction);

  final String label;
  final LvTouchAction defaultAction;

  /// המחווה המקבילה ל"לחיצה כפולה" של אותו מספר אצבעות, אם קיימת.
  LvGesture? get doubleVariant => switch (this) {
    LvGesture.twoFingerTap => LvGesture.twoFingerDoubleTap,
    LvGesture.threeFingerTap => LvGesture.threeFingerDoubleTap,
    _ => null,
  };
}

/// פעולות שאפשר לשייך למחווה.
enum LvTouchAction {
  none('ללא פעולה', FluentIcons.prohibited_24_regular),
  nextPage('עמוד הבא', FluentIcons.arrow_down_24_filled),
  previousPage('עמוד קודם', FluentIcons.arrow_up_24_filled),
  back('חזרה', FluentIcons.arrow_left_24_filled),
  zoomIn('הגדלה', FluentIcons.add_24_filled),
  zoomOut('הקטנה', FluentIcons.subtract_24_filled),
  contents('תוכן עניינים', FluentIcons.text_bullet_list_24_filled),
  nextSection('הסעיף הבא', FluentIcons.arrow_next_24_regular),
  previousSection('הסעיף הקודם', FluentIcons.arrow_previous_24_regular),
  firstPage('לתחילת הספר', FluentIcons.arrow_upload_24_filled),
  lastPage('לסוף הספר', FluentIcons.arrow_download_24_filled),
  fullscreen('מסך מלא', FluentIcons.full_screen_maximize_24_filled),
  colors('החלפת צבעים', FluentIcons.color_24_filled),
  home('מסך הבית', FluentIcons.home_24_filled);

  const LvTouchAction(this.label, this.icon);

  final String label;
  final IconData icon;
}
