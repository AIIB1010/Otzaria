import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_fetcher.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_store.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

LibraryRelease _release(
  String tag, {
  bool notes = true,
  bool prerelease = false,
  bool draft = false,
}) => LibraryRelease(
  tag: tag,
  isPrerelease: prerelease,
  isDraft: draft,
  publishedAt: null,
  assets: [
    const ReleaseAsset(
      name: 'seforim.db.zst',
      downloadUrl: 'https://x/db',
      size: 1,
    ),
    if (notes)
      ReleaseAsset(
        name: LibraryChangesFetcher.assetName,
        downloadUrl: 'https://dl/$tag/library-changes.md',
        size: 100,
      ),
  ],
);

void main() {
  group('releasesInRange', () {
    final releases = [
      _release('v31-20261001000000', notes: false),
      _release('v32-20261010190601'),
      _release('v33-20261020000000'),
      _release('vectors-v33-20261020000000', prerelease: true),
      _release('v34-20261101000000', draft: true),
      _release('v35-20261110000000'),
      _release('v36-20261120000000'),
    ];

    test('(from, to] בלבד, יציבים עם הקובץ, החדש קודם', () {
      final picked = LibraryChangesFetcher.releasesInRange(releases, 32, 35);
      expect(picked.map((e) => e.$1.tag), [
        'v35-20261110000000',
        'v33-20261020000000',
      ]);
    });

    test('release בלי הקובץ (ישן) אינו נבחר', () {
      expect(LibraryChangesFetcher.releasesInRange(releases, 30, 31), isEmpty);
    });

    test('מוגבל ל-maxReleases החדשים', () {
      final many = [
        for (var v = 40; v < 60; v++) _release('v$v-20261001000000'),
      ];
      final picked = LibraryChangesFetcher.releasesInRange(many, 39, 59);
      expect(picked, hasLength(LibraryChangesFetcher.maxReleases));
      expect(picked.first.$1.tag, 'v59-20261001000000');
    });
  });

  group('fetch', () {
    late Directory root;
    late LibraryChangesStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('library_changes_fetch_');
      store = LibraryChangesStore(dataRootProvider: () async => root.path);
    });

    tearDown(() => root.deleteSync(recursive: true));

    LibraryChangesFetcher fetcher(
      MockClientHandler handler, {
      Future<List<LibraryRelease>> Function()? releases,
    }) => LibraryChangesFetcher(
      store: store,
      fetchReleases:
          releases ??
          () async => [
            _release('v33-20261020000000'),
            _release('v34-20261101000000'),
            _release('v35-20261110000000'),
          ],
      clientFactory: () => MockClient(handler),
      timeout: const Duration(milliseconds: 200),
    );

    test('404 ו-timeout מדולגים; השאר נשמרים', () async {
      final saved = await fetcher((request) async {
        final url = request.url.toString();
        if (url.contains('v33')) return http.Response('', 404);
        if (url.contains('v34')) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        return http.Response.bytes(utf8.encode('# גרסת ספרייה 35\n'), 200);
      }).fetch(fromVersion: 32, toVersion: 35);

      expect(saved, 1);
      final notes = await store.readPending();
      expect(notes.map((n) => n.releaseTag), ['v35-20261110000000']);
      expect(notes.single.markdown, '# גרסת ספרייה 35\n');
    });

    test('כשל ברשימת ה-releases אינו זורק', () async {
      final saved = await fetcher(
        (_) async => http.Response('x', 200),
        releases: () async => throw const SocketException('offline'),
      ).fetch(fromVersion: 32, toVersion: 35);
      expect(saved, 0);
      expect(await store.readPending(), isEmpty);
    });

    test('גרסה מקומית לא ידועה או טווח ריק — לא פונים לרשת', () async {
      var calls = 0;
      final f = fetcher((_) async {
        calls++;
        return http.Response('x', 200);
      });
      expect(await f.fetch(fromVersion: 0, toVersion: 35), 0);
      expect(await f.fetch(fromVersion: 35, toVersion: 35), 0);
      expect(calls, 0);
    });

    test('release שכבר נשמר אינו מורד שוב', () async {
      await store.writePending('v35-20261110000000', 'קיים');
      final requested = <String>[];
      await fetcher((request) async {
        requested.add(request.url.toString());
        return http.Response('', 404);
      }).fetch(fromVersion: 34, toVersion: 35);
      expect(requested, isEmpty);
    });
  });
}
