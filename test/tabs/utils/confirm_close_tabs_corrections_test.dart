import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// כתיבות שנכשלות לפי דגל, מעל מאגר אמיתי בזיכרון.
class _FlakyDrafts implements PluginCorrectionDraftRepository {
  _FlakyDrafts(this.inner);
  final PluginCorrectionDraftRepository inner;
  bool failWrites = false;

  @override
  Future<({String status, int? version, String? conflicts})> write({
    required String pluginId,
    required String draftId,
    required String token,
    required int revision,
    required String libraryVersion,
    required String changesJson,
    String? conflictsJson,
    int? expectedVersion,
  }) async {
    if (failWrites) throw StateError('disk full');
    return inner.write(
      pluginId: pluginId,
      draftId: draftId,
      token: token,
      revision: revision,
      libraryVersion: libraryVersion,
      changesJson: changesJson,
      conflictsJson: conflictsJson,
      expectedVersion: expectedVersion,
    );
  }

  @override
  Future<({String token, int? version, String changes, String conflicts})>
  acquire({
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
  }) => inner.acquire(
    pluginId: pluginId,
    draftId: draftId,
    bookUid: bookUid,
    bookId: bookId,
    bookSource: bookSource,
    libraryVersion: libraryVersion,
  );

  @override
  Future<void> release({
    required String pluginId,
    required String draftId,
    required String token,
  }) => inner.release(pluginId: pluginId, draftId: draftId, token: token);

  @override
  Future<void> purge(String pluginId) => inner.purge(pluginId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// תשובת שמירה נשלטת, בלי מאגר.
class _FakeService extends PluginCorrectionSessionService {
  final Set<String> unpersisted = {};
  final List<Iterable<String>> asked = [];

  @override
  String? ownerNameForTab(String tabId) => 'בודק';
  @override
  bool hasSessionForTab(String tabId) => true;
  @override
  Future<Set<String>> unpersistedTabIds(
    Iterable<String> tabIds, {
    Duration? timeout,
  }) async {
    asked.add(tabIds.toList());
    return unpersisted.intersection(tabIds.toSet());
  }
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  TextBookTab textTab() =>
      TextBookTab(book: TextBook(title: 'ברכות'), index: 0);

  group('unpersistedCorrectionTabs עם שירות אמיתי', () {
    late Database db;
    late _FlakyDrafts drafts;
    late PluginCorrectionSessionService service;
    late TextBookTab tab;
    late String tabId;

    setUp(() async {
      db = sqlite3.openInMemory();
      drafts = _FlakyDrafts(PluginCorrectionDraftRepository.direct(db));
      service = PluginCorrectionSessionService()..draftRepository = drafts;
      tab = textTab();
      tabId = PluginCorrectionSessionService.tabIdFor(tab);
      await service.begin(
        owner: 'p1',
        ownerName: 'בודק',
        tabId: tabId,
        bookId: 'ברכות',
        bookUid: 'id:1',
        libraryVersion: 'v1',
        loadSource: (_) async => 'מקור',
      );
    });

    tearDown(() async {
      drafts.failWrites = false;
      service.endAll('test');
      await service.flushAll();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      service.dispose();
      db.close();
    });

    test('טיוטה שנשמרה אינה מחזירה אזהרה', () async {
      service.editParagraph(tabId, 0, 'מקור', 'תיקון');
      final entries = await unpersistedCorrectionTabs([
        CombinedTab(rightTab: tab, leftTab: textTab()),
      ], service: service);
      expect(entries, isEmpty);
    });

    test('טיוטה שלא נשמרה מחזירה את הלשונית עם שם התוסף', () async {
      drafts.failWrites = true;
      service.editParagraph(tabId, 0, 'מקור', 'תיקון');
      final entries = await unpersistedCorrectionTabs([
        tab,
      ], service: service);
      expect(entries.single.tab, same(tab));
      expect(entries.single.message, unsavedCorrectionsMessage('בודק'));
    });
  });

  group('confirmCloseTabs', () {
    late _FakeService service;

    setUp(() => service = _FakeService());
    tearDown(() => service.dispose());

    Future<Future<bool>> pump(WidgetTester tester, TextBookTab tab) async {
      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = confirmCloseTabs(
                context,
                [tab],
                corrections: service,
              ),
              child: const Text('close'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('לשונית בלי מזהה אינה נבדקת', (tester) async {
      final result = await pump(tester, textTab());
      expect(service.asked, isEmpty);
      expect(await result, isTrue);
    });

    testWidgets('טיוטה שמורה — סוגר בלי דיאלוג', (tester) async {
      final tab = textTab();
      PluginCorrectionSessionService.tabIdFor(tab);
      final result = await pump(tester, tab);
      expect(service.asked, hasLength(1));
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
      expect(await result, isTrue);
    });

    testWidgets('טיוטה שלא נשמרה — דיאלוג עם ההודעה', (tester) async {
      final tab = textTab();
      service.unpersisted.add(PluginCorrectionSessionService.tabIdFor(tab));
      final result = await pump(tester, tab);
      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      expect(
        find.textContaining(unsavedCorrectionsMessage('בודק')),
        findsOneWidget,
      );
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
