import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// פתיחת חלונות אוצריא נוספים — המשטח שהקוראים משתמשים בו בפועל.
/// כל פתיחת חלון עוברת דרך [WindowOpener.current], ולא ישירות דרך המימוש.
abstract interface class WindowOpener {
  /// המימוש הפעיל. ניתן להחלפה בבדיקות דרך [debugOverride].
  /// ב-Windows וב-Linux תמיד חלונות Dart; בלי בעלים הם פשוט אינם נפתחים.
  static WindowOpener get current =>
      debugOverride ??
      (MultiViewMode.usesEngineWindows
          ? const MultiWindowService()
          : ViewWindowOpener.instance);

  @visibleForTesting
  static WindowOpener? debugOverride;

  /// [tab] נשאר של הקורא — החלון החדש מקבל עותק. מעבר מחלון מסיר אותה שם
  /// (`RemoveTab`); כרטיסיה שלא הוצגה בשום חלון הקורא משחרר בעצמו.
  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    ({int left, int top, int width, int height})? bounds,
    bool inheritPlacement = true,
  });

  Future<bool> openEmptyWindow();

  Future<bool> restoreLastClosedWindow();

  Future<bool> canOpenAnotherWindow();

  /// `null` כשלא ידוע — ראו [MultiWindowService.windowCount].
  Future<({int count, int max, int engines})?> windowCount();

  Future<void> reportOpenWindowFailure();
}
