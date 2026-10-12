import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_notes.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryChangesStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('library_changes_');
    store = LibraryChangesStore(dataRootProvider: () async => root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  File pending(String tag) =>
      File(p.join(root.path, 'pending_library_changes', '$tag.md'));

  test('תיקייה חסרה — אין הערות ואין שגיאה', () async {
    expect(await store.readPending(), isEmpty);
    expect(await store.readAll(), isEmpty);
    expect(await store.hasAny(), isFalse);
    await store.markSeen(const []);
  });

  test('כתיבה אטומית: נשאר רק הקובץ הסופי, ודריסה מחליפה תוכן', () async {
    await store.writePending('v33-20261020000000', 'ישן');
    await store.writePending('v33-20261020000000', 'חדש');
    final files = Directory(
      p.join(root.path, 'pending_library_changes'),
    ).listSync().map((e) => p.basename(e.path));
    expect(files, ['v33-20261020000000.md']);
    expect(pending('v33-20261020000000').readAsStringSync(), 'חדש');
  });

  test('תג עם מפריד נתיב נדחה', () async {
    expect(() => store.writePending('../x', 'a'), throwsArgumentError);
    expect(() => store.writePending(r'a\b', 'a'), throwsArgumentError);
  });

  test(
    'ממוין לפי גרסה (לא לפי מחרוזת), החדש קודם; tmp ו-BOM מתעלמים',
    () async {
      await store.writePending('v9-20260101000000', '# 9');
      await store.writePending('v34-20261101000000', '# 34');
      await store.writePending('v33-20261020000000', '# 33');
      pending('v35-20261201000000').writeAsStringSync('﻿# 35');
      File(
        '${pending('v36-20261201000000').path}.tmp',
      ).writeAsStringSync('partial');

      final notes = await store.readPending();
      expect(notes.map((n) => n.version), [35, 34, 33, 9]);
      expect(notes.first.markdown, '# 35');
    },
  );

  test('markSeen מעביר ל-seen ושומר רק את 10 האחרונות', () async {
    for (var v = 31; v <= 42; v++) {
      await store.writePending('v$v-20261001000000', '# $v');
    }
    await store.markSeen(await store.readPending());

    expect(await store.readPending(), isEmpty);
    final seen = await store.readSeen();
    expect(seen.map((n) => n.version), [for (var v = 42; v >= 33; v--) v]);
    expect(await store.contains('v42-20261001000000'), isTrue);
    expect(await store.contains('v31-20261001000000'), isFalse);
  });

  test('readAll מאחד ממתינות ושנצפו, החדש קודם', () async {
    await store.writePending('v33-20261020000000', '# 33');
    await store.markSeen(await store.readPending());
    await store.writePending('v34-20261101000000', '# 34');
    final all = await store.readAll();
    expect(all.map((n) => n.version), [34, 33]);
  });

  group('LibraryChangesNotes.showPending', () {
    testWidgets('מציג את הממתינות ובסגירה מעביר ל-seen', (tester) async {
      await tester.runAsync(() async {
        await store.writePending('v33-20261020000000', '# 33');
        await store.writePending('v34-20261101000000', '# 34');
      });
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      List<int>? shown;
      final notes = LibraryChangesNotes(
        store: store,
        contextProvider: () => context,
        showDialog: (_, list) async =>
            shown = [for (final n in list) n.version],
      );
      await tester.runAsync(notes.showPending);
      expect(shown, [34, 33]);
      final (pendingAfter, seen) = (await tester.runAsync(
        () async => (await store.readPending(), await store.readSeen()),
      ))!;
      expect(pendingAfter, isEmpty);
      expect(seen, hasLength(2));
    });

    test('בלי Navigator ההערות נשארות ממתינות', () async {
      await store.writePending('v33-20261020000000', '# 33');
      var shown = false;
      final notes = LibraryChangesNotes(
        store: store,
        contextProvider: () => null,
        showDialog: (_, _) async => shown = true,
      );
      await notes.showPending();
      expect(shown, isFalse);
      expect(await store.readPending(), hasLength(1));
    });
  });
}
