// מפיק צילומי מסך מהקוד האמיתי ברזולוציית מסך 16" (1920x1080).
// רץ רק כש-LV_SHOTS_DIR מוגדר:
//   LV_SHOTS_DIR=/path flutter test test/low_vision/low_vision_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/view/lv_books_screen.dart';
import 'package:otzaria/low_vision/view/lv_home_screen.dart';
import 'package:otzaria/low_vision/view/lv_pdf_reader.dart';
import 'package:otzaria/low_vision/view/lv_search_screen.dart';
import 'package:otzaria/low_vision/view/lv_settings_screen.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/low_vision/view/lv_toc_screen.dart';
import 'package:otzaria/low_vision/models/lv_toc.dart';
import 'package:otzaria/models/books.dart';

import 'low_vision_test_harness.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  await loader.load();
}

String _fluentFontsDir() {
  final cache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final hosted = Directory('$cache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .firstWhere((d) => d.path.contains('fluentui_system_icons-'));
  return '${hosted.path}/lib/fonts';
}

const _boundary = ValueKey('lv-shot');

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['LV_SHOTS_DIR']!;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

List<String> _lines() => [
  '<h2>פרק א</h2>',
  'בראשית ברא אלהים את השמים ואת הארץ. והארץ היתה תהו ובהו וחשך על פני תהום ורוח אלהים מרחפת על פני המים.',
  'ויאמר אלהים יהי אור ויהי אור. וירא אלהים את האור כי טוב ויבדל אלהים בין האור ובין החשך.',
  'ויקרא אלהים לאור יום ולחשך קרא לילה ויהי ערב ויהי בקר יום אחד.',
  for (var i = 0; i < 30; i++)
    'ויאמר אלהים יהי רקיע בתוך המים ויהי מבדיל בין מים למים $i',
  '<h2>פרק ב</h2>',
  for (var i = 0; i < 30; i++) 'ויכלו השמים והארץ וכל צבאם $i',
];

void main() {
  final enabled = Platform.environment['LV_SHOTS_DIR'] != null;

  setUpAll(() async {
    if (!enabled) return;
    await _loadFont('Rubik', 'fonts/Rubik-VariableFont_wght.ttf');
    final dir = _fluentFontsDir();
    for (final f in ['Filled', 'Regular']) {
      await _loadFont(
        'packages/fluentui_system_icons/FluentSystemIcons-$f',
        '$dir/FluentSystemIcons-$f.ttf',
      );
    }
  });

  ThemeData theme() => ThemeData(fontFamily: 'Rubik');

  final books = [
    TextBook(title: 'משנה ברורה', author: 'ישראל מאיר הכהן'),
    TextBook(title: 'שולחן ערוך אורח חיים', author: 'יוסף קארו'),
    TextBook(title: 'תהילים', author: ''),
    TextBook(title: 'רמב"ם הלכות שבת', author: 'משה בן מימון'),
  ];

  testWidgets('צילומי מסך', skip: !enabled, (tester) async {
    // בית
    await pumpLowVision(
      tester,
      LvHomeScreen(libraryHasBooks: () async => true),
      theme: theme(),
      boundaryKey: _boundary,
      setup: (c) {
        for (final b in books) {
          c.noteOpened(b);
        }
      },
    );
    await tester.pump();
    await tester.pump();
    await _shot(tester, '1-בית');

    // הספרים שלי
    await pumpLowVision(
      tester,
      const LvBooksScreen(),
      theme: theme(),
      boundaryKey: _boundary,
      setup: (c) {
        for (final b in books.reversed) {
          c.noteOpened(b);
        }
        c.togglePin(books[1]);
        c.togglePin(books[0]);
      },
    );
    await tester.pump();
    await _shot(tester, '2-הספרים-שלי');

    // חיפוש
    await pumpLowVision(
      tester,
      LvSearchScreen(search: (q) async => books.take(3).toList()),
      theme: theme(),
      boundaryKey: _boundary,
    );
    await tester.tap(find.text('מ').first);
    await tester.tap(find.text('ש').first);
    await tester.tap(find.text('נ').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await _shot(tester, '3-חיפוש-עם-מקלדת');

    // תוצאות במסך מלא
    await tester.tap(find.text('חפש').first);
    await tester.pump();
    await tester.pump();
    await _shot(tester, '4-תוצאות-חיפוש');

    // קורא טקסט
    Future<void> reader(
      String name, {
      LvPalette? palette,
      double? scale,
    }) async {
      await pumpLowVision(
        tester,
        LvTextReader(
          book: TextBook(title: 'בראשית'),
          loadText: () async => _lines().join('\n'),
          loadToc: () async => [
            TocEntry(text: 'פרק א', index: 0, level: 2),
            TocEntry(text: 'פרק ב', index: 34, level: 2),
          ],
        ),
        theme: theme(),
        boundaryKey: _boundary,
        setup: (c) {
          if (palette != null) c.setPalette(palette);
          if (scale != null) c.setTextScale(scale);
        },
      );
      await tester.pump();
      await tester.pump();
      await _shot(tester, name);
    }

    await reader('5-קורא-טקסט');
    await reader(
      '6-קורא-טקסט-לבן-על-שחור',
      palette: LvPalette.whiteOnBlack,
      scale: 1.6,
    );
    await reader(
      '7-קורא-טקסט-שחור-על-צהוב',
      palette: LvPalette.blackOnYellow,
      scale: 2.4,
    );

    // תוכן עניינים
    await pumpLowVision(
      tester,
      LvTocScreen(
        bookTitle: 'משנה ברורה',
        items: [
          LvTocItem('הלכות השכמת הבוקר', 1, [LvTocItem('סימן א', 1)]),
          LvTocItem('הלכות ציצית', 8),
          LvTocItem('הלכות תפילין', 25, [LvTocItem('סימן כה', 25)]),
          LvTocItem('הלכות קריאת שמע', 46),
        ],
      ),
      theme: theme(),
      boundaryKey: _boundary,
    );
    await tester.pump();
    await _shot(tester, '8-תוכן-עניינים');

    // קפיצה לעמוד (ספר מצולם)
    await pumpLowVision(
      tester,
      const LvGotoPageScreen(pageCount: 340, current: 12),
      theme: theme(),
      boundaryKey: _boundary,
    );
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('8'));
    await tester.pump();
    await _shot(tester, '9-קפיצה-לעמוד');

    // הגדרות (לעוזר)
    await pumpLowVision(
      tester,
      const LvSettingsScreen(),
      theme: theme(),
      boundaryKey: _boundary,
    );
    await tester.pump();
    await _shot(tester, '10-הגדרות');
    await tester.pump(const Duration(seconds: 2));
  });
}
