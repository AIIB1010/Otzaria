import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_extent_estimates.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/widgets/reading_extent_estimation.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('מסיר רק סימנים משולבים ומשאיר פיסוק עברי', () {
    expect(visibleReadingCharCount('אַ֑ב־ג׀ד׃ה׆ו'), 'אב־ג׀ד׃ה׆ו'.length);
    expect(visibleReadingCharCount('e\u0301'), 1);
    expect(visibleReadingCharCount('😀'), 1);
  });

  test('מפענח ישויות אחרי הסרת תגיות ומסתיר גוף הערות', () {
    expect(visibleReadingCharCount('&amp;&#x5BE;&#1472;&nbsp;&lt;b&gt;'), 7);
    expect(
      visibleReadingCharCount(
        'אב<sup class="footnote-marker">א</sup>'
        '<i class="footnote">${'גוף הערה ארוך ' * 1000}</i>גד',
      ),
      5,
    );
    expect(visibleReadingCharCount('<b>אב</b><span>גד</span>'), 4);
  });

  test('מידות השורות ורוחב העמודה משפיעים על ההערכה', () {
    final segments = _segments(['א' * 1000]);
    final full = readingExtentEstimator(
      segments,
      20,
      lineHeight: 1,
      verticalPadding: 0,
    );
    final narrow = readingExtentEstimator(
      segments,
      20,
      lineHeight: 2,
      contentWidthRatio: 0.5,
      verticalPadding: 0,
    );
    expect(narrow(0, 300), closeTo(full(0, 300) * 4, 40));
    expect(segments.debugBuiltCount, 0);
  });

  test('דלתאות רציפות ממוזגות ומעדכנות רק את שורותיהן', () async {
    final identity = Object();
    final content = List<String>.filled(20000, 'אבגד');
    var snapshot = _segments(content, identity: identity, version: 1);
    final data = ReadingExtentEstimates(snapshot);
    await data.refresh();
    expect(data.debugCountedLines, 20000);
    expect(data.debugStorageBytes, 80000);
    final firstContent = List<String>.of(content)..[7000] = 'א' * 1000;
    snapshot = _segments(
      firstContent,
      identity: identity,
      version: 2,
      changes: ContentLineChanges(
        fromVersion: 1,
        ranges: [(first: 7000, last: 7001)],
      ),
    );
    data.update(snapshot);
    final secondContent = List<String>.of(firstContent)..[7002] = 'א' * 2000;
    snapshot = _segments(
      secondContent,
      identity: identity,
      version: 3,
      changes: ContentLineChanges(
        fromVersion: 2,
        ranges: [(first: 7001, last: 7002)],
      ),
    );
    data.update(snapshot);
    final changed = await data.refresh();
    expect(changed.full, isFalse);
    expect(changed.ranges, [(first: 7000, last: 7002)]);
    expect(data.debugCountedLines, 20003);
    expect(data.debugStorageBytes, 80000);
    const metrics = ReadingExtentMetrics(lineExtent: 20, charWidth: 10);
    expect(data.estimate(7002, 100, metrics), 4004);
    expect(data.estimate(7000, 100, metrics), 2004);
    expect(snapshot.debugBuiltCount, 0);
  });

  test('טעינה תוך כדי ספירה ברקע אינה מאבדת דלתא', () async {
    final identity = Object();
    final original = _segments(
      List.filled(20000, 'אב'),
      identity: identity,
      version: 1,
    );
    final data = ReadingExtentEstimates(original);
    final refresh = data.refresh();
    final next = List<String>.of(original.content)..[18000] = 'א' * 3000;
    data.update(
      _segments(
        next,
        identity: identity,
        version: 2,
        changes: ContentLineChanges(
          fromVersion: 1,
          ranges: [(first: 18000, last: 18000)],
        ),
      ),
    );
    final result = await refresh;
    expect(result.full, isTrue);
    expect(data.debugCountedLines, 20001);
    expect(
      data.estimate(
        18000,
        100,
        const ReadingExtentMetrics(lineExtent: 20, charWidth: 10),
      ),
      6004,
    );
  });

  test('גרסה שדולגה וספר אחר מחייבים רענון מלא', () async {
    final identity = Object();
    final before = _segments(
      List.filled(20, 'אב'),
      identity: identity,
      version: 1,
    );
    final data = ReadingExtentEstimates(before);
    await data.refresh();
    final after = _segments(
      List.filled(20, 'אבגד'),
      identity: identity,
      version: 3,
      changes: ContentLineChanges(
        fromVersion: 2,
        ranges: [(first: 1, last: 1)],
      ),
    );
    expect(after.changedLinesSince(before), isNull);
    data.update(after);
    expect((await data.refresh()).full, isTrue);
    expect(data.debugCountedLines, 40);
    final other = _segments(
      after.content,
      identity: Object(),
      version: 4,
      changes: ContentLineChanges(
        fromVersion: 3,
        ranges: [(first: 0, last: 0)],
      ),
    );
    expect(other.changedLinesSince(after), isNull);
  });

  testWidgets('חימום מעדכן פריט רחוק בלי key חדש ובלי לבנותו', (tester) async {
    final identity = Object();
    final controller = ItemScrollController();
    final content = List<String>.filled(1000, '');
    content[0] = 'אבגד' * 30;
    var snapshot = _segments(
      content,
      flags: [true, ...List<bool>.filled(999, false)],
      identity: identity,
      version: 1,
    );
    late StateSetter rebuild;
    Object? latestKey;
    ItemExtentEstimator? latestEstimator;
    double? nativeWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return SizedBox(
              width: 400,
              height: 600,
              child: ReadingExtentEstimation(
                segments: snapshot,
                controller: controller,
                fontSize: 20,
                builder: (estimator, key) {
                  latestKey = key;
                  latestEstimator = estimator;
                  return ScrollablePositionedList.builder(
                    itemCount: 1000,
                    itemScrollController: controller,
                    estimateExtent: (index, width) {
                      nativeWidth = width;
                      return estimator(index, width);
                    },
                    estimationKey: key,
                    padding: const EdgeInsets.symmetric(horizontal: 17),
                    itemBuilder: (_, index) =>
                        SizedBox(key: ValueKey(index), height: 100),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final key = latestKey;
    final before = controller.listController!.extentForIndex(500).$1;
    rebuild(() {
      final next = List<String>.of(content)..[500] = 'א' * 5000;
      final flags = List<bool>.of(snapshot.loadedLineFlags!)..[500] = true;
      snapshot = _segments(
        next,
        flags: flags,
        identity: identity,
        version: 2,
        changes: ContentLineChanges(
          fromVersion: 1,
          ranges: [(first: 500, last: 500)],
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(latestKey, same(key));
    expect(
      controller.listController!.extentForIndex(500).$1,
      greaterThan(before * 10),
    );
    expect(
      controller.listController!.extentForIndex(500).$1,
      closeTo(latestEstimator!(500, nativeWidth!), 0.001),
    );
    expect(find.byKey(const ValueKey(500)), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

ReadingSegments _segments(
  List<String> content, {
  Object? identity,
  int version = 0,
  ContentLineChanges? changes,
  List<bool>? flags,
}) => ReadingSegments(
  layout: ReadingLayout.identity(content.length),
  content: content,
  loadedLineFlags: flags,
  readerIdentity: identity,
  contentVersion: version,
  contentChanges: changes,
);
