import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';

/// מדוע כל החלונות נסגרים; לרישום בלבד.
enum AppQuitReason { update }

/// נקודת הכניסה היחידה ליציאה מכל החלונות ולבנייתם מחדש. בריבוי תצוגות
/// אין למי לשדר באפיק, וסגירת הראשי רק מסתירה אותו כשחלונות Dart פתוחים.
abstract final class AppQuit {
  static Future<void> Function()? _quitProcess;

  /// מסלול היציאה המלא של התהליך: שאלות, שטיפה, הריסת החלונות וסיום.
  /// נקבע ב-main בריבוי תצוגות בלבד.
  static void install(Future<void> Function() quitProcess) =>
      _quitProcess = quitProcess;

  @visibleForTesting
  static void resetForTest() => _quitProcess = null;

  /// יציאה מכל החלונות: הסשנים של כולם נשמרים להפעלה הבאה והתהליך מסתיים.
  /// חזרה מהקריאה פירושה ביטול (שינויים שלא נשמרו), או מודל A — כמו קודם.
  static Future<void> quitAll(
    AppQuitReason reason, {
    required AppWindowController window,
  }) async {
    final quitProcess = _quitProcess;
    if (MultiViewMode.enabled && quitProcess != null) {
      debugPrint('AppQuit.quitAll(${reason.name})');
      await quitProcess();
      return;
    }
    MultiWindowService.closePeers();
    // ⚠️ סגירה מנומסת ולא `quitApplication()`: האחרון הוא `PostQuitMessage`
    // ומפיל את המנוע תחת Dart רץ. ראו התיעוד ב-`AppWindowController`.
    await window.close();
  }

  /// בונה מחדש את כל החלונות בלי לצאת מהתהליך. בריבוי תצוגות `RestartWidget`
  /// עוטף גם את חלונות ה-Dart; במודל A כל מנוע מתבקש באפיק.
  static void restartAll(
    BuildContext context, {
    bool? pluginSafeMode,
    FutureOr<void> Function()? afterRestart,
  }) {
    if (!MultiViewMode.enabled) {
      MultiWindowService.restartPeers(pluginSafeMode: pluginSafeMode);
    }
    RestartWidget.restartApp(context, afterRestart: afterRestart);
  }
}
