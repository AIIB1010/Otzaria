import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_remote_file_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late PluginRemoteFileCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_remote_cache_');
    cache = PluginRemoteFileCache(
      root: Directory(p.join(tempDir.path, 'cache')),
      quotaBytes: 100,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<bool> allowAll(Uri _) async => true;

  List<FileSystemEntity> leftovers(String pluginId) {
    final dir = Directory(p.join(cache.root.path, pluginId));
    return dir.existsSync() ? dir.listSync() : [];
  }

  PluginFileDownloadService serving(List<int> body) =>
      PluginFileDownloadService(
        client: MockClient((_) async => http.Response.bytes(body, 200)),
      );

  Future<PluginRemoteFile> fetch(
    String name,
    int size, {
    String pluginId = 'p1',
    Duration timeout = PluginRemoteFileCache.defaultTimeout,
    PluginFileDownloadService? downloader,
  }) => cache.fetch(
    pluginId,
    Uri.parse('https://example.org/$name'),
    downloader: downloader ?? serving(List.filled(size, 7)),
    isAllowed: allowAll,
    timeout: timeout,
  );

  test('קובץ נשמר בשמו תחת תיקיית התוסף, עם גודלו', () async {
    final file = await fetch('a.pdf', 10);

    expect(file.name, 'a.pdf');
    expect(file.size, 10);
    expect(p.basename(file.path), 'a.pdf');
    expect(cache.owns(file.path), isTrue);
    expect(cache.owns(p.join(tempDir.path, 'a.pdf')), isFalse);
  });

  test('שני קבצים באותו שם אינם דורסים זה את זה', () async {
    final first = await fetch('a.pdf', 10);
    final second = await fetch('a.pdf', 20);

    expect(first.path, isNot(second.path));
    expect(await File(first.path).length(), 10);
    expect(await File(second.path).length(), 20);
  });

  test('חריגה מהמכסה מוחקת את הוותיק ביותר ולא את החדש', () async {
    // זמני הכתיבה נקבעים במפורש: הסדר אינו תלוי בדיוק השעון של מערכת הקבצים.
    final oldest = await fetch('1.bin', 40);
    File(oldest.path).setLastModifiedSync(DateTime(2026, 1, 1));
    final middle = await fetch('2.bin', 40);
    File(middle.path).setLastModifiedSync(DateTime(2026, 1, 2));
    final newest = await fetch('3.bin', 40);

    expect(File(oldest.path).existsSync(), isFalse);
    expect(File(middle.path).existsSync(), isTrue);
    expect(File(newest.path).existsSync(), isTrue);
  });

  test('הורדה שעדיין רצה נספרת במכסה אך אינה מפונה', () async {
    final running = Directory(p.join(cache.root.path, 'p1', 'running'))
      ..createSync(recursive: true);
    File(
      p.join(running.path, PluginFileDownloadService.partialFileName),
    ).writeAsBytesSync(List.filled(90, 1));
    final done = await fetch('1.bin', 40);
    File(done.path).setLastModifiedSync(DateTime(2026, 1, 2));
    final newest = await fetch('2.bin', 40);

    expect(running.existsSync(), isTrue);
    expect(File(done.path).existsSync(), isFalse);
    expect(File(newest.path).existsSync(), isTrue);
  });

  test('שם סופי שנגמר ב-.part אינו מתחזה להורדה שרצה', () async {
    final first = await fetch('big.part', 90);
    File(first.path).setLastModifiedSync(DateTime(2026, 1, 1));
    await fetch('2.bin', 40);

    expect(File(first.path).existsSync(), isFalse);
  });

  test('תקרת הורדות מקבילות לתוסף, ומתפנה עם סיום הורדה', () async {
    final gate = Completer<void>();
    final slow = PluginFileDownloadService(
      client: MockClient.streaming((request, _) async {
        Stream<List<int>> body() async* {
          await gate.future;
          yield [1];
        }

        return http.StreamedResponse(body(), 200);
      }),
    );
    final running = [
      for (
        var i = 0;
        i < PluginRemoteFileCache.maxConcurrentFetchesPerPlugin;
        i++
      )
        fetch('$i.bin', 1, downloader: slow),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await expectLater(
      fetch('extra.bin', 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('error.too_many_requests'),
        ),
      ),
    );
    // תוסף אחר אינו מושפע.
    await fetch('other.bin', 1, pluginId: 'p2');

    gate.complete();
    await Future.wait(running);
    await fetch('after.bin', 1);
  });

  test('מזהה ריק או של נקודות בלבד אינו יוצא משורש המטמון', () async {
    final outside = File(p.join(tempDir.path, 'keep.txt'))
      ..writeAsStringSync('x');
    final file = await fetch('a.bin', 5, pluginId: '..');
    final blank = await fetch('b.bin', 5, pluginId: '');

    expect(cache.owns(file.path), isTrue);
    expect(p.isWithin(cache.root.path, file.path), isTrue);
    await cache.deleteForPlugin('..');
    await cache.deleteForPlugin('');

    expect(File(file.path).existsSync(), isFalse);
    expect(File(blank.path).existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
    expect(cache.root.existsSync(), isTrue);
  });

  test('המכסה היא לכל תוסף: הורדה של תוסף אחר אינה מפנה', () async {
    final mine = await fetch('1.bin', 90, pluginId: 'p1');
    final other = await fetch('2.bin', 90, pluginId: 'p2');

    expect(File(mine.path).existsSync(), isTrue);
    expect(File(other.path).existsSync(), isTrue);
  });

  test('כשל מוחק את תיקיית ההורדה ואינו משאיר דבר', () async {
    final failing = PluginFileDownloadService(
      client: MockClient((_) async => http.Response('nope', 404)),
    );

    await expectLater(fetch('x.pdf', 1, downloader: failing), throwsException);
    expect(leftovers('p1'), isEmpty, reason: 'אין תיקיית הורדה יתומה');
    expect(
      Directory(p.join(cache.root.path, 'p1')).existsSync(),
      isFalse,
      reason: 'גם תיקיית התוסף הריקה נמחקת',
    );
  });

  test(
    'timeout מחזיר TimeoutException ומנקה גם כשההורדה מסיימת אחריו',
    () async {
      final slow = PluginFileDownloadService(
        client: MockClient.streaming((request, _) async {
          Stream<List<int>> body() async* {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            yield [1, 2, 3];
          }

          return http.StreamedResponse(body(), 200);
        }),
      );

      await expectLater(
        fetch(
          's.bin',
          1,
          downloader: slow,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
      // ההורדה ממשיכה ברקע עד המקטע הראשון, ואז נקטעת ונמחקת.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(leftovers('p1'), isEmpty);
    },
  );

  test('delete מוחק רק קובץ שהמטמון הוריד', () async {
    final file = await fetch('a.pdf', 10);
    final outside = File(p.join(tempDir.path, 'keep.txt'))
      ..writeAsStringSync('x');

    await cache.delete(outside.path);
    expect(outside.existsSync(), isTrue);

    await cache.delete(file.path);
    expect(File(file.path).existsSync(), isFalse);
    expect(File(file.path).parent.existsSync(), isFalse);
  });

  test('delete מסיר את תיקיית ההורדה ואת תיקיית התוסף כשהתרוקנה', () async {
    final only = await fetch('1.bin', 5);
    final pluginDir = Directory(p.join(cache.root.path, 'p1'));

    await cache.delete(only.path);
    expect(pluginDir.existsSync(), isFalse);

    // עם הורדה נוספת — תיקיית התוסף נשארת.
    final first = await fetch('1.bin', 5);
    final second = await fetch('2.bin', 5);
    await cache.delete(first.path);
    expect(pluginDir.existsSync(), isTrue);
    expect(File(second.path).existsSync(), isTrue);
    expect(pluginDir.listSync(), hasLength(1));
  });

  test('פינוי מהמכסה אינו משאיר תיקיות ריקות', () async {
    final oldest = await fetch('1.bin', 60);
    File(oldest.path).setLastModifiedSync(DateTime(2026, 1, 1));
    await fetch('2.bin', 60);

    final dirs = Directory(p.join(cache.root.path, 'p1')).listSync();
    expect(dirs, hasLength(1));
    expect((dirs.single as Directory).listSync(), hasLength(1));
  });

  test('הניקוי הראשוני מסיר תיקיות ריקות (לא צעירות מדי) ותוסף ריק', () async {
    final emptyDownload = Directory(p.join(cache.root.path, 'gone', 'empty'))
      ..createSync(recursive: true);
    final fresh = Directory(p.join(cache.root.path, 'p1', 'fresh'))
      ..createSync(recursive: true);

    // עם ברירת המחדל התיקייה הריקה הטרייה נשמרת: אולי הורדה שזה עתה התחילה.
    await fetch('a.bin', 1);
    expect(fresh.existsSync(), isTrue);
    expect(emptyDownload.existsSync(), isTrue);

    final strict = PluginRemoteFileCache(
      root: cache.root,
      emptyDirGrace: Duration.zero,
    );
    await strict.fetch(
      'p1',
      Uri.parse('https://example.org/b.bin'),
      downloader: serving([1]),
      isAllowed: allowAll,
    );

    expect(fresh.existsSync(), isFalse);
    expect(emptyDownload.existsSync(), isFalse);
    expect(emptyDownload.parent.existsSync(), isFalse);
  });

  test('deleteForPlugin מוחק את התוסף בלבד', () async {
    final mine = await fetch('1.bin', 10, pluginId: 'p1');
    final other = await fetch('2.bin', 10, pluginId: 'p2');

    await cache.deleteForPlugin('p1');

    expect(File(mine.path).existsSync(), isFalse);
    expect(File(other.path).existsSync(), isTrue);
  });

  test('בהורדה הראשונה נמחקות הורדות ישנות, ורק הן', () async {
    final stale = Directory(p.join(cache.root.path, 'p1', 'old'))
      ..createSync(recursive: true);
    File(p.join(stale.path, 'a.pdf')).writeAsStringSync('x');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final recent = Directory(p.join(cache.root.path, 'p1', 'recent'))
      ..createSync(recursive: true);
    File(p.join(recent.path, 'b.pdf')).writeAsStringSync('x');

    final aging = PluginRemoteFileCache(
      root: cache.root,
      staleAfter: const Duration(milliseconds: 300),
    );
    await aging.fetch(
      'p1',
      Uri.parse('https://example.org/c.bin'),
      downloader: serving([1]),
      isAllowed: allowAll,
    );

    expect(stale.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });
}
