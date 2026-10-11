import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

/// מספק CalendarState קבוע בלי להריץ את אתחול ה-cubit האמיתי.
class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('חיצים ו-Tab עוברים מהספר שנלחץ לשכנו ומציגים אותו בתצוגה '
      'המקדימה (issue #2010)', (tester) async {
    final library = Library(categories: []);
    final books = [
      for (var i = 0; i < 6; i++) TextBook(title: 'ספר $i', author: 'מחבר'),
    ];
    final libraryBloc = await _pumpBrowser(
      tester,
      LibraryState(
        library: library,
        currentCategory: library,
        searchResults: books,
        searchQuery: 'ספר',
      ),
    );

    await tester.tap(find.text('ספר 1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_focusedBook(), 'ספר 1', reason: 'החיצים ממשיכים מהספר שנלחץ');

    // RTL: חץ שמאלה = הספר הבא בסדר הקריאה.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_focusedBook(), 'ספר 2');
    verify(() => libraryBloc.add(SelectBookForPreview(books[2]))).called(1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusedBook(), 'ספר 3');
    verify(() => libraryBloc.add(SelectBookForPreview(books[3]))).called(1);
  });

  testWidgets('קטגוריה ארוכה בונה רק את הכרטיסים שבתצוגה, וחץ-מטה מהחיפוש '
      'אחרי גלילה עמוקה חוזר לספר הראשון', (tester) async {
    const count = 300;
    final library = Library(categories: []);
    final category = Category(
      title: 'קטגוריה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [
        for (var i = 0; i < count; i++)
          TextBook(title: 'ספר $i', author: 'מחבר', order: i),
      ],
      parent: library,
    );
    final focusRepository = FocusRepository();
    await _pumpBrowser(
      tester,
      LibraryState(library: library, currentCategory: category),
      focusRepository: focusRepository,
    );

    final built = find.byType(BookGridItem).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(count ~/ 5));

    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(MyGridView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(find.text('ספר 0'), findsNothing);

    focusRepository.requestLibrarySearchFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(position.pixels, 0);
    expect(_focusedBook(), 'ספר 0');
  });
}

String? _focusedBook() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<BookGridItem>()
    ?.book
    .title;

/// בונה LibraryBrowser מלא עם blocs מדומים במצב [initialState].
Future<LibraryBloc> _pumpBrowser(
  WidgetTester tester,
  LibraryState initialState, {
  FocusRepository? focusRepository,
}) async {
  final libraryBloc = _MockLibraryBloc();
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: initialState,
  );
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  whenListen(
    navigationBloc,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.library),
  );
  whenListen(
    libraryUpdateBloc,
    const Stream<LibraryUpdateState>.empty(),
    initialState: const LibraryUpdateState(),
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await libraryBloc.close();
    await settingsBloc.close();
    await navigationBloc.close();
    await libraryUpdateBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      // כמו באפליקציה — בלי GlobalWidgetsLocalizations הכיוון היה LTR.
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: MultiProvider(
        providers: [
          Provider<FocusRepository>.value(
            value: focusRepository ?? FocusRepository(),
          ),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
          BlocProvider<CalendarCubit>.value(value: calendarCubit),
        ],
        child: const LibraryBrowser(),
      ),
    ),
  );
  await tester.pump();
  // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
  tester.takeException();
  return libraryBloc;
}
