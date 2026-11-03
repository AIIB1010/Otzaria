import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/view/lv_books_screen.dart';
import 'package:otzaria/low_vision/view/lv_input_test_screen.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/low_vision/view/widgets/lv_touch_zones.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

import 'low_vision_test_harness.dart';

const _leftPoint = Offset(400, 540);
const _rightPoint = Offset(1500, 540);

Future<({List<String> events})> _pumpZones(WidgetTester tester) async {
  final events = <String>[];
  await pumpLowVision(
    tester,
    Scaffold(
      body: LvTouchZones(
        left: LvZoneAction(
          label: 'הבא',
          icon: Icons.arrow_downward,
          onTriggered: () => events.add('left'),
        ),
        right: LvZoneAction(
          label: 'הקודם',
          icon: Icons.arrow_upward,
          onTriggered: () => events.add('right'),
        ),
        onHoldBack: () => events.add('back'),
        child: const SizedBox.expand(),
      ),
    ),
  );
  return (events: events);
}

void main() {
  group('מחוות מגע', () {
    testWidgets('נגיעה בודדת אינה עושה כלום', (tester) async {
      final z = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(z.events, isEmpty);
    });

    testWidgets('לחיצה כפולה בצד שמאל וימין מפעילה את הצד הנכון', (
      tester,
    ) async {
      final z = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(_leftPoint + const Offset(10, 10));
      await tester.pump();
      expect(z.events, ['left']);

      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(_rightPoint);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(_rightPoint);
      await tester.pump();
      expect(z.events, ['left', 'right']);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('שתי נגיעות בצדדים שונים אינן לחיצה כפולה', (tester) async {
      final z = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(z.events, isEmpty);
    });

    testWidgets('נגיעות רחוקות בזמן אינן לחיצה כפולה', (tester) async {
      final z = await _pumpZones(tester);
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(seconds: 1));
      expect(z.events, isEmpty);
    });

    testWidgets('החזקה ארוכה חוזרת אחורה, והחזקה קצרה לא', (tester) async {
      final z = await _pumpZones(tester);
      final short = await tester.startGesture(_leftPoint);
      await tester.pump(const Duration(milliseconds: 500));
      await short.up();
      await tester.pump();
      expect(z.events, isEmpty);

      final long = await tester.startGesture(_leftPoint);
      await tester.pump(); // הפריים הראשון מתחיל את הטיימר
      await tester.pump(const Duration(milliseconds: 1000));
      expect(z.events, ['back']);
      await long.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('כף יד או אף (שתי נגיעות יחד) מבטלים את המחוות', (
      tester,
    ) async {
      final z = await _pumpZones(tester);
      final a = await tester.startGesture(_leftPoint);
      final b = await tester.startGesture(_rightPoint);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(z.events, isEmpty);
      await a.up();
      await b.up();

      await tester.tapAt(_leftPoint);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_leftPoint);
      await tester.pump();
      expect(z.events, ['left']);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('תנועה גדולה באמצע ההחזקה מבטלת את החזרה', (tester) async {
      final z = await _pumpZones(tester);
      final g = await tester.startGesture(_leftPoint);
      await tester.pump(const Duration(milliseconds: 300));
      await g.moveBy(const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(z.events, isEmpty);
      await g.up();
      await tester.pump();
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

    testWidgets('הגדרת החלפת הצדדים הופכת את כיוון הדפדוף', (tester) async {
      final h = await openReader(tester);
      h.cubit.setSwapTapSides(true);
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
}
