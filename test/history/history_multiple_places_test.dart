import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';

import '../helpers/memory_settings_cache.dart';

class _MemoryHistoryRepository extends HistoryRepository {
  _MemoryHistoryRepository([List<Bookmark> items = const []])
    : stored = List<Bookmark>.from(items);

  List<Bookmark> stored;

  @override
  Future<List<Bookmark>> load() async => stored;

  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async {
    stored = List<Bookmark>.from(apply(List<Bookmark>.from(stored)));
    return List<Bookmark>.from(stored);
  }
}

class _FakeNavigationRepository implements NavigationRepository {
  @override
  Future<bool> checkLibraryIsEmpty() async => false;
  @override
  Future<void> refreshLibrary() async {}
}

final _book = TextBook(id: 7, title: 'משנה ברורה');

Bookmark _entry(int index, {String? slot}) => Bookmark(
  ref: 'משנה ברורה $index',
  book: _book,
  index: index,
  historySlot: slot,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('Bookmark.historyKey', () {
    test('רשומה בלי slot שומרת את המפתח הישן', () {
      expect(_entry(1).historyKey, 'book:id:7');
    });

    test('slot שונה = רשומה נפרדת לאותו ספר', () {
      expect(
        _entry(1, slot: 'a').historyKey,
        isNot(_entry(1, slot: 'b').historyKey),
      );
      expect(_entry(1, slot: 'a').historyKey, _entry(9, slot: 'a').historyKey);
    });

    test('ה-slot שורד JSON', () {
      final restored = Bookmark.fromJson(_entry(3, slot: 'a').toJson());
      expect(restored.historySlot, 'a');
      expect(_entry(3).toJson().containsKey('historySlot'), isFalse);
    });
  });

  group('HistoryBloc', () {
    Future<HistoryBloc> loadedBloc() async {
      final bloc = HistoryBloc(_MemoryHistoryRepository());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state is HistoryLoaded);
      return bloc;
    }

    Future<void> add(HistoryBloc bloc, Bookmark entry) async {
      bloc.add(BulkAddHistory([entry]));
      await bloc.stream.firstWhere(
        (state) => identical(state.history.firstOrNull, entry),
      );
    }

    test('שני מקומות באותו ספר נשמרים שניהם', () async {
      final bloc = await loadedBloc();
      final first = _entry(10);
      final second = _entry(500, slot: 'b');

      await add(bloc, first);
      await add(bloc, second);

      expect(bloc.state.history, [second, first]);
    });

    test('אותו slot מעדכן את רשומתו ולא מוסיף', () async {
      final bloc = await loadedBloc();
      final other = _entry(10);
      await add(bloc, other);
      await add(bloc, _entry(500, slot: 'b'));
      final moved = _entry(520, slot: 'b');

      await add(bloc, moved);

      expect(bloc.state.history, [moved, other]);
    });
  });

  group('טאבים', () {
    test('ה-slot נשמר ב-JSON ובהעתקה של טאב טקסט ו-PDF', () {
      final text = TextBookTab(book: _book, index: 3)..historySlot = 'a';
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ברכות', path: '/b.pdf'),
        pageNumber: 2,
      )..historySlot = 'p';
      addTearDown(text.dispose);
      addTearDown(pdf.dispose);

      final restoredText = TextBookTab.fromJson(text.toJson());
      final restoredPdf = PdfBookTab.fromJson(pdf.toJson());
      final copiedText = OpenedTab.from(text);
      final copiedPdf = OpenedTab.from(pdf);
      addTearDown(restoredText.dispose);
      addTearDown(restoredPdf.dispose);
      addTearDown(copiedText.dispose);
      addTearDown(copiedPdf.dispose);

      expect(restoredText.historySlot, 'a');
      expect(restoredPdf.historySlot, 'p');
      expect(copiedText.historySlot, 'a');
      expect(copiedPdf.historySlot, 'p');
    });

    test('פתיחה מרשומת היסטוריה לוקחת את ה-slot שלה', () {
      final tab = tabFromBookmark(_entry(500, slot: 'b'));
      addTearDown(tab.dispose);
      expect(tab.historySlot, 'b');
    });

    test('newHistorySlot אינו חוזר על עצמו גם ברצף מהיר', () {
      final slots = List.generate(50, (_) => OpenedTab.newHistorySlot());
      expect(slots.toSet(), hasLength(50));
    });
  });

  group('TabsBloc ו-BookOpenCoordinator', () {
    late Directory tempDir;
    late TabsBloc tabsBloc;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('history_places_test');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>('tabs');
      tabsBloc = TabsBloc(repository: TabsRepository());
    });

    tearDown(() async {
      await tabsBloc.close();
      await Hive.deleteFromDisk();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<BookOpenCoordinator> coordinator(List<Bookmark> history) async {
      final historyBloc = HistoryBloc(_MemoryHistoryRepository(history));
      final navigationBloc = NavigationBloc(
        repository: _FakeNavigationRepository(),
        tabsRepository: TabsRepository(),
      );
      addTearDown(historyBloc.close);
      addTearDown(navigationBloc.close);
      await historyBloc.stream.firstWhere(
        (state) => state.history.length == history.length,
      );
      return BookOpenCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: historyBloc,
        navigationBloc: navigationBloc,
      );
    }

    test('פתיחת ספר ממשיכה את רשומתו האחרונה כשאינה פתוחה', () async {
      final opener = await coordinator([_entry(500, slot: 'b'), _entry(10)]);

      final tab = opener.buildTab(_book, 0, '');
      addTearDown(tab.dispose);

      expect(tab.historySlot, 'b');
      expect((tab as TextBookTab).index, 500);
    });

    test('ספר שכבר פתוח בטאב אחר מקבל רשומה חדשה', () async {
      final open = TextBookTab(book: _book, index: 500)..historySlot = 'b';
      tabsBloc.add(AddTab(open));
      await pumpEventQueue();
      final opener = await coordinator([_entry(500, slot: 'b')]);

      // תוצאת חיפוש בספר הפתוח: טאב חדש, שאינו דורס את מקום הטאב הפתוח.
      tabsBloc.add(AddTab(opener.buildTab(_book, 40, '', explicitIndex: true)));
      await pumpEventQueue();

      final added = tabsBloc.state.tabs.firstWhere((t) => t != open);
      expect(added.historySlot, isNotNull);
      expect(added.historySlot, isNot('b'));
      expect(open.historySlot, 'b');
    });

    test('טאב ללא slot ליד טאב ללא slot של אותו ספר מקבל slot', () async {
      final open = TextBookTab(book: _book, index: 10);
      final second = TextBookTab(book: _book, index: 900);
      tabsBloc.add(AddTab(open));
      tabsBloc.add(AddTab(second));
      await pumpEventQueue();

      expect(open.historySlot, isNull);
      expect(second.historySlot, isNotNull);
    });

    test('טאב של ספר אחר אינו מקבל slot חדש', () async {
      tabsBloc.add(AddTab(TextBookTab(book: _book, index: 10)));
      final other = TextBookTab(
        book: TextBook(id: 8, title: 'ספר אחר'),
        index: 0,
      );
      tabsBloc.add(AddTab(other));
      await pumpEventQueue();

      expect(other.historySlot, isNull);
    });

    test('שכפול טאב יוצר מקום נפרד בהיסטוריה', () async {
      final original = TextBookTab(book: _book, index: 500)..historySlot = 'b';
      tabsBloc.add(AddTab(original));
      await pumpEventQueue();

      tabsBloc.add(CloneTab(original));
      await pumpEventQueue();

      final copy = tabsBloc.state.tabs.firstWhere((t) => t != original);
      expect(copy.historySlot, isNotNull);
      expect(copy.historySlot, isNot('b'));
      expect(original.historySlot, 'b');
    });
  });

  test('מיזוג גיבוי משמר את שני המקומות של אותו ספר', () {
    Map<String, dynamic> raw(int index, {String? slot}) =>
        _entry(index, slot: slot).toJson();
    final merged = BackupMerge.merge(
      {
        'history': [raw(10)],
      },
      {
        'history': [raw(500, slot: 'b')],
      },
      olderTimestamp: DateTime(2025, 1, 1),
      newerTimestamp: DateTime(2025, 6, 1),
      now: DateTime(2025, 7, 1),
    );
    expect(merged['history'] as List, hasLength(2));
  });
}
