import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_virtual_window_frame.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multiview/host_window_app_window_controller.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:window_manager/window_manager.dart' show ResizeEdge;

import '../../test_helpers/fake_view_window.dart';
import '../../test_helpers/second_test_view.dart';

void main() {
  late StubWindowController stub;
  late FakeViewWindowNative native;

  Future<void> pumpFrame(WidgetTester tester, {Key? childKey}) async {
    stub = StubWindowController(SecondTestView(tester.view));
    native = FakeViewWindowNative();
    final window = HostWindowAppWindowController(
      id: const AppWindowId('window-view-2'),
      handle: StubWindowHandle(stub, (_) {}, fakeHwnd: 5),
      onClose: () async {},
      native: native,
    );
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        role: const AppWindowRole.view(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AppVirtualWindowFrame(child: _Counter(key: childKey)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('הקצה העליון משנה את גודל החלון הזה, והפינות לפי המסך', (
    tester,
  ) async {
    await pumpFrame(tester);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    await tester.dragFrom(const Offset(2, 2), const Offset(0, 60));
    await tester.dragFrom(Offset(width / 2, 2), const Offset(0, 60));
    await tester.dragFrom(Offset(width - 2, 2), const Offset(0, 60));
    expect(native.resized, [
      (5, ResizeEdge.topLeft),
      (5, ResizeEdge.top),
      (5, ResizeEdge.topRight),
    ]);

    // מתחת לפס הלחיצה מגיעה לתוכן.
    await tester.dragFrom(Offset(width / 2, 40), const Offset(0, 60));
    expect(native.resized, hasLength(3));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('בלי פסים כשהחלון ממוקסם, והתוכן אינו נבנה מחדש', (tester) async {
    final childKey = GlobalKey<_CounterState>();
    await pumpFrame(tester, childKey: childKey);
    final state = childKey.currentState;

    stub.maximized = true;
    stub.notify();
    // המצב נשאל אסינכרונית, וה-setState נבנה בפריים שאחריו.
    await tester.pump();
    await tester.pump();
    await tester.dragFrom(const Offset(400, 2), const Offset(0, 60));
    expect(native.resized, isEmpty);
    expect(childKey.currentState, same(state));

    stub.maximized = false;
    stub.notify();
    // המצב נשאל אסינכרונית, וה-setState נבנה בפריים שאחריו.
    await tester.pump();
    await tester.pump();
    await tester.dragFrom(const Offset(400, 2), const Offset(0, 60));
    expect(native.resized, [(5, ResizeEdge.top)]);
    expect(childKey.currentState, same(state));
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('חלון בלי שינוי גודל משלו מקבל את התוכן כמו שהוא', (
    tester,
  ) async {
    await tester.pumpWidget(
      const AppWindowScope(
        controller: WindowManagerAppWindowController(),
        geometry: WindowManagerAppWindowController(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AppVirtualWindowFrame(child: SizedBox.expand()),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(AppVirtualWindowFrame),
        matching: find.byType(MouseRegion),
      ),
      findsNothing,
    );
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
