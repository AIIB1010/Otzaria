import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/page_shape/lv_html_text.dart';
import 'package:otzaria/low_vision/page_shape/lv_page_shape_loader.dart';
import 'package:otzaria/low_vision/page_shape/lv_page_shape_view.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/models/books.dart';

import 'low_vision_test_harness.dart';

const _base = TextStyle(fontSize: 20);

LvPageShapeLoader _loader({
  List<LvPanelSpec>? specs,
  Future<List<LvCommentaryEntry>> Function(
    TextBook,
    int,
    int,
    List<String>,
  )?
  entries,
}) => LvPageShapeLoader(
  specsLoader: (_) async =>
      specs ??
      const [
        LvPanelSpec(LvPanelSlot.right, 'רש"י'),
        LvPanelSpec(LvPanelSlot.left, 'תוספות'),
      ],
  entriesLoader:
      entries ??
      (book, start, end, titles) async => [
        (line: start, title: 'רש"י', html: '<b>גמ׳</b> פירוש רש"י $start'),
        (line: start, title: 'תוספות', html: 'דברי תוספות $start'),
      ],
);

void main() {
  group('lvHtmlSpans', () {
    test('הדגשה, גדול/קטן ושבירת שורה', () {
      final spans = lvHtmlSpans(
        '<b>דיבור</b> רגיל<br>שורה <big>גדול</big><small>קטן</small>',
        _base,
      ).cast<TextSpan>();
      expect(spans.first.text, 'דיבור');
      expect(spans.first.style!.fontWeight, FontWeight.w900);
      expect(spans[1].text, ' רגיל\nשורה ');
      expect(spans[1].style!.fontWeight, isNot(FontWeight.w900));
      expect(spans[2].style!.fontSize, 24);
      expect(spans[3].style!.fontSize, 16);
    });

    test('תגיות אחרות מוסרות וניקוד אפשר להסיר', () {
      final spans = lvHtmlSpans(
        '<i>בְּרֵאשִׁית</i> &amp; <a href="x">שלום</a>',
        _base,
        showNikud: false,
      ).cast<TextSpan>();
      final text = spans.map((s) => s.text).join();
      expect(text, 'בראשית & שלום');
    });
  });

  group('LvPageShapeLoader', () {
    final lines = [for (var i = 0; i < 10; i++) 'שורה $i'];

    test('חותך את הקטע ומחלק את המפרשים לפי מיקום', () async {
      final data = await _loader().loadSection(
        TextBook(title: 'ברכות'),
        lines,
        2,
        4,
        const [
          LvPanelSpec(LvPanelSlot.right, 'רש"י'),
          LvPanelSpec(LvPanelSlot.left, 'תוספות'),
        ],
      );
      expect(data.mainLines, ['שורה 2', 'שורה 3', 'שורה 4']);
      expect(data.panel(LvPanelSlot.right)!.entries.single, contains('רש"י 2'));
      expect(
        data.panel(LvPanelSlot.left)!.entries.single,
        contains('תוספות 2'),
      );
      expect(data.panel(LvPanelSlot.bottom), isNull);
      expect(data.hasCommentary, isTrue);
    });

    test('כשל בטעינת מפרשים עדיין מציג את הטקסט הראשי', () async {
      final data =
          await _loader(
            entries: (a, b, c, d) async => throw StateError('db'),
          ).loadSection(
            TextBook(title: 'ברכות'),
            lines,
            0,
            1,
            const [LvPanelSpec(LvPanelSlot.right, 'רש"י')],
          );
      expect(data.mainLines, ['שורה 0', 'שורה 1']);
      expect(data.hasCommentary, isFalse);
    });

    test('גבולות הקטע נחתכים לגבולות הספר', () async {
      final data = await _loader().loadSection(
        TextBook(title: 'ברכות'),
        lines,
        8,
        50,
        const [],
      );
      expect(data.mainLines, ['שורה 8', 'שורה 9']);
    });
  });

  group('LvPageShapeView', () {
    LvPageShapeData data() => const LvPageShapeData(
      mainLines: ['<b>גמרא</b> שורה ראשונה', 'שורה שנייה'],
      panels: [
        LvPanelData(
          slot: LvPanelSlot.right,
          title: 'רש"י',
          entries: ['פירוש ראשון', 'פירוש שני'],
        ),
        LvPanelData(
          slot: LvPanelSlot.left,
          title: 'תוספות',
          entries: ['דברי תוספות'],
        ),
        LvPanelData(
          slot: LvPanelSlot.bottom,
          title: 'מהרש"א',
          entries: ['הערה למטה'],
        ),
      ],
    );

    testWidgets('מציג טקסט ראשי ומפרשים במקומם: רש"י מימין, תוספות משמאל', (
      tester,
    ) async {
      final controller = LvPageShapeController();
      await pumpLowVision(
        tester,
        Scaffold(
          body: LvPageShapeView(
            data: data(),
            controller: controller,
            foreground: Colors.black,
            background: Colors.white,
            showNikud: true,
            glide: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('רש"י'), findsOneWidget);
      expect(find.text('תוספות'), findsOneWidget);
      expect(find.text('מהרש"א'), findsOneWidget);
      final rashi = tester.getCenter(find.text('רש"י')).dx;
      final tosafot = tester.getCenter(find.text('תוספות')).dx;
      expect(rashi, greaterThan(tosafot));
      // המהרש"א בתחתית, מתחת לטקסט הראשי.
      expect(
        tester.getCenter(find.text('מהרש"א')).dy,
        greaterThan(tester.getCenter(find.text('רש"י')).dy),
      );
    });

    testWidgets('הגדלה והקטנה ללא הגבלה, וגלילה קטנה, דרך הבקר', (
      tester,
    ) async {
      final controller = LvPageShapeController();
      await pumpLowVision(
        tester,
        Scaffold(
          body: LvPageShapeView(
            data: data(),
            controller: controller,
            foreground: Colors.black,
            background: Colors.white,
            showNikud: true,
            glide: false,
          ),
        ),
      );
      await tester.pump();
      InteractiveViewer viewer() =>
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      double scale() =>
          viewer().transformationController!.value.getMaxScaleOnAxis();

      final fit = scale();
      expect(fit, closeTo(1920 / kLvPageWidth, 0.01));
      controller.zoomIn();
      await tester.pump();
      expect(scale(), closeTo(fit * 1.25, 0.01));
      for (var i = 0; i < 12; i++) {
        controller.zoomIn();
      }
      await tester.pump();
      expect(scale(), greaterThan(fit * 8));
      final zoomedIn = scale();
      controller.zoomOut();
      await tester.pump();
      expect(scale(), lessThan(zoomedIn));

      controller.fitToWidth();
      await tester.pump();
      expect(scale(), closeTo(fit, 0.01));

      final before = viewer().transformationController!.value
          .getTranslation()
          .y;
      controller.scroll(1);
      await tester.pump();
      final after = viewer().transformationController!.value.getTranslation().y;
      expect(after, lessThan(before)); // התוכן זז למעלה = גלילה למטה
    });
  });

  group('צורת הדף בקורא הטקסט', () {
    final lines = [
      '<h2>עמוד א</h2>',
      for (var i = 0; i < 6; i++) 'שורה א$i',
      '<h2>עמוד ב</h2>',
      for (var i = 0; i < 6; i++) 'שורה ב$i',
    ];
    final toc = [
      TocEntry(text: 'עמוד א', index: 0, level: 2),
      TocEntry(text: 'עמוד ב', index: 7, level: 2),
    ];

    Future<LvHarness> open(
      WidgetTester tester, {
      LvPageShapeLoader? loader,
    }) async {
      final h = await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'ברכות'),
          loadText: () async => lines.join('\n'),
          loadToc: () async => toc,
          pageShapeLoader: loader ?? _loader(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return h;
    }

    testWidgets('לספר עם מפרשים מופיע כפתור "צורת הדף"', (tester) async {
      await open(tester);
      expect(find.text('צורת הדף'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('לספר בלי צורת הדף אין כפתור', (tester) async {
      await open(tester, loader: _loader(specs: const []));
      expect(find.text('צורת הדף'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('מעבר לצורת הדף מציג עמוד עם מפרשים, ועמוד הבא עובר קטע', (
      tester,
    ) async {
      final h = await open(tester);
      await tester.tap(find.text('צורת הדף'));
      await tester.pumpAndSettle();

      expect(find.text('דברי תוספות 0'), findsOneWidget);
      expect(find.text('שורה א0'), findsOneWidget);
      expect(find.text('עמוד 1 מתוך 2'), findsOneWidget);
      expect(h.cubit.state.preferPageShape, isTrue);

      await tester.tap(find.text('עמוד').last);
      await tester.pumpAndSettle();
      expect(find.text('עמוד 2 מתוך 2'), findsOneWidget);
      expect(find.text('שורה ב0'), findsOneWidget);
      expect(find.text('שורה א0'), findsNothing);

      // חזרה לטקסט נשארת באותו מקום, ומבטלת את ההעדפה.
      await tester.tap(find.text('טקסט'));
      await tester.pumpAndSettle();
      expect(h.cubit.state.preferPageShape, isFalse);
      expect(find.text('שורה ב0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('אם הוחלף לצורת הדף בפעם הקודמת, ספר חדש נפתח בה', (
      tester,
    ) async {
      final h = await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'ברכות'),
          loadText: () async => lines.join('\n'),
          loadToc: () async => toc,
          pageShapeLoader: _loader(),
        ),
        setup: (c) => c.setPreferPageShape(true),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('עמוד 1 מתוך 2'), findsOneWidget);
      expect(h.cubit.state.preferPageShape, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  test('חידוד ספרים מצולמים: רמות ניגודיות ורינדור', () {
    const off = LowVisionState(pdfSharpnessIndex: 0);
    const sharp = LowVisionState(pdfSharpnessIndex: 1);
    const strong = LowVisionState(pdfSharpnessIndex: 2);
    expect(off.pdfContrast, 1.0);
    expect(off.pdfRenderBoost, 1.0);
    expect(sharp.pdfContrast, greaterThan(1.0));
    expect(strong.pdfContrast, greaterThan(sharp.pdfContrast));
    expect(strong.pdfRenderBoost, greaterThan(sharp.pdfRenderBoost));
    expect(const LowVisionState().pdfSharpnessIndex, 1);
  });
}
