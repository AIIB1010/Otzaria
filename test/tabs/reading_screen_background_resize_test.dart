import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../test_helpers/memory_cache_provider.dart';

/// שינוי גודל החלון עם כמה טאבים פתוחים: טאבי רקע חיים (KeepAlive) אינם
/// מוצגים, ולכן אסור שייבנו וייפרסו מחדש בכל פריים של הגרירה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<TextBookTab> tabs;
  late _TestTabsBloc tabsBloc;

  Future<void> pumpReadingScreen(
    WidgetTester tester, {
    int tabCount = 3,
  }) async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    final focusRepository = FocusRepository()..resetForTesting();
    final bookmarkBloc = _TestBookmarkBloc();
    final personalNotesBloc = PersonalNotesBloc();
    final tourCubit = TourCubit();
    final historyBloc = _FakeHistoryBloc();
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    tabs = [
      for (var i = 0; i < tabCount; i++)
        () {
          final book = TextBook(title: 'ספר $i');
          return TextBookTab(
            book: book,
            index: 0,
            blocOverride: _TestTextBookBloc(_loadedState(book)),
          );
        }(),
    ];
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      for (final tab in tabs) {
        await tab.bloc.close();
        tab.dispose();
      }
      await tabsBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
      await bookmarkBloc.close();
      await personalNotesBloc.close();
      await tourCubit.close();
      focusRepository.resetForTesting();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: focusRepository),
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: _FakeShamorZachorDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: _FakeShamorZachorProgressProvider(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
          ],
          child: const MaterialApp(home: ReadingScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // ביקור בכל טאב כדי שייבנה ויישמר חי ברקע.
    for (var i = tabCount - 1; i >= 0; i--) {
      await showTab(tester, i);
    }
  }

  testWidgets('גרירת גודל החלון אינה בונה מחדש את תוכן טאבי הרקע', (
    tester,
  ) async {
    await pumpReadingScreen(tester);

    var backgroundRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (_isInsideBackgroundBook(element)) backgroundRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (var frame = 1; frame <= 10; frame++) {
      tester.view.physicalSize = Size(1600 - frame * 20, 900 - frame * 10);
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;

    expect(
      backgroundRebuilds,
      0,
      reason:
          'טאב רקע אינו מוצג; בנייה ופריסה שלו בכל פריים מכפילות את עלות הגרירה',
    );
  });

  testWidgets('טאב רקע מוצג בגודל החלון החדש כשעוברים אליו', (tester) async {
    await pumpReadingScreen(tester);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pump();
    await showTab(tester, 1);

    final scaffold = find.descendant(
      of: find.byType(TextBookViewerBloc).hitTestable(),
      matching: find.byType(Scaffold),
    );
    expect(tester.getSize(scaffold.first), const Size(1000, 700));
    expect(
      MediaQuery.sizeOf(tester.element(scaffold.first)),
      const Size(1000, 700),
    );
  });
}

Future<void> showTab(WidgetTester tester, int index) async {
  final controller = tester
      .widget<PageView>(find.byKey(const ValueKey('normal_tab_view')))
      .controller!;
  final bloc =
      tester.element(find.byType(ReadingScreen)).read<TabsBloc>()
          as _TestTabsBloc;
  bloc.emit(TabsState(tabs: bloc.state.tabs, currentTabIndex: index));
  await tester.pump();
  controller.jumpToPage(index);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// האם האלמנט שייך למסך ספר שבטאב שאינו הפעיל.
bool _isInsideBackgroundBook(Element element) {
  var insideBook = element.widget is TextBookViewerBloc;
  var background = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is TextBookViewerBloc) insideBook = true;
    if (widget is ExcludeFocus && widget.key is ObjectKey) {
      background = widget.excluding;
      return false;
    }
    return true;
  });
  return insideBook && background;
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
    content: [for (var i = 0; i < 100; i++) 'שורה $i'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const <Link>[],
    visibleLinks: const <Link>[],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: true,
    searchText: '',
    currentTitle: 'סימן א',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _FakeTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async => 'שורה א\nשורה ב';
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}
}
