import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/models/lv_scan_resolver.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/models/books.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'low_vision_test_harness.dart';

class _Opened {
  _Opened(this.book, this.replace, this.page, this.line, this.forceText);
  final Book book;
  final bool replace;
  final int? page;
  final int? line;
  final bool forceText;
}

LvScanResolver _resolver({PdfBook? pdf, int? page = 7}) => LvScanResolver(
  pdfFor: (_) async => pdf,
  textFor: (_) async => null,
  pageFor: (text, pdf, line) async => page,
  lineFor: (pdf, outline, page) async => 3,
  talmudOpensAsScan: (_) => false,
);

void main() {
  final lines = [for (var i = 0; i < 80; i++) 'שורה מספר $i בספר'];
  final scan = PdfBook(title: 'ברכות', path: '/tmp/berachot.pdf');

  Future<LvHarness> open(
    WidgetTester tester, {
    required LvScanResolver resolver,
    required List<_Opened> opened,
    int? initialLine,
  }) async {
    final h = await pumpLowVision(
      tester,
      LvTextReader(
        book: TextBook(title: 'ברכות'),
        loadText: () async => lines.join('\n'),
        loadToc: () async => const [],
        resolver: resolver,
        initialLine: initialLine,
        openBook:
            (
              BuildContext context,
              Book book, {
              bool replace = false,
              bool forceText = false,
              int? initialPage,
              int? initialLine,
            }) async => opened.add(
              _Opened(book, replace, initialPage, initialLine, forceText),
            ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return h;
  }

  group('צורת הדף (הצילום המקורי) בקורא הטקסט', () {
    testWidgets('לספר עם צילום מופיע כפתור "צורת הדף", והוא פותח את הצילום', (
      tester,
    ) async {
      final opened = <_Opened>[];
      final h = await open(
        tester,
        resolver: _resolver(pdf: scan, page: 7),
        opened: opened,
      );
      expect(find.text('צורת הדף'), findsOneWidget);

      await tester.tap(find.text('צורת הדף'));
      await tester.pump();
      await tester.pump();
      expect(opened, hasLength(1));
      expect(opened.single.book, same(scan));
      expect(opened.single.replace, isTrue);
      expect(opened.single.page, 7);
      expect(h.cubit.state.preferScan, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('בלי התאמה אמינה הצילום נפתח בלי עמוד מסוים', (tester) async {
      final opened = <_Opened>[];
      await open(
        tester,
        resolver: _resolver(pdf: scan, page: null),
        opened: opened,
      );
      await tester.tap(find.text('צורת הדף'));
      await tester.pump();
      await tester.pump();
      expect(opened.single.page, isNull);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('לספר בלי צילום אין כפתור', (tester) async {
      await open(tester, resolver: _resolver(pdf: null), opened: []);
      expect(find.text('צורת הדף'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('נפתח בשורה שנבחרה (למשל במעבר מהצילום)', (tester) async {
      await open(
        tester,
        resolver: _resolver(pdf: null),
        opened: [],
        initialLine: 40,
      );
      expect(find.text('שורה מספר 40 בספר'), findsOneWidget);
      expect(find.text('שורה מספר 0 בספר'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  test('ההעדפה "לפתוח כצילום" נשמרת וחוזרת', () async {
    SharedPreferences.setMockInitialValues({});
    final first = LowVisionCubit();
    await first.load();
    expect(first.state.preferScan, isFalse);
    first.setPreferScan(true);
    await first.close();

    final second = LowVisionCubit();
    await second.load();
    expect(second.state.preferScan, isTrue);
    await second.close();
  });

  test('ה-typedef של פותח הספרים תואם את lvOpenBook', () {
    LvBookOpener opener = lvOpenBook;
    expect(opener, isNotNull);
  });
}
