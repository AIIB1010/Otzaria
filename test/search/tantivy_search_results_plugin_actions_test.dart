import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/plugin_search_results_actions.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialState) {
    emit(initialState);
  }

  @override
  void add(SearchEvent event) {}
}

/// מצב "אין תוצאות": כפתור `resultsAction` של התוסף מוצג ליד "ערוך חיפוש".
void main() {
  const pluginId = 'test.plugin';
  const actionLabel = 'המשך במקור החיצוני';

  late _StaticSearchBloc searchBloc;
  late _MockSettingsBloc settingsBloc;
  late SearchingTab tab;

  void registerAction() {
    addTearDown(() => PluginSearchDialogRegistry.instance.removeAll(pluginId));
    PluginSearchDialogRegistry.instance.registerPayload(pluginId, {
      'id': 'external',
      'type': 'checkbox',
      'title': 'חפש במקור חיצוני',
      'openPluginOnSubmit': true,
      'resultsAction': actionLabel,
    });
  }

  Future<void> pumpResults(
    WidgetTester tester,
    SearchState state, {
    VoidCallback? onEditSearch,
  }) async {
    searchBloc = _StaticSearchBloc(state);
    settingsBloc = _MockSettingsBloc();
    tab = SearchingTab('חיפוש', 'בדיקה', searchBloc: searchBloc);
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    addTearDown(() async {
      tab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SizedBox(
              height: 500,
              child: TantivySearchResults(tab: tab, onEditSearch: onEditSearch),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const noResults = SearchState(searchQuery: 'בדיקה', totalResults: 0);

  List<SearchResult> twoResults() => [
    for (var i = 0; i < 2; i++)
      SearchResult(
        id: BigInt.from(i + 1),
        title: 'ספר ${i + 1}',
        reference: 'סימן ${i + 1}',
        text: 'טקסט בדיקה $i',
        segment: BigInt.from(i),
        isPdf: false,
        filePath: 'book_$i.txt',
        mergedCount: 1,
        merged: const [],
        textStatus: TextStatus.ok,
        continuesToNextLine: false,
      ),
  ];

  testWidgets('אין תוצאות: כפתור התוסף מוצג לצד "ערוך חיפוש"', (tester) async {
    registerAction();
    await pumpResults(tester, noResults, onEditSearch: () {});

    expect(find.text('אין תוצאות'), findsOneWidget);
    expect(find.text('ערוך חיפוש'), findsOneWidget);
    expect(find.text(actionLabel), findsOneWidget);
  });

  testWidgets('אין תוצאות בלי תוסף רשום: רק "ערוך חיפוש"', (tester) async {
    await pumpResults(tester, noResults, onEditSearch: () {});

    expect(find.text('ערוך חיפוש'), findsOneWidget);
    expect(find.text(actionLabel), findsNothing);
  });

  testWidgets('בלי onEditSearch כפתור התוסף עדיין מוצג', (tester) async {
    registerAction();
    await pumpResults(tester, noResults);

    expect(find.text('ערוך חיפוש'), findsNothing);
    expect(find.text(actionLabel), findsOneWidget);
  });

  testWidgets('בלי כפתור עריכה ובלי תוסף רשום אין action ריק במסך', (
    tester,
  ) async {
    await pumpResults(tester, noResults);

    expect(find.text('אין תוצאות'), findsOneWidget);
    expect(find.byType(PluginSearchResultsActions), findsNothing);
  });

  testWidgets('הגבלת חיפוש אינה מציגה את כפתור התוסף', (tester) async {
    registerAction();
    await pumpResults(
      tester,
      const SearchState(
        searchQuery: 'בדיקה',
        totalResults: 0,
        resultsTruncated: true,
      ),
      onEditSearch: () {},
    );

    expect(find.text('הגעת למגבלת אפשרויות החיפוש'), findsOneWidget);
    expect(find.text(actionLabel), findsNothing);
  });

  group('אחרי התוצאות', () {
    testWidgets('כל התוצאות נטענו: הכפתור מוצג אחרי התוצאה האחרונה', (
      tester,
    ) async {
      registerAction();
      await pumpResults(
        tester,
        SearchState(
          searchQuery: 'בדיקה',
          totalResults: 2,
          results: twoResults(),
        ),
      );

      expect(find.text('ספר 2'), findsOneWidget);
      expect(find.text(actionLabel), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(actionLabel)).dy,
        greaterThan(tester.getTopLeft(find.text('ספר 2')).dy),
      );
    });

    testWidgets('יש עוד תוצאות לטעון: אין כפתור אחרי הרשימה', (tester) async {
      registerAction();
      await pumpResults(
        tester,
        SearchState(
          searchQuery: 'בדיקה',
          totalResults: 5,
          results: twoResults(),
        ),
      );

      expect(find.text('ספר 2'), findsOneWidget);
      expect(find.text(actionLabel), findsNothing);
    });

    testWidgets('הספירה עדיין בעיצומה: אין כפתור', (tester) async {
      registerAction();
      await pumpResults(
        tester,
        SearchState(
          searchQuery: 'בדיקה',
          totalResults: 2,
          results: twoResults(),
          isLoading: true,
          isCounting: true,
        ),
      );

      expect(find.text(actionLabel), findsNothing);
    });
  });
}
