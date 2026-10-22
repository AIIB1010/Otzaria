import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';

import '../../../test_helpers/fake_view_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    MultiViewMode.debugOverride = false;
    MultiViewMode.debugResetOwnerInstalled();
  });

  test('רק Windows נתמך, ושם אין מנוע לכל חלון', () {
    MultiViewMode.debugOverride = null;
    expect(MultiViewMode.supported, Platform.isWindows);
    expect(MultiViewMode.usesEngineWindows, !Platform.isWindows);
  });

  test('binding של בדיקות: הבעלים לא מותקן וריבוי התצוגות כבוי', () {
    MultiViewMode.debugOverride = null;

    expect(hasRealPlatformDispatcher(), isFalse);
    expect(installWindowingOwner(), isFalse);
    expect(MultiViewMode.ownerInstalled, isFalse);
    expect(MultiViewMode.enabled, isFalse);
    // גם בלי בעלים, Windows אינו חוזר למנוע לכל חלון.
    expect(MultiViewMode.usesEngineWindows, !Platform.isWindows);
  });

  test('בלי בעלים, יצירת חלון נכשלת בשגיאת Dart ולא בקריסה נייטיבית', () {
    expect(
      () => createViewWindow(
        size: const Size(800, 600),
        title: 't',
        onCloseRequested: (_) {},
        onDestroyed: (_) {},
      ),
      throwsStateError,
    );
  });

  test('debugOverride גובר על מצב הבעלים', () {
    MultiViewMode.debugOverride = true;
    expect(MultiViewMode.enabled, isTrue);
    expect(MultiViewMode.usesEngineWindows, isFalse);
    MultiViewMode.debugOverride = false;
    expect(MultiViewMode.enabled, isFalse);
    expect(MultiViewMode.usesEngineWindows, isTrue);
  });

  test('nativeHandle: בקר שאינו נייטיב או חלון שנהרס מחזירים null', () {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    final handle = ViewWindowHandle.forTesting(StubWindowController(view));
    expect(handle.nativeHandle, isNull);
    expect(handle.hwnd, isNull);
    handle.markDestroyed();
    expect(handle.nativeHandle, isNull);
  });

  test('ViewWindowNative.platform: win32 ב-Windows', () {
    final native = ViewWindowNative.platform();
    if (Platform.isWindows) expect(native, isA<Win32ViewWindowNative>());
  });
}
