import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_contact_filter.dart';
import 'package:otzaria/low_vision/view/lv_contact_screen.dart';
import 'package:otzaria/low_vision/view/lv_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'low_vision_test_harness.dart';

PointerData _touch(
  PointerChange change, {
  int device = 1,
  double radius = 0,
  double size = 0,
}) => PointerData(
  timeStamp: Duration.zero,
  change: change,
  kind: PointerDeviceKind.touch,
  device: device,
  radiusMajor: radius,
  size: size,
);

List<PointerChange> _changes(PointerDataPacket packet) => [
  for (final d in packet.data) d.change,
];

void main() {
  group('מסנן נגיעות גדולות', () {
    test('נגיעת אצבע עוברת, נגיעה גדולה נזרקת עד ההרמה', () {
      final filter = LvContactFilter()..maxSize = 30;
      addTearDown(filter.dispose);

      final finger = filter.filter(
        PointerDataPacket(
          data: [
            _touch(PointerChange.down, radius: 20),
            _touch(PointerChange.up, radius: 20),
          ],
        ),
      );
      expect(_changes(finger), [PointerChange.down, PointerChange.up]);

      final nose = filter.filter(
        PointerDataPacket(
          data: [
            _touch(PointerChange.down, radius: 80),
            _touch(PointerChange.move, radius: 80),
            _touch(PointerChange.up, radius: 80),
          ],
        ),
      );
      expect(nose.data, isEmpty);
      expect(filter.rejectedCount.value, 1);
      expect(filter.last.value!.rejected, isTrue);

      // אחרי ההרמה נגיעת אצבע חדשה עוברת כרגיל.
      final next = filter.filter(
        PointerDataPacket(data: [_touch(PointerChange.down, radius: 20)]),
      );
      expect(_changes(next), [PointerChange.down]);
    });

    test('אצבע שנוגעת בזמן שהאף נוגע לא נפגעת', () {
      final filter = LvContactFilter()..maxSize = 30;
      addTearDown(filter.dispose);
      final result = filter.filter(
        PointerDataPacket(
          data: [
            _touch(PointerChange.down, device: 1, radius: 90),
            _touch(PointerChange.down, device: 2, radius: 20),
            _touch(PointerChange.move, device: 1, radius: 90),
            _touch(PointerChange.move, device: 2, radius: 20),
            _touch(PointerChange.up, device: 2, radius: 20),
            _touch(PointerChange.up, device: 1, radius: 90),
          ],
        ),
      );
      expect(_changes(result), [
        PointerChange.down,
        PointerChange.move,
        PointerChange.up,
      ]);
    });

    test('בלי גבול, או בזמן כיול, הכול עובר', () {
      final filter = LvContactFilter();
      addTearDown(filter.dispose);
      final big = PointerDataPacket(
        data: [_touch(PointerChange.down, radius: 500)],
      );
      expect(filter.filter(big).data, hasLength(1));
      filter
        ..maxSize = 30
        ..measureOnly = true;
      expect(filter.filter(big).data, hasLength(1));
      expect(filter.last.value!.size, 500);
    });

    test('כשאין רדיוס משתמשים ב-size', () {
      final filter = LvContactFilter()..maxSize = 0.3;
      addTearDown(filter.dispose);
      final result = filter.filter(
        PointerDataPacket(data: [_touch(PointerChange.down, size: 0.9)]),
      );
      expect(result.data, isEmpty);
    });

    test('עטיפת קבלת האירועים של המערכת ושחזורה', () {
      final dispatcher = PlatformDispatcher.instance;
      final saved = dispatcher.onPointerDataPacket;
      addTearDown(() => dispatcher.onPointerDataPacket = saved);
      final received = <PointerDataPacket>[];
      dispatcher.onPointerDataPacket = received.add;

      final filter = LvContactFilter()..maxSize = 30;
      filter.install();
      dispatcher.onPointerDataPacket!(
        PointerDataPacket(data: [_touch(PointerChange.down, radius: 90)]),
      );
      expect(received, isEmpty);
      dispatcher.onPointerDataPacket!(
        PointerDataPacket(data: [_touch(PointerChange.down, radius: 10)]),
      );
      expect(received, hasLength(1));

      filter.dispose();
      expect(dispatcher.onPointerDataPacket, received.add);
    });
  });

  test('הכיול והרמה נשמרים, והגבול נגזר מהאצבע', () async {
    SharedPreferences.setMockInitialValues({});
    final cubit = LowVisionCubit();
    await cubit.load();
    expect(cubit.state.maxContactSize, 0);
    cubit
      ..setFingerSize(20)
      ..setContactReject(3);
    await cubit.flush();
    await cubit.close();

    final again = LowVisionCubit();
    await again.load();
    addTearDown(again.close);
    expect(again.state.fingerSize, 20);
    expect(
      again.state.maxContactSize,
      20 * LowVisionState.contactRejectFactors[3],
    );
    again.setContactReject(0);
    expect(again.state.maxContactSize, 0);
  });

  group('מסך הכיול', () {
    testWidgets('שש נגיעות נמדדות והגדולה שבהן נשמרת', (tester) async {
      final harness = await pumpLowVision(tester, const LvContactScreen());
      await tester.tap(find.text('התחל כיול'));
      await tester.pump();
      for (final size in [18.0, 22.0, 20.0, 25.0, 19.0, 21.0]) {
        harness.contacts.last.value = LvContactSample(
          size: size,
          rejected: false,
        );
        await tester.pump();
      }
      expect(harness.cubit.state.fingerSize, 25);
      expect(find.textContaining('הכיול נשמר'), findsOneWidget);
      expect(harness.contacts.measureOnly, isFalse);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('מסך שלא מדווח גודל: אומרים את זה ולא שומרים', (tester) async {
      final harness = await pumpLowVision(tester, const LvContactScreen());
      await tester.tap(find.text('התחל כיול'));
      await tester.pump();
      harness.contacts.last.value = const LvContactSample(
        size: 0,
        rejected: false,
      );
      await tester.pump();
      expect(find.textContaining('לא מדווח על גודל'), findsOneWidget);
      expect(harness.cubit.state.fingerSize, 0);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('נגיעה שנדחתה מוצגת כנדחתה', (tester) async {
      final harness = await pumpLowVision(tester, const LvContactScreen());
      harness.contacts.last.value = const LvContactSample(
        size: 90,
        rejected: true,
      );
      await tester.pump();
      expect(find.textContaining('נדחתה'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('בהגדרות אפשר לשנות את רמת הדחייה ולפתוח את הכיול', (
    tester,
  ) async {
    final harness = await pumpLowVision(tester, const LvSettingsScreen());
    await tester.pump();
    final level = find.textContaining('דחיית נגיעות גדולות');
    await tester.scrollUntilVisible(level, 300);
    await tester.pumpAndSettle();
    final before = harness.cubit.state.contactRejectIndex;
    await tester.tap(level);
    await tester.pump();
    expect(harness.cubit.state.contactRejectIndex, (before + 1) % 4);

    final calibrate = find.textContaining('כיול נגיעות ובדיקה');
    await tester.scrollUntilVisible(calibrate, 300);
    await tester.pumpAndSettle();
    await tester.tap(calibrate);
    await tester.pumpAndSettle();
    expect(find.text('התחל כיול'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
