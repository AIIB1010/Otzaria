import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';

/// Encodes a payload the way `scripts/app_bundle.py` of toldot-gedolei-yisrael
/// does: gzip of compact UTF-8 JSON.
Uint8List encodeBundle(Map<String, dynamic> payload) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(payload))));

Map<String, dynamic> samplePayload({Object version = 1}) => {
  'format': 'biographies-app',
  'version': version,
  'built': '2026-10-23',
  'release': 'v0.3.0',
  'author': 'abaye',
  'eras': [
    {'key': 'tannaim', 'label': 'תנאים'},
    {'key': 'rishonim', 'label': 'ראשונים'},
    {'key': 'acharonim', 'label': 'אחרונים'},
  ],
  'credits': {
    'wikipedia': {
      'name': 'ויקיפדיה העברית',
      'license': 'CC BY-SA 4.0',
      'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/deed.he',
      'attribution': 'על פי ערכי ויקיפדיה העברית.',
    },
  },
  'entries': [
    {
      'id': 'Q127398',
      'era': 'rishonim',
      'name': 'רבינו משה בן מימון',
      'known_as': ['הרמב"ם'],
      'honorific': 'זצ"ל',
      'born': {'hebrew': 'ד\'תתצ"ח (או: ד\'תתצ"ה)', 'gregorian': '1138'},
      'died': {'place': 'פוסטאט'},
      'teachers': [
        {'name': 'רבי יוסף אבן מיגאש', 'ref': 'Q958361'},
        {'name': 'רבי פלוני'},
      ],
      'family': [
        {'relation': 'אביו', 'name': 'רבי מימון הדיין', 'ref': 'Q3303401'},
      ],
      'works': [
        {'title': 'משנה תורה', 'description': 'חיבור הלכתי'},
        {'title': 'מורה נבוכים'},
      ],
      'summary': 'מגדולי הפוסקים.',
      'sources': [
        {'credit': 'wikipedia', 'title': 'רמב"ם', 'url': 'https://he.x/1'},
      ],
    },
    {'id': 'tta-1', 'era': 'tannaim', 'name': 'אונקלוס הגר'},
    // Malformed entries are skipped, not fatal.
    {'id': 'no-name'},
    'not an entry',
  ],
};

void main() {
  group('BiographiesCodec', () {
    test('decodes the bundle, its eras, credits and entries', () {
      final bundle = BiographiesCodec.decode(encodeBundle(samplePayload()));

      expect(bundle.release, 'v0.3.0');
      expect(bundle.built, '2026-10-23');
      expect(bundle.eras.map((e) => e.key), [
        'tannaim',
        'rishonim',
        'acharonim',
      ]);
      expect(bundle.presentEras.map((e) => e.key), ['tannaim', 'rishonim']);
      expect(bundle.credits['wikipedia']?.license, 'CC BY-SA 4.0');
      expect(bundle.entries.map((b) => b.id), ['Q127398', 'tta-1']);

      final rambam = bundle.entries.first;
      expect(rambam.fullName, 'רבינו משה בן מימון זצ"ל');
      expect(rambam.eraLabel, 'ראשונים');
      expect(rambam.knownAs, ['הרמב"ם']);
      expect(rambam.born?.display, 'ד\'תתצ"ח (או: ד\'תתצ"ה) (1138)');
      expect(rambam.died?.display, 'פוסטאט');
      expect(rambam.teachers.first.ref, 'Q958361');
      expect(rambam.teachers.last.ref, isNull);
      expect(rambam.family.single.display, 'אביו: רבי מימון הדיין');
      expect(rambam.works.first.display, 'משנה תורה - חיבור הלכתי');
      expect(rambam.works.last.display, 'מורה נבוכים');
      expect(rambam.sources.single.url, 'https://he.x/1');

      final onkelos = bundle.entries.last;
      expect(onkelos.summary, isNull);
      expect(onkelos.born, isNull);
      expect(onkelos.teachers, isEmpty);
    });

    test('rejects bytes that are not gzip', () {
      expect(
        () => BiographiesCodec.decode(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });

    test('rejects another format', () {
      final payload = samplePayload()..['format'] = 'tashma-biographies';
      expect(
        () => BiographiesCodec.decode(encodeBundle(payload)),
        throwsFormatException,
      );
    });

    test('rejects a newer bundle version', () {
      expect(
        () => BiographiesCodec.decode(encodeBundle(samplePayload(version: 2))),
        throwsFormatException,
      );
    });
  });
}
