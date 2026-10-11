import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/ref_key.dart';

/// המפתח הקנוני נבנה גם בבונה ה-DB (SeforimLibrary) מול אותו קובץ fixtures.
/// שינוי כאן שמפיל את הבדיקה מחייב שינוי מקביל שם — אחרת ה-hash לא ייפגש.
void main() {
  final fixtures =
      jsonDecode(
            File('test/fixtures/ref_key_fixtures.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  group('buildRefKey', () {
    for (final entry in fixtures['refKeys'] as List) {
      final input = entry['input'] as String;
      test(input, () {
        final key = buildRefKey(input);
        expect(key, entry['key']);
        if (key != null) expect(refKeyHash(key), entry['hash']);
      });
    }
  });

  group('buildLineRefKey', () {
    for (final entry in fixtures['lineKeys'] as List) {
      final heRef = entry['heRef'] as String;
      test(heRef, () {
        final aliases = (entry['aliases'] as List).cast<String>();
        final key = buildLineRefKey(heRef, aliases);
        expect(key, entry['key']);
        if (key != null) expect(refKeyHash(key), entry['hash']);
      });
    }
  });

  group('partialLineRefKeys', () {
    for (final entry in fixtures['partialLineKeys'] as List) {
      final heRef = entry['heRef'] as String;
      test(heRef, () {
        final aliases = (entry['aliases'] as List).cast<String>();
        final expected = (entry['keys'] as List).cast<Map<String, dynamic>>();
        final keys = partialLineRefKeys(heRef, aliases);
        expect(keys, [for (final e in expected) e['key']]);
        expect(keys.map(refKeyHash), [for (final e in expected) e['hash']]);
      });
    }
  });

  group('buildPartialRefKey', () {
    for (final entry in fixtures['partialRefKeys'] as List) {
      final input = entry['input'] as String;
      test(input, () {
        final key = buildPartialRefKey(input);
        expect(key, entry['key']);
        expect(refKeyHash(key!), entry['hash']);
      });
    }
  });

  test('שאילתה וכותרת מגיעות לאותו מפתח', () {
    expect(
      buildRefKey('פרק לב פסוק יא'),
      buildLineRefKey('ישעיהו לב, יא', const ['ישעיהו']),
    );
  });

  test('שורת כותרת אינה מקבלת מפתח', () {
    expect(buildLineRefKey('ישעיהו', const ['ישעיהו']), isNull);
  });

  group('lineRefIndexEntries', () {
    // מפתחות כל שורה בנפרד — מה שהאינדקס חייב להכיל.
    List<(int, int)> naive(
      List<({int lineIndex, String heRef})> refs,
      String title,
    ) => [
      for (final ref in refs)
        if (buildLineRefKey(ref.heRef, [title]) case final key?) ...[
          (refKeyHash(key), ref.lineIndex),
          for (final partial in partialLineRefKeys(ref.heRef, [title]))
            (refKeyHash(partial), ref.lineIndex),
        ],
    ];

    // ספר אישי: עשר שורות תחת כל כותרת חולקות heRef אחד.
    final refs = [
      for (var i = 0; i < 20000; i++)
        (lineIndex: i, heRef: 'טור, חושן משפט, סימן ${i ~/ 100}, ${i ~/ 10}'),
      (lineIndex: 20000, heRef: 'טור'),
    ];

    test('זהה למפתחות שמחושבים לכל שורה בנפרד', () {
      expect(lineRefIndexEntries(refs, 'טור'), naive(refs, 'טור'));
    });

    test('heRef שחוזר בשורות רצופות אינו מחושב מחדש', () {
      final naiveWatch = Stopwatch()..start();
      naive(refs, 'טור');
      naiveWatch.stop();
      final watch = Stopwatch()..start();
      lineRefIndexEntries(refs, 'טור');
      watch.stop();
      expect(
        watch.elapsedMicroseconds * 3,
        lessThan(naiveWatch.elapsedMicroseconds),
      );
    });
  });
}
