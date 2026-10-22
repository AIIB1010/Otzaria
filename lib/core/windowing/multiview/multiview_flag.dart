// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// הקובץ היחיד שנוגע ב-API הפנימי של Flutter לחלונות; כל השאר עובר דרכו.
import 'dart:io';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_win32.dart'
    show WindowControllerWin32;
import 'package:flutter/widgets.dart';

/// התנאי היחיד לכל מסלול ריבוי התצוגות (חלונות Dart באותו מנוע).
abstract final class MultiViewMode {
  static bool? _override;
  static bool _ownerInstalled = false;

  /// ב-Windows תמיד ריבוי תצוגות. Linux/macOS עדיין במודל A (מנוע לכל חלון).
  static bool get supported => Platform.isWindows;

  /// פעיל רק אחרי ש-[installWindowingOwner] התקין בעלים אמיתי.
  static bool get enabled => _override ?? (supported && _ownerInstalled);

  /// חלון נוסף הוא מנוע נוסף (מודל A). ב-Windows לעולם לא, גם בלי בעלים.
  static bool get usesEngineWindows => !(_override ?? supported);

  /// האם הותקן בעלים אמיתי לחלונות ה-Dart.
  static bool get ownerInstalled => _ownerInstalled;

  @visibleForTesting
  static set debugOverride(bool? value) => _override = value;

  @visibleForTesting
  static void debugResetOwnerInstalled() => _ownerInstalled = false;
}

/// מדליק את דגל החלונות של המסגרת רק למשך [body]. מחוץ לו הדגל כבוי, ולכן
/// `showDialog` נשאר בתוך התצוגה ו-`MaterialApp` אינו עוטף ב-`WindowManager`.
T withWindowing<T>(T Function() body) {
  final previous = features.isWindowingEnabled;
  features.isWindowingEnabled = true;
  try {
    return body();
  } finally {
    features.isWindowingEnabled = previous;
  }
}

/// פעם אחת, אחרי אתחול ה-binding ולפני פתיחת חלון ראשון. מחזיר אם הותקן.
bool installWindowingOwner() {
  if (MultiViewMode._ownerInstalled) return true;
  if (!MultiViewMode.supported || !hasRealPlatformDispatcher()) return false;
  withWindowing(
    () =>
        WidgetsBinding.instance.windowingOwner = createDefaultWindowingOwner(),
  );
  return MultiViewMode._ownerInstalled = true;
}

/// binding של בדיקות מחזיר engineId=1, והמנוע מפרש אותו כמצביע וקורס.
/// TODO(upstream): TestPlatformDispatcher.engineId; GetEngineForId בלי בדיקה.
@visibleForTesting
bool hasRealPlatformDispatcher() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  return identical(dispatcher, PlatformDispatcher.instance) &&
      dispatcher.engineId != null;
}

/// חלון נייטיב שנוצר מ-Dart. עוטף את הבקר הפנימי כדי שהוא לא ידלוף החוצה.
class ViewWindowHandle {
  ViewWindowHandle._(this._controller);

  @visibleForTesting
  ViewWindowHandle.forTesting(RegularWindowController controller)
    : _controller = controller;

  final RegularWindowController _controller;

  FlutterView get view => _controller.rootView;

  /// מודיע על שינוי גודל, הפעלה, כותרת ומגבלות; לא על הזזה בלבד.
  Listenable get changes => _controller;

  bool _destroyed = false;

  /// האם החלון כבר נהרס (WM_DESTROY).
  bool get isDestroyed => _destroyed;

  /// ה-HWND של החלון העליון; null מחוץ ל-Windows או אחרי ההריסה.
  int? get hwnd {
    final controller = _controller;
    if (_destroyed || controller is! WindowControllerWin32) return null;
    return (controller as WindowControllerWin32).windowHandle.address;
  }

  bool get isActivated => !_destroyed && _controller.isActivated;
  bool get isMaximized => !_destroyed && _controller.isMaximized;
  bool get isMinimized => !_destroyed && _controller.isMinimized;
  bool get isFullscreen => !_destroyed && _controller.isFullscreen;

  void setTitle(String title) {
    if (!_destroyed) _controller.setTitle(title);
  }

  void setMaximized(bool value) {
    if (!_destroyed) _controller.setMaximized(value);
  }

  void setMinimized(bool value) {
    if (!_destroyed) _controller.setMinimized(value);
  }

  void setFullscreen(bool value) {
    if (!_destroyed) _controller.setFullscreen(value);
  }

  void setMinimumSize(Size size) {
    if (_destroyed) return;
    _controller.setConstraints(
      BoxConstraints(minWidth: size.width, minHeight: size.height),
    );
  }

  /// מותר לקרוא כמה פעמים; `onDestroyed` נקרא כשהחלון באמת נהרס.
  void destroy() => _controller.destroy();

  /// אחרי WM_DESTROY: שאילתות מחזירות ערך ברירת מחדל ופעולות אינן עושות דבר.
  void markDestroyed() => _destroyed = true;

  void dispose() => _controller.dispose();
}

/// פותח חלון רגיל (את הכותרת מסיר ה-registry). מוסתר עד הפריים הראשון.
ViewWindowHandle createViewWindow({
  required Size size,
  required String title,
  required void Function(ViewWindowHandle handle) onCloseRequested,
  required void Function(ViewWindowHandle handle) onDestroyed,
}) {
  if (!MultiViewMode.ownerInstalled) {
    throw StateError('אין בעלים לחלונות Dart (installWindowingOwner לא הותקן)');
  }
  final delegate = _ViewWindowDelegate(onCloseRequested, onDestroyed);
  final controller = withWindowing(
    () => RegularWindowController(
      size: size,
      title: title,
      delegate: delegate,
    ),
  );
  return delegate.handle = ViewWindowHandle._(controller);
}

// בלי super: מימושי ברירת המחדל זורקים כשהדגל כבוי, והוא כבוי כשהודעה מגיעה.
class _ViewWindowDelegate extends RegularWindowControllerDelegate {
  _ViewWindowDelegate(this._onCloseRequested, this._onDestroyed);

  final void Function(ViewWindowHandle handle) _onCloseRequested;
  final void Function(ViewWindowHandle handle) _onDestroyed;
  late final ViewWindowHandle handle;

  @override
  void onWindowCloseRequested(RegularWindowController controller) =>
      _onCloseRequested(handle);

  @override
  void onWindowDestroyed() => _onDestroyed(handle);
}
