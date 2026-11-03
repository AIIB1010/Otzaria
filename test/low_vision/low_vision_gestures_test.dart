import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/view/lv_books_screen.dart';
import 'package:otzaria/low_vision/view/lv_gestures_screen.dart';
import 'package:otzaria/low_vision/view/lv_input_test_screen.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/low_vision/view/widgets/lv_touch_zones.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

import 'low_vision_test_harness.dart';

const _leftPoint = Offset(400, 540);
const _rightPoint = Offset(1500, 540);

LvZoneAction _action(List<String> events, String name) => LvZoneAction(
  label: name,
  icon: Icons.circle,
  onTriggered: () => events.add(name),
);

/// מציג אזורי מגע עם הפעולות המבוקשות; ברירת מחדל: שמאל, ימין והחזקה.
Future<List<String>> _pumpZones(
  WidgetTester tester, {
  Set<LvGesture> bind = const {
    LvGesture.doubleTapLeft,
    LvGesture.doubleTapRight,
    LvGesture.hold,
  },
}) async {
  final events = <String>[];
  await pumpLowVision(
    tester,
    Scaffold(
      body: LvTouchZones(
        holdDuration: const Duration(milliseconds: 900),
        actions: {
          for (final g in bind) g: _action(events, g.name),
        },
        child: const SizedBox.expand(),
      ),
    ),
  );
  return events;
}

Future<void> _tapFingers(WidgetTester tester, int fingers, Offset at) async {
  final gestures = <TestGesture>[];
  for (var i = 0; i < fingers; i++) {
    gestures.add(
      await tester.startGesture(at + Offset(i * 60.0, 0), pointer: 10 + i),
    );
  }
  await tester.pump(const Duration(milliseconds: 40));
  for (final g in gestures) {
    await g.up();
  }
}

