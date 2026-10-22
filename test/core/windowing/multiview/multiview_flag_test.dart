import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    MultiViewMode.debugOverride = false;
    MultiViewMode.debugResetOwnerInstalled();
  });

  test('ברירת המחדל של הבנייה היא ריבוי תצוגות; רק Windows נתמך', () {
    // הבדיקות רצות בלי OTZARIA_MULTIVIEW, כלומר עם ברירת המחדל.
    expect(kMultiView, isTrue);
    expect(MultiViewMode.supported, Platform.isWindows);
  });

  test('binding של בדיקות: הבעלים לא מותקן והמצב נשאר מודל A', () {
    MultiViewMode.debugOverride = null;

    expect(hasRealPlatformDispatcher(), isFalse);
    expect(installWindowingOwner(), isFalse);
    expect(MultiViewMode.ownerInstalled, isFalse);
    expect(MultiViewMode.enabled, isFalse);
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
    MultiViewMode.debugOverride = false;
    expect(MultiViewMode.enabled, isFalse);
  });
}
