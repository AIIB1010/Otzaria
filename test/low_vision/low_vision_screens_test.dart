import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/view/lv_home_screen.dart';
import 'package:otzaria/low_vision/view/lv_search_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_keyboard.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/models/books.dart';

import 'low_vision_test_harness.dart';

Finder _hasText(String text) => find.text(text);

double _fontSizeOf(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text).first);
  return widget.style!.fontSize!;
}

void main() {
  testWidgets('מסך הבית מציג שני כפתורים גדולים בלבד ואייקון הגדרות קטן', (
    tester,
  ) async {
    await pumpLowVision(
      tester,
      LvHomeScreen(libraryHasBooks: () async => true),
    );
    await tester.pump();

    expect(_hasText('הספרים\nשלי'), findsOneWidget);
    expect(_hasText('חיפוש\nספרים'), findsOneWidget);
    // הטקסט בכפתורי הבית גדול בהרבה מטקסט רגיל (16).
    expect(_fontSizeOf(tester, 'הספרים\nשלי'), greaterThan(100));

    final settings = tester.getSize(find.bySemanticsLabel('הגדרות'));
    final books = tester.getSize(find.bySemanticsLabel('הספרים שלי'));
    expect(settings.width, lessThan(books.width / 5));
  });

  testWidgets('בלי ספרייה מוצגת הודעה ברורה ולא כפתורים מתים', (tester) async {
    await pumpLowVision(
      tester,
      LvHomeScreen(libraryHasBooks: () async => false),
    );
    await tester.pump();
    expect(find.textContaining('לא נמצאה ספרייה'), findsOneWidget);
    expect(_hasText('חיפוש\nספרים'), findsNothing);
  });

  testWidgets('הקלדה במקלדת המסך מחפשת ומציגה תוצאות; לחיצה פותחת קורא', (
    tester,
  ) async {
    final queries = <String>[];
    await pumpLowVision(
      tester,
      LvSearchScreen(
        search: (q) async {
          queries.add(q);
          return [
            TextBook(title: 'משנה תורה', author: 'רמב"ם'),
            TextBook(title: 'משנה ברורה'),
          ];
        },
      ),
    );

    await tester.tap(find.text('מ').first);
    await tester.tap(find.text('ש').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(queries.last, 'מש');
    expect(find.text('משנה תורה'), findsOneWidget);
    expect(find.text('משנה ברורה'), findsOneWidget);
    expect(_fontSizeOf(tester, 'משנה תורה'), greaterThan(60));

    // מחיקה והקלדה ממקלדת חיצונית.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries.last, 'מ');
  });

  testWidgets('מקלדת חיצונית מקלידה בשורת החיפוש', (tester) async {
    final queries = <String>[];
    await pumpLowVision(
      tester,
      LvSearchScreen(
        search: (q) async {
          queries.add(q);
          return const [];
        },
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries.last, 'ab');
  });

  group('קורא טקסט', () {
    final lines = [
      '<h2>פרק א</h2>',
      for (var i = 0; i < 40; i++) 'שורה מספר $i בפרק הראשון',
      '<h2>פרק ב</h2>',
      for (var i = 0; i < 40; i++) 'שורה מספר $i בפרק השני',
    ];
    final toc = [
      TocEntry(text: 'פרק א', index: 0, level: 2),
      TocEntry(text: 'פרק ב', index: 41, level: 2),
    ];

    Future<void> openReader(WidgetTester tester) async {
      await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'ספר בדיקה'),
          loadText: () async => lines.join('\n'),
          loadToc: () async => toc,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('מציג טקסט ענק, כפתור חזרה ותוכן עניינים', (tester) async {
      await openReader(tester);
      expect(find.text('ספר בדיקה'), findsOneWidget);
      expect(find.text('חזרה'), findsOneWidget);
      expect(find.text('תוכן'), findsOneWidget);
      expect(find.text('עמוד'), findsNWidgets(2));
      expect(_fontSizeOf(tester, 'שורה מספר 0 בפרק הראשון'), greaterThan(60));
      // שם הסעיף הנוכחי מוצג תמיד.
      expect(find.text('פרק א'), findsWidgets);
    });

    testWidgets('עמוד הבא מגלול קדימה והקטנה/הגדלה משנות את הגופן', (
      tester,
    ) async {
      await openReader(tester);
      final before = _fontSizeOf(tester, 'שורה מספר 0 בפרק הראשון');
      await tester.tap(find.bySemanticsLabel('הגדל'));
      await tester.pump();
      await tester.pump();
      expect(
        _fontSizeOf(tester, 'שורה מספר 0 בפרק הראשון'),
        greaterThan(before),
      );

      final topBefore = tester
          .getTopLeft(find.text('שורה מספר 0 בפרק הראשון'))
          .dy;
      await tester.tap(find.text('עמוד').last);
      await tester.pumpAndSettle();
      final texts = find.text('שורה מספר 0 בפרק הראשון');
      final scrolledAway =
          texts.evaluate().isEmpty ||
          tester.getTopLeft(texts).dy < topBefore - 300;
      expect(scrolledAway, isTrue);
    });

    testWidgets('דילוג לסעיף דרך תוכן העניינים', (tester) async {
      await openReader(tester);
      await tester.tap(find.text('תוכן'));
      await tester.pumpAndSettle();
      expect(find.text('פרק ב'), findsOneWidget);

      await tester.tap(find.text('פרק ב'));
      await tester.pumpAndSettle();
      expect(find.text('שורה מספר 0 בפרק השני'), findsOneWidget);
      expect(find.text('שורה מספר 0 בפרק הראשון'), findsNothing);
    });

    testWidgets('כפתורי סעיף הבא וסעיף קודם', (tester) async {
      await openReader(tester);
      await tester.tap(find.text('סעיף').last);
      await tester.pumpAndSettle();
      expect(find.text('שורה מספר 0 בפרק השני'), findsOneWidget);

      await tester.tap(find.text('סעיף').first);
      await tester.pumpAndSettle();
      expect(find.text('שורה מספר 0 בפרק הראשון'), findsOneWidget);
    });

    testWidgets('מקשי מקלדת ושיוך מחדש של מקש מאקרו', (tester) async {
      final harness = await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'ספר בדיקה'),
          loadText: () async => lines.join('\n'),
          loadToc: () async => toc,
        ),
      );
      await tester.pump();
      await tester.pump();

      // מקש המאקרו משויך מחדש (בסביבת הבדיקה אין F15, אבל יש F9).
      harness.cubit.setKeyOverride('zoomIn', [LogicalKeyboardKey.f9.keyId]);
      final scaleBefore = harness.cubit.state.textScale;
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pump();
      expect(harness.cubit.state.textScale, greaterThan(scaleBefore));

      harness.cubit.setKeyOverride('contrast', [LogicalKeyboardKey.f10.keyId]);
      final paletteBefore = harness.cubit.state.palette;
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pump();
      expect(harness.cubit.state.palette, isNot(paletteBefore));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final texts = find.text('שורה מספר 0 בפרק הראשון');
      expect(
        texts.evaluate().isEmpty || tester.getTopLeft(texts).dy < 200,
        isTrue,
      );
    });

    testWidgets('קביעת הספר מהסרגל העליון נשמרת', (tester) async {
      final harness = await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'ספר בדיקה'),
          loadText: () async => lines.join('\n'),
          loadToc: () async => toc,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('קבע'));
      await tester.pump();
      expect(harness.cubit.state.pinned.single.title, 'ספר בדיקה');
      expect(find.text('קבוע'), findsOneWidget);
    });
  });
  testWidgets('המקלדת בסדר עברית רגיל: ק משמאל ו-פ מימין', (tester) async {
    await pumpLowVision(tester, LvSearchScreen(search: (_) async => const []));
    final qof = tester.getCenter(find.text('ק').first);
    final pe = tester.getCenter(find.text('פ').first);
    expect(qof.dx, lessThan(pe.dx));
  });

  testWidgets('בטלפון צר שורת החיפוש נשארת רחבה וקריאה', (tester) async {
    await pumpLowVision(
      tester,
      LvSearchScreen(search: (_) async => const []),
      size: const Size(360, 640),
    );
    await tester.tap(find.text('ש').first);
    await tester.pump();
    final searchIcon = tester
        .getCenter(find.byIcon(FluentIcons.search_24_filled).first)
        .dx;
    final clearIcon = tester
        .getCenter(find.byIcon(FluentIcons.dismiss_circle_24_filled))
        .dx;
    final barWidth = (searchIcon - clearIcon).abs();
    expect(barWidth, greaterThan(150));
  });

  testWidgets('מקש במקלדת הופך לשחור עם כיתוב לבן בזמן לחיצה', (tester) async {
    await pumpLowVision(tester, LvSearchScreen(search: (_) async => const []));
    // האות מופיעה גם בשורת החיפוש אחרי ההקלדה, ולכן מחפשים רק במקלדת.
    final letter = find.descendant(
      of: find.byType(LvKeyboard),
      matching: find.text('ש'),
    );
    final key = find.ancestor(of: letter, matching: find.byType(Container));
    Color? colorOf() =>
        ((tester.widget<Container>(key.first)).decoration as BoxDecoration)
            .color;

    final before = colorOf();
    final gesture = await tester.startGesture(tester.getCenter(letter));
    await tester.pump();
    expect(colorOf(), const Color(0xFF000000));
    expect(colorOf(), isNot(before));
    final text = tester.widget<Text>(letter);
    expect(text.style!.color, const Color(0xFFFFFFFF));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(colorOf(), before);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('אחוז ההתקדמות בספר מתעדכן בגלילה ומסומן "מהספר"', (
    tester,
  ) async {
    final lines = [for (var i = 0; i < 200; i++) 'שורה מספר $i בספר'];
    await pumpLowVision(
      tester,
      LvTextReader(
        book: TextBook(title: 'ספר ארוך'),
        loadText: () async => lines.join('\n'),
        loadToc: () async => const [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('0% מהספר'), findsOneWidget);

    await tester.tap(find.text('עמוד').last);
    await tester.pumpAndSettle();
    expect(find.text('0% מהספר'), findsNothing);
    expect(find.textContaining('% מהספר'), findsOneWidget);
  });

  testWidgets('שינוי גודל הטקסט מציג חיווי גדול לרגע', (tester) async {
    await pumpLowVision(
      tester,
      LvTextReader(
        book: TextBook(title: 'ספר'),
        loadText: () async => 'שורה\nעוד שורה',
        loadToc: () async => const [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('גודל הטקסט'), findsNothing);

    await tester.tap(find.bySemanticsLabel('הגדל'));
    await tester.pump();
    expect(find.text('גודל הטקסט: 120%'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('גודל הטקסט'), findsNothing);
  });
}
