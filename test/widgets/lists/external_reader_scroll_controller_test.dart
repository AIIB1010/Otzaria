import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('native navigation resumes after detaching the external reader', (
    tester,
  ) async {
    final lines = LineScrollController();
    addTearDown(lines.dispose);
    final external = <int>[];
    var jumps = 0;
    lines.addBeforeJumpListener(() => jumps++);
    lines.externalNavigator = (line) async => external.add(line);
    expect(lines.isAttached, isTrue);
    await lines.jumpToLine(23);
    await lines.scrollToLine(31);
    expect(external, [23, 31]);
    expect(jumps, 2);
    expect(lines.position.value?.topLine, 31);

    lines.externalNavigator = null;
    expect(lines.isAttached, isFalse);
    final segments = buildReadingSegments(
      List.filled(100, 'שורה'),
      continuous: false,
    );
    lines.attach(
      ReadingViewportBinding(
        segments: () => segments,
        viewportExtent: () => 600,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollablePositionedList.builder(
          itemScrollController: lines.itemController,
          itemPositionsListener: lines.positionsListener,
          scrollOffsetController: lines.offsetController,
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$i')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final navigation = lines.jumpToLine(12);
    await tester.pumpAndSettle();
    await navigation;
    expect(lines.position.value?.topLine, 12);
    expect(external, [23, 31]);
    expect(jumps, greaterThan(2));
  });
}
