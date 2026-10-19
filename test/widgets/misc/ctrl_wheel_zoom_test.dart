import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/ctrl_wheel_zoom.dart';

void main() {
  late List<bool> zooms;
  late ScrollController scroll;

  Future<void> pumpZoom(WidgetTester tester) async {
    zooms = [];
    scroll = ScrollController(initialScrollOffset: 500);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CtrlWheelZoom(
          onZoom: zooms.add,
          child: ListView.builder(
            controller: scroll,
            itemCount: 100,
            itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
          ),
        ),
      ),
    );
  }

  Future<void> wheel(
    WidgetTester tester,
    double dy, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final pointer = TestPointer(1, kind);
    pointer.hover(tester.getCenter(find.byType(ListView)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('Ctrl + wheel zooms instead of scrolling', (tester) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    await wheel(tester, -100);
    await wheel(tester, 100);

    expect(zooms, [true, false]);
    expect(scroll.offset, 500);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('a notch of one line still makes one step', (tester) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    await wheel(tester, -100 / 3);

    expect(zooms, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('small pinch deltas add up to a step', (tester) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    for (var i = 0; i < 2; i++) {
      await wheel(tester, -10);
    }
    expect(zooms, isEmpty);
    await wheel(tester, -10);

    expect(zooms, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('the wheel without Ctrl scrolls as before', (tester) async {
    await pumpZoom(tester);

    await wheel(tester, 100);

    expect(zooms, isEmpty);
    expect(scroll.offset, 600);
  });

  testWidgets('Ctrl + Shift + wheel is left to the scrollable', (
    tester,
  ) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

    await wheel(tester, -100);

    expect(zooms, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });
}
