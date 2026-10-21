import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// פתיחת חלונות אוצריא נוספים — המשטח שהקוראים משתמשים בו בפועל.
/// כל פתיחת חלון עוברת דרך [WindowOpener.current], ולא ישירות דרך המימוש.
abstract interface class WindowOpener {
  /// המימוש הפעיל. ניתן להחלפה בבדיקות דרך [debugOverride].
  static WindowOpener get current =>
      debugOverride ?? const MultiWindowService();

  @visibleForTesting
  static WindowOpener? debugOverride;

  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    ({int left, int top, int width, int height})? bounds,
  });

  Future<bool> openEmptyWindow();

  Future<bool> restoreLastClosedWindow();

  Future<bool> canOpenAnotherWindow();

  /// `null` כשלא ידוע — ראו [MultiWindowService.windowCount].
  Future<({int count, int max, int engines})?> windowCount();

  Future<void> reportOpenWindowFailure();
}