void main() {
  group('מחוות מגע', () {
    testWidgets('נגיעה בודדת אינה עושה כלום', (tester) async {
      final events = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
    });

    testWidgets('לחיצה כפולה בצד שמאל וימין מפעילה את הצד הנכון', (
      tester,
    ) async {
      final events = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(_leftPoint + const Offset(10, 10));
      await tester.pump();
      expect(events, ['doubleTapLeft']);

      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(_rightPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(_rightPoint);
      await tester.pump();
      expect(events, ['doubleTapLeft', 'doubleTapRight']);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('שתי נגיעות בצדדים שונים אינן לחיצה כפולה', (tester) async {
      final events = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
    });

    testWidgets('נגיעות רחוקות בזמן אינן לחיצה כפולה', (tester) async {
      final events = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
    });

    testWidgets('החזקה ארוכה מפעילה, והחזקה קצרה לא', (tester) async {
      final events = await _pumpZones(tester);
      final short = await tester.startGesture(_leftPoint);
      await tester.pump(const Duration(milliseconds: 500));
      await short.up();
      await tester.pump();
      expect(events, isEmpty);

      final long = await tester.startGesture(_leftPoint);
      await tester.pump(); // הפריים הראשון מתחיל את הטיימר
      await tester.pump(const Duration(milliseconds: 1000));
      expect(events, ['hold']);
      await long.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('גרירה לכל כיוון (גם באלכסון, גם באיטיות) אינה מפעילה החזקה', (
      tester,
    ) async {
      final events = await _pumpZones(tester);
      final g = await tester.startGesture(_leftPoint);
      await tester.pump();
      // תזוזה קטנה מיד בתחילת המגע הופכת אותו לגרירה.
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(25, 18));
        await tester.pump(const Duration(milliseconds: 250));
      }
      // ועצירה ארוכה באמצע הגרירה, כשהעמוד "תפוס", אינה החזקה.
      await tester.pump(const Duration(seconds: 3));
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
    });

    testWidgets('אצבע שנחה ואז זזה מבטלת את ההחזקה', (tester) async {
      final events = await _pumpZones(tester);
      final g = await tester.startGesture(_leftPoint);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await g.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(events, isEmpty);
      await g.up();
      await tester.pump();
    });

    testWidgets('שתי אצבעות: נגיעה מופעלת מיד כשאין מחווה כפולה', (
      tester,
    ) async {
      final events = await _pumpZones(
        tester,
        bind: {LvGesture.twoFingerTap},
      );
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump();
      expect(events, ['twoFingerTap']);
    });

    testWidgets('שתי אצבעות: עם מחווה כפולה, בודדת מופעלת רק אחרי ההמתנה', (
      tester,
    ) async {
      final events = await _pumpZones(
        tester,
        bind: {LvGesture.twoFingerTap, LvGesture.twoFingerDoubleTap},
      );
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump(const Duration(milliseconds: 200));
      expect(events, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(events, ['twoFingerTap']);

      events.clear();
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(events, ['twoFingerDoubleTap']);
    });

    testWidgets('שלוש אצבעות: נגיעה ולחיצה כפולה', (tester) async {
      final events = await _pumpZones(
        tester,
        bind: {LvGesture.threeFingerTap, LvGesture.threeFingerDoubleTap},
      );
      await _tapFingers(tester, 3, _rightPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await _tapFingers(tester, 3, _rightPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(events, ['threeFingerDoubleTap']);

      events.clear();
      await _tapFingers(tester, 3, _rightPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(events, ['threeFingerTap']);
    });

    testWidgets('צביטה (שתי אצבעות שזזות) אינה נגיעה בשתי אצבעות', (
      tester,
    ) async {
      final events = await _pumpZones(
        tester,
        bind: {LvGesture.twoFingerTap, LvGesture.twoFingerDoubleTap},
      );
      final a = await tester.startGesture(_leftPoint, pointer: 1);
      final b = await tester.startGesture(
        _leftPoint + const Offset(80, 0),
        pointer: 2,
      );
      await tester.pump(const Duration(milliseconds: 40));
      await a.moveBy(const Offset(-120, 0));
      await b.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 40));
      await a.up();
      await b.up();
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
    });

    testWidgets('מחווה ללא שיוך אינה מופעלת', (tester) async {
      final events = await _pumpZones(tester, bind: {});
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_leftPoint);
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump(const Duration(seconds: 2));
      expect(events, isEmpty);
    });
  });

  group('דפדוף בקורא', () {
    final lines = [for (var i = 0; i < 80; i++) 'שורה מספר $i בספר'];

    Future<LvHarness> openReader(WidgetTester tester) async {
      final h = await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'ספר'),
          loadText: () async => lines.join('\n'),
          loadToc: () async => const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      return h;
    }

    double? topOfFirst(WidgetTester tester) {
      final f = find.text('שורה מספר 0 בספר');
      return f.evaluate().isEmpty ? null : tester.getTopLeft(f).dy;
    }

    testWidgets('נגיעה בודדת על הטקסט לא מדפדפת ולא מסתירה סרגלים', (
      tester,
    ) async {
      await openReader(tester);
      final before = topOfFirst(tester);
      await tester.tapAt(_leftPoint);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(topOfFirst(tester), before);
      expect(find.text('חזרה'), findsOneWidget);
    });

    testWidgets('לחיצה כפולה בצד שמאל מדפדפת קדימה', (tester) async {
      await openReader(tester);
      final before = topOfFirst(tester)!;
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(_leftPoint);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final after = topOfFirst(tester);
      expect(after == null || after < before - 300, isTrue);
    });

    testWidgets('שיוך מחדש של המחוות משנה את כיוון הדפדוף', (tester) async {
      final h = await openReader(tester);
      h.cubit.setTouchBinding(
        LvGesture.doubleTapLeft,
        LvTouchAction.previousPage,
      );
      h.cubit.setTouchBinding(LvGesture.doubleTapRight, LvTouchAction.nextPage);
      await tester.pump();
      final before = topOfFirst(tester)!;
      // שמאל = הקודם עכשיו, ובתחילת הספר אין לאן לחזור.
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(_leftPoint);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(topOfFirst(tester), before);

      await tester.tapAt(_rightPoint);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(_rightPoint);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final after = topOfFirst(tester);
      expect(after == null || after < before - 300, isTrue);
    });

    testWidgets('לחיצה כפולה בשתי אצבעות מגדילה את הטקסט (ברירת מחדל)', (
      tester,
    ) async {
      final h = await openReader(tester);
      final before = h.cubit.state.textScale;
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await _tapFingers(tester, 2, _leftPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(h.cubit.state.textScale, greaterThan(before));
    });
  });

  group('סימון פריט ברשימה', () {
    Color? rowColor(WidgetTester tester) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(LvRow).first,
                matching: find.byType(Material),
              )
              .first,
        )
        .color;

    testWidgets('אין פריט מסומן כברירת מחדל, ורק מקלדת מסמנת', (tester) async {
      await pumpLowVision(
        tester,
        const LvBooksScreen(),
        setup: (c) {
          c.noteOpened(TextBook(title: 'א'));
          c.noteOpened(TextBook(title: 'ב'));
        },
      );
      await tester.pump();
      final plain = rowColor(tester);
      expect(plain, const Color(0xFFEDEDED));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(rowColor(tester), const Color(0xFF000000));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('בדיקת כפתורי המכשיר', () {
    testWidgets('מציגה מקש, גלגלת וכפתור חזרה של המכשיר', (tester) async {
      await pumpLowVision(tester, const LvInputTestScreen());
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pump();
      expect(find.textContaining('מקש: F9'), findsOneWidget);

      final mouse = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(500, 500)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
      await tester.pump();
      expect(find.textContaining('גלגלת: אנכי 40.0'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('כפתור חזרה של המכשיר נקלט'), findsOneWidget);
    });

    testWidgets('כפתור יציאה סוגר את המסך וחוזר למסך הקודם', (tester) async {
      await pumpLowVision(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => lvPush<void>(context, const LvInputTestScreen()),
              child: const Text('פתח'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      expect(find.text('בדיקת כפתורים'), findsOneWidget);

      await tester.tap(find.text('יציאה'));
      await tester.pumpAndSettle();
      expect(find.text('פתח'), findsOneWidget);
      expect(find.text('בדיקת כפתורים'), findsNothing);
    });
  });

  group('מסך הגדרת מחוות', () {
    testWidgets('בחירת פעולה למחווה נשמרת ומוצגת', (tester) async {
      final h = await pumpLowVision(tester, const LvGesturesScreen());
      await tester.pump();
      expect(h.cubit.state.actionFor(LvGesture.hold), LvTouchAction.back);

      await tester.scrollUntilVisible(
        find.text('החזקה ארוכה (אצבע אחת, בלי לזוז)'),
        300,
      );
      await tester.tap(find.text('החזקה ארוכה (אצבע אחת, בלי לזוז)'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('מסך הבית'), 300);
      await tester.tap(find.text('מסך הבית'));
      await tester.pumpAndSettle();

      expect(h.cubit.state.actionFor(LvGesture.hold), LvTouchAction.home);
      await tester.scrollUntilVisible(find.text('מסך הבית'), 300);
      expect(find.text('מסך הבית'), findsOneWidget);

      await tester.scrollUntilVisible(find.textContaining('איפוס מחוות'), 300);
      await tester.tap(find.textContaining('איפוס מחוות'));
      await tester.pump();
      expect(h.cubit.state.actionFor(LvGesture.hold), LvTouchAction.back);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('זמן ההחזקה והחלקת העמוד ניתנים לשינוי', (tester) async {
      final h = await pumpLowVision(tester, const LvGesturesScreen());
      await tester.pump();
      expect(h.cubit.state.holdSeconds, 1.2);
      await tester.scrollUntilVisible(find.textContaining('זמן החזקה'), 300);
      await tester.tap(find.textContaining('זמן החזקה'));
      await tester.pump();
      expect(h.cubit.state.holdSeconds, 1.8);

      await tester.scrollUntilVisible(find.textContaining('העמוד נעצר'), 300);
      await tester.tap(find.textContaining('העמוד נעצר'));
      await tester.pump();
      expect(h.cubit.state.glide, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
