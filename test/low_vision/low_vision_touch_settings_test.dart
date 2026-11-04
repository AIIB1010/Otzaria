import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/view/lv_home_screen.dart';
import 'package:otzaria/low_vision/view/lv_input_test_screen.dart';
import 'package:otzaria/low_vision/view/lv_search_screen.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/low_vision/view/widgets/lv_keyboard.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

import 'low_vision_test_harness.dart';

Future<int> _pumpButton(
  WidgetTester tester, {
  int toleranceIndex = 1,
  List<String>? out,
}) async {
  await pumpLowVision(
    tester,
    Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          height: 300,
          child: LvButton(label: 'לחץ', onPressed: () => out?.add('tap')),
        ),
      ),
    ),
    setup: (c) => c.setTapTolerance(toleranceIndex),
  );
  return 0;
}

void main() {
  group('נגיעה סלחנית', () {
    testWidgets('נגיעה שהאצבע זזה בה מעט נקלטת ברגישות גבוהה', (tester) async {
      final out = <String>[];
      await _pumpButton(tester, out: out);
      final g = await tester.startGesture(tester.getCenter(find.text('לחץ')));
      await g.moveBy(const Offset(35, 10));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, ['tap']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('נגיעה ארוכה וקלה (בלי תזוזה) נקלטת גם אחרי זמן רב', (
      tester,
    ) async {
      final out = <String>[];
      await _pumpButton(tester, out: out);
      final g = await tester.startGesture(tester.getCenter(find.text('לחץ')));
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, ['tap']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('ברגישות רגילה אותה תזוזה מבטלת, וגרירה גדולה תמיד מבטלת', (
      tester,
    ) async {
      final out = <String>[];
      await _pumpButton(tester, toleranceIndex: 0, out: out);
      var g = await tester.startGesture(tester.getCenter(find.text('לחץ')));
      await g.moveBy(const Offset(35, 10));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, isEmpty);

      await _pumpButton(tester, out: out);
      g = await tester.startGesture(tester.getCenter(find.text('לחץ')));
      await g.moveBy(const Offset(120, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, isEmpty);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('שתי אצבעות אינן נגיעה', (tester) async {
      final out = <String>[];
      await _pumpButton(tester, out: out);
      final c = tester.getCenter(find.text('לחץ'));
      final a = await tester.startGesture(c, pointer: 1);
      final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, isEmpty);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('בתוך רשימה: נגיעה קלה נקלטת, וגלילה אמיתית לא נחשבת נגיעה', (
      tester,
    ) async {
      final out = <String>[];
      await pumpLowVision(
        tester,
        Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                LvRow(title: 'שורה $i', onTap: () => out.add('row$i')),
            ],
          ),
        ),
      );
      // גרירה של 30px: הרשימה זזה (מעל סף הגלילה), ולכן זו לא נגיעה.
      var g = await tester.startGesture(tester.getCenter(find.text('שורה 3')));
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, isEmpty);

      // נגיעה עם תזוזה קלה מאוד: הרשימה לא זזה, והשורה נבחרת.
      g = await tester.startGesture(tester.getCenter(find.text('שורה 4')));
      await g.moveBy(const Offset(6, 4));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(out, ['row4']);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('מקלדת', () {
    testWidgets('אות נכנסת ברגע הנגיעה, עוד לפני הרמת האצבע', (tester) async {
      await pumpLowVision(
        tester,
        LvSearchScreen(search: (_) async => const []),
      );
      await tester.pump();
      final g = await tester.startGesture(
        tester.getCenter(find.text('ש').first),
      );
      await tester.pump();
      expect(find.text('ש'), findsNWidgets(2)); // המקש והאות בשורת החיפוש
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ש'), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('אפשר לבחור הקלדה בהרמת האצבע', (tester) async {
      await pumpLowVision(
        tester,
        LvSearchScreen(search: (_) async => const []),
        setup: (c) => c.setKeysOnTouchDown(false),
      );
      await tester.pump();
      final g = await tester.startGesture(
        tester.getCenter(find.text('ש').first),
      );
      await tester.pump();
      expect(find.text('ש'), findsOneWidget); // רק המקש
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ש'), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('הגדרת גודל המקלדת משנה את גובה המקלדת', (tester) async {
      Future<double> heightFor(int index) async {
        await pumpLowVision(
          tester,
          LvSearchScreen(search: (_) async => const []),
          setup: (c) => c.setKeyboardSize(index),
        );
        await tester.pump();
        return tester.getSize(find.byType(LvKeyboard)).height;
      }

      final regular = await heightFor(0);
      final huge = await heightFor(3);
      expect(regular, closeTo(1080 * 0.40, 1));
      // ה"ענקית" גדולה בהרבה, אבל משאירה מקום לשורה של תוצאות.
      expect(huge, greaterThan(regular * 1.4));
      expect(huge, lessThanOrEqualTo(1080 * 0.82 + 1));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('מסך הבית', () {
    testWidgets('הגדרת גודל משנה את גודל האייקון', (tester) async {
      Future<double> iconFor(int index) async {
        await pumpLowVision(
          tester,
          LvHomeScreen(libraryHasBooks: () async => true),
          setup: (c) => c.setHomeSize(index),
        );
        await tester.pump();
        await tester.pump();
        return tester
            .widget<Icon>(find.byIcon(FluentIcons.book_24_filled))
            .size!;
      }

      final small = await iconFor(0);
      final big = await iconFor(3);
      expect(big, greaterThan(small * 1.8));
      // גם הרגיל גדול בהרבה מהאייקון הקודם (3 יחידות).
      expect(small, greaterThan(300));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('חוגה פיזית', () {
    final lines = [for (var i = 0; i < 120; i++) 'שורה מספר $i בספר'];

    testWidgets('מקשי עוצמת הקול גוללים בצעדים קטנים (ברירת מחדל)', (
      tester,
    ) async {
      expect(
        LvAction.scrollDown.defaultKeys.map((k) => k.keyId),
        [LogicalKeyboardKey.audioVolumeUp.keyId],
      );
      expect(
        LvAction.scrollUp.defaultKeys.map((k) => k.keyId),
        [LogicalKeyboardKey.audioVolumeDown.keyId],
      );
    });

    testWidgets('הפעולה גוללת כחמישית מהתצוגה, ושיוך מחדש עובד', (
      tester,
    ) async {
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
      // בסביבת הבדיקה אין מקש עוצמת קול, ולכן משייכים לפעולה מקש אחר.
      h.cubit.setKeyOverride('scrollDown', [LogicalKeyboardKey.f9.keyId]);
      h.cubit.setKeyOverride('scrollUp', [LogicalKeyboardKey.f10.keyId]);
      double top() => tester.getTopLeft(find.text('שורה מספר 1 בספר').first).dy;
      final before = top();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      final moved = before - top();
      expect(moved, greaterThan(60));
      expect(moved, lessThan(450)); // הרבה פחות מעמוד שלם

      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(top(), closeTo(before, 2));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('בדיקת נגיעה', () {
    testWidgets('מציגה משך, תזוזה, לחץ וגודל של כל נגיעה', (tester) async {
      await pumpLowVision(tester, const LvInputTestScreen());
      await tester.pump();
      final g = await tester.startGesture(const Offset(900, 700));
      await tester.pump(const Duration(milliseconds: 120));
      await g.moveBy(const Offset(12, 0));
      await g.up();
      await tester.pump();
      expect(find.textContaining('נגיעה:'), findsOneWidget);
      expect(find.textContaining('תזוזה 12 px'), findsOneWidget);
      expect(find.textContaining('גודל מגע'), findsOneWidget);
    });

    testWidgets('נגיעה שבוטלה על ידי המערכת מסומנת', (tester) async {
      await pumpLowVision(tester, const LvInputTestScreen());
      await tester.pump();
      final g = await tester.startGesture(const Offset(900, 700));
      await tester.pump(const Duration(milliseconds: 50));
      await g.cancel();
      await tester.pump();
      expect(find.textContaining('בוטלה על ידי המערכת'), findsOneWidget);
    });
  });

  group('חיפוש עם מקלדת ענקית ובפריסה לצד', () {
    final found = [
      TextBook(title: 'משנה תורה', author: 'רמב"ם'),
      TextBook(title: 'משנה ברורה', author: 'חפץ חיים'),
    ];

    testWidgets(
      'מקלדת ענקית: חזרה במקום "חפש", בלי כפתורים למעלה, ותוצאה מובלטת',
      (
        tester,
      ) async {
        await pumpLowVision(
          tester,
          LvSearchScreen(search: (_) async => found),
          setup: (c) => c.setKeyboardSize(3),
        );
        await tester.pump();

        // שורה עליונה: אין "חזרה" ו"הסתר מקלדת"; המקש "חזרה" הוא במקלדת.
        expect(find.text('הסתר מקלדת'), findsNothing);
        expect(find.text('חפש'), findsNothing);
        final back = find.text('חזרה');
        expect(back, findsOneWidget);
        expect(
          find.descendant(of: find.byType(LvKeyboard), matching: back),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(LvKeyboard),
            matching: find.text('מ'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        // התוצאה המתאימה ביותר מובלטת בשורה העליונה, והמחבר בצד שמאל שלה.
        final title = tester.getCenter(find.text('משנה תורה'));
        final author = tester.getCenter(find.text('רמב"ם'));
        expect(title.dy, lessThan(300));
        expect(author.dx, lessThan(title.dx));
        expect(find.text('משנה ברורה'), findsNothing);

        // התוצאה הבאה.
        await tester.tap(find.bySemanticsLabel(RegExp('התוצאה הבאה')));
        await tester.pump();
        expect(find.text('משנה ברורה'), findsOneWidget);
        expect(find.text('משנה תורה'), findsNothing);
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets('פריסה לצד: הרבה תוצאות נראות יחד עם מקלדת בגובה מלא', (
      tester,
    ) async {
      await pumpLowVision(
        tester,
        LvSearchScreen(search: (_) async => found),
        setup: (c) => c.setSearchSideBySide(true),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(LvKeyboard),
          matching: find.text('מ'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('משנה תורה'), findsOneWidget);
      expect(find.text('משנה ברורה'), findsOneWidget);
      final keyboard = tester.getRect(find.byType(LvKeyboard));
      final results = tester.getCenter(find.text('משנה תורה'));
      // התוצאות מימין למקלדת, והמקלדת מאריכה על כל גובה הגוף.
      expect(results.dx, greaterThan(keyboard.right));
      expect(keyboard.height, greaterThan(700));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
