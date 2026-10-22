import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';

/// נקודת אחיזה גלובלית לפתיחת פאנל הכלים.
///
/// הפאנל הוא מצב פנימי של `MainWindowScreen`, אבל נדרש לפתוח אותו גם מהקשרים
/// שאין להם `BuildContext` של המסך: גשר התוספים, קישורים עמוקים, קיצורי
/// מקלדת והסיור המודרך. אותו דפוס כמו `PluginPageLauncher.navigator`.
class ToolsLauncherController {
  ToolsLauncherController._();

  static final ToolsLauncherController instance = ToolsLauncherController._();

  final _openers = Expando<void Function()>();

  /// הפותח של החלון הנוכחי. `null` כשהמסך שלו אינו מורכב.
  void Function()? get opener => _openers[AppWindowKeys.current];
  set opener(void Function()? value) => _openers[AppWindowKeys.current] = value;

  /// נקרא על-ידי `MainWindowScreen` של החלון [keys].
  void register(AppWindowKeys keys, void Function() opener) =>
      _openers[keys] = opener;

  /// מסיר את [opener] רק אם הוא עדיין הרשום (השוואה ב-== — tear-off חדש בכל גישה).
  void unregister(AppWindowKeys keys, void Function() opener) {
    if (_openers[keys] == opener) _openers[keys] = null;
  }

  @visibleForTesting
  int openCount = 0;

  void open() {
    openCount++;
    opener?.call();
  }
}
