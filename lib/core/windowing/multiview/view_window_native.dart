import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// מה שחלון Dart צריך מהמערכת ואין לו בבקר של המסגרת. הכול בפיקסלים פיזיים.
abstract interface class ViewWindowNative {
  /// מלבן החלון כולו (כולל המסגרת); null כשאינו זמין.
  Rect? windowRect(int hwnd);
  void setWindowRect(int hwnd, Rect rect);
  bool isVisible(int hwnd);
  void show(int hwnd);

  /// מביא לחזית בלי לשנות את מצב ה-maximize.
  void focus(int hwnd);
  void startDragging(int hwnd);

  /// אזור העבודה של המסך שהחלון עליו.
  Rect? workArea(int hwnd);

  /// תיקוני הקלט של ה-runner (#1441, #1645) לתצוגה של החלון.
  Future<void> installViewHooks(int hwnd);
}

/// המימוש האמיתי: win32 ישירות, והערוץ של ה-runner להתקנת התיקונים.
class Win32ViewWindowNative implements ViewWindowNative {
  const Win32ViewWindowNative();

  static const MethodChannel _channel = MethodChannel('otzaria/multiwindow');

  static HWND _h(int hwnd) => HWND(Pointer.fromAddress(hwnd));

  static Rect _rect(RECT r) => Rect.fromLTRB(
    r.left.toDouble(),
    r.top.toDouble(),
    r.right.toDouble(),
    r.bottom.toDouble(),
  );

  @override
  Rect? windowRect(int hwnd) {
    final rect = calloc<RECT>();
    try {
      if (!GetWindowRect(_h(hwnd), rect).value) return null;
      return _rect(rect.ref);
    } finally {
      calloc.free(rect);
    }
  }

  @override
  void setWindowRect(int hwnd, Rect rect) {
    SetWindowPos(
      _h(hwnd),
      null,
      rect.left.round(),
      rect.top.round(),
      rect.width.round(),
      rect.height.round(),
      SET_WINDOW_POS_FLAGS(SWP_NOZORDER | SWP_NOACTIVATE),
    );
  }

  @override
  bool isVisible(int hwnd) => IsWindowVisible(_h(hwnd));

  @override
  void show(int hwnd) => ShowWindow(_h(hwnd), SW_SHOW);

  @override
  void focus(int hwnd) => SetForegroundWindow(_h(hwnd));

  @override
  void startDragging(int hwnd) {
    // כמו window_manager: לולאת ההזזה של המערכת, כאילו נלחצה הכותרת.
    ReleaseCapture();
    PostMessage(
      _h(hwnd),
      WM_NCLBUTTONDOWN,
      const WPARAM(HTCAPTION),
      const LPARAM(0),
    );
  }

  @override
  Rect? workArea(int hwnd) {
    final monitor = MonitorFromWindow(_h(hwnd), MONITOR_DEFAULTTONEAREST);
    final info = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
    try {
      if (!GetMonitorInfo(monitor, info)) return null;
      return _rect(info.ref.rcWork);
    } finally {
      calloc.free(info);
    }
  }

  @override
  Future<void> installViewHooks(int hwnd) async {
    if (!Platform.isWindows) return;
    try {
      final installed = await _channel.invokeMethod<bool>(
        'installViewHooks',
        {'hwnd': hwnd},
      );
      if (installed != true) debugPrint('installViewHooks: not installed');
    } catch (e) {
      // החלון עובד גם בלי התיקונים; רק מגע ו-Shift תקוע חוזרים.
      debugPrint('installViewHooks failed: $e');
    }
  }
}
