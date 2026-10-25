import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/breakpad_envelope.dart';
import 'package:path/path.dart' as p;

import 'minidump_fixture.dart';

void main() {
  group('extractMinidumpFromEnvelope', () {
    test('שולף את ה-minidump גם אחרי אירוע ו-session', () {
      final dump = buildMinidump();
      expect(
        extractMinidumpFromEnvelope(buildCrashEnvelope(minidump: dump)),
        dump,
      );
    });

    test('דילוג על attachment שאינו minidump', () {
      final dump = buildMinidump();
      final envelope = buildEnvelope([
        (
          header: {'type': 'attachment', 'attachment_type': 'event.attachment'},
          payload: utf8.encode('log line\nsecond line'),
        ),
        (
          header: {'type': 'attachment', 'attachment_type': 'event.minidump'},
          payload: dump,
        ),
      ]);
      expect(extractMinidumpFromEnvelope(envelope), dump);
    });

    test('נתונים בינאריים עם ירידות שורה אינם שוברים את הפענוח', () {
      final dump = Uint8List.fromList([...buildMinidump(), 0x0a, 0x7b, 0x0a]);
      expect(
        extractMinidumpFromEnvelope(buildCrashEnvelope(minidump: dump)),
        dump,
      );
    });

    test('minidump בלי length → null (בינארי, אי אפשר לחתוך לפי שורה)', () {
      final envelope = buildEnvelope([
        (
          header: {'type': 'attachment', 'attachment_type': 'event.minidump'},
          payload: buildMinidump(),
        ),
      ], withLength: false);
      expect(extractMinidumpFromEnvelope(envelope), isNull);
    });

    test('פריט אחר בלי length מדולג עד סוף השורה', () {
      final dump = buildMinidump();
      final head = buildEnvelope([
        (header: {'type': 'event'}, payload: utf8.encode('{"a":1}')),
      ], withLength: false);
      final tail = buildEnvelope([
        (
          header: {'type': 'attachment', 'attachment_type': 'event.minidump'},
          payload: dump,
        ),
      ]);
      // כותרת ה-envelope של השני נזרקת: מדביקים מהפריט הראשון שלו.
      final firstItem = tail.indexOf(0x0a);
      final combined = Uint8List.fromList([
        ...head,
        ...tail.sublist(firstItem),
      ]);
      expect(extractMinidumpFromEnvelope(combined), dump);
    });

    test('envelope בלי minidump → null', () {
      final envelope = buildEnvelope([
        (header: {'type': 'event'}, payload: utf8.encode('{}')),
      ]);
      expect(extractMinidumpFromEnvelope(envelope), isNull);
    });

    test('payload שאינו minidump (בלי MDMP) → null', () {
      final envelope = buildCrashEnvelope(
        minidump: Uint8List.fromList(List.filled(64, 7)),
      );
      expect(extractMinidumpFromEnvelope(envelope), isNull);
    });

    test('envelope קטוע, length שגוי או זבל → null בלי לזרוק', () {
      final full = buildCrashEnvelope();
      expect(
        extractMinidumpFromEnvelope(
          Uint8List.sublistView(full, 0, full.length - 10),
        ),
        isNull,
      );
      expect(
        extractMinidumpFromEnvelope(
          buildEnvelope([
            (
              header: {
                'type': 'attachment',
                'attachment_type': 'event.minidump',
                'length': -5,
              },
              payload: const [1, 2, 3],
            ),
          ], withLength: false),
        ),
        isNull,
      );
      expect(extractMinidumpFromEnvelope(Uint8List(0)), isNull);
      expect(
        extractMinidumpFromEnvelope(
          Uint8List.fromList(utf8.encode('{}\nnot json\n')),
        ),
        isNull,
      );
    });
  });

  group('recoverBreakpadMinidumps', () {
    late Directory sentry;
    final crashedAt = DateTime.utc(2026, 10, 20, 12);
    final since = DateTime.utc(2026, 10, 20, 11);

    setUp(() => sentry = Directory.systemTemp.createTempSync('otzaria_bp_'));
    tearDown(() => sentry.deleteSync(recursive: true));

    File envelope(
      String dir,
      String name,
      Uint8List bytes,
      DateTime modified,
    ) {
      final file = File(p.join(sentry.path, dir, name))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      file.setLastModifiedSync(modified);
      return file;
    }

    File recovered(String name) =>
        File(p.join(sentry.path, recoveredMinidumpsDirName, name));

    Directory recoveredDir() =>
        Directory(p.join(sentry.path, recoveredMinidumpsDirName));

    test(
      'envelope ב-*.run הופכים ל-dmp בזמן הקריסה, ו-reports לא נוגעים',
      () async {
        final a = buildMinidump();
        final b = buildMinidump(exceptionCode: 0x80000003);
        envelope(
          'a1.run',
          'ev-a.envelope',
          buildCrashEnvelope(minidump: a),
          crashedAt,
        );
        envelope(
          'b2.run',
          'ev-b.envelope',
          buildCrashEnvelope(minidump: b),
          crashedAt,
        );

        await recoverBreakpadMinidumps(sentry.path, since);

        expect(recovered('ev-a.dmp').readAsBytesSync(), a);
        expect(recovered('ev-b.dmp').readAsBytesSync(), b);
        expect(recovered('ev-a.dmp').lastModifiedSync().toUtc(), crashedAt);
        expect(recoveredDir().listSync().length, 2);
        expect(Directory(p.join(sentry.path, 'reports')).existsSync(), isFalse);
      },
    );

    test(
      'cache אינו נסרק (ב-sentry-native ה-dump יוצא משם לקובץ נפרד)',
      () async {
        envelope('cache', 'ev.envelope', buildCrashEnvelope(), crashedAt);
        await recoverBreakpadMinidumps(sentry.path, since);
        expect(recoveredDir().existsSync(), isFalse);
      },
    );

    test(
      'envelope ישן מתחילת ההפעלה הקודמת מתעלמים; בדיוק ב-since נכלל',
      () async {
        envelope(
          'a1.run',
          'old.envelope',
          buildCrashEnvelope(),
          since.subtract(const Duration(milliseconds: 1)),
        );
        envelope('a1.run', 'edge.envelope', buildCrashEnvelope(), since);
        await recoverBreakpadMinidumps(sentry.path, since);
        expect(recovered('old.dmp').existsSync(), isFalse);
        expect(recovered('edge.dmp').existsSync(), isTrue);
      },
    );

    test(
      'envelope בלי minidump, קובץ אחר ותיקייה זרה לא משאירים כלום',
      () async {
        envelope(
          'a1.run',
          'ev.envelope',
          buildEnvelope([
            (header: {'type': 'event'}, payload: utf8.encode('{}')),
          ]),
          crashedAt,
        );
        envelope('a1.run', 'notes.txt', buildCrashEnvelope(), crashedAt);
        envelope('external', 'x.envelope', buildCrashEnvelope(), crashedAt);

        await recoverBreakpadMinidumps(sentry.path, since);
        expect(recoveredDir().existsSync(), isFalse);
      },
    );

    test('dmp שכבר נשלף לא נדרס', () async {
      envelope('a1.run', 'ev.envelope', buildCrashEnvelope(), crashedAt);
      recovered('ev.dmp')
        ..createSync(recursive: true)
        ..writeAsStringSync('kept');
      await recoverBreakpadMinidumps(sentry.path, since);
      expect(recovered('ev.dmp').readAsStringSync(), 'kept');
    });

    test('dumps ושאריות tmp ישנים נמחקים, חדשים נשארים', () async {
      final now = DateTime.utc(2026, 11, 20);
      final stale = now.subtract(
        recoveredMinidumpRetention + const Duration(days: 1),
      );
      final fresh = now.subtract(const Duration(days: 1));
      for (final (name, at) in [
        ('stale.dmp', stale),
        ('stale.dmp.tmp', stale),
        ('fresh.dmp', fresh),
      ]) {
        recovered(name)
          ..createSync(recursive: true)
          ..writeAsStringSync('x')
          ..setLastModifiedSync(at);
      }

      await recoverBreakpadMinidumps(sentry.path, since, clock: () => now);

      expect(recovered('stale.dmp').existsSync(), isFalse);
      expect(recovered('stale.dmp.tmp').existsSync(), isFalse);
      expect(recovered('fresh.dmp').existsSync(), isTrue);
    });

    test('תיקייה חסרה — לא זורק', () async {
      await recoverBreakpadMinidumps(p.join(sentry.path, 'missing'), since);
    });
  });
}
