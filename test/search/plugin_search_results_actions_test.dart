import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder, SearchScope, WordMatchMode;

import '../support/search_engine_test_init.dart';

class _FakeWindowController extends Fake implements AppWindowController {}

class _FakeWindowGeometry extends Fake implements AppWindowGeometry {}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialState) {
    emit(initialState);
  }

  void set(SearchState state) => emit(state);

  @override
  void add(SearchEvent event) {}
}

/// כפתור `resultsAction` בטאב החיפוש: מוצג רק אחרי שהחיפוש הסתיים, ולחיצה
/// מעבירה לתוסף את אותו חיפוש באותו חוזה של שליחת הדיאלוג.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  late _StaticSearchBloc searchBloc;
  late SearchingTab tab;
  late PluginSearchDialogRegistry registry;
  late List<(String, Map<String, dynamic>)> launches;

  const finished = SearchState(
    searchQuery: 'שבת',
    negativeQuery: 'גוי',
    configuration: SearchConfiguration(
      searchMode: SearchMode.advanced,
      distance: 2,
      currentFacets: ['/הלכה'],
      searchScopeFacets: ['/הלכה'],
    ),
  );

  setUp(() {
    searchBloc = _StaticSearchBloc(finished);
    tab = SearchingTab('חיפוש', 'שבת', searchBloc: searchBloc);
    tab.negativeQueryController.text = 'גוי';
    registry = PluginSearchDialogRegistry.forTesting();
    registry.registerPayload('test.plugin', {
      'id': 'external',
      'type': 'checkbox',
      'title': 'חפש במקור חיצוני',
      'openPluginOnSubmit': true,
      'resultsAction': 'המשך במקור החיצוני',
      'visibleInModes': ['advanced'],
    });
    launches = [];
  });

  tearDown(() async {
    registry.dispose();
    tab.dispose();
    await searchBloc.close();
  });

  Future<void> pump(WidgetTester tester, {bool iconOnly = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginSearchResultsActions(
            tab: tab,
            iconOnly: iconOnly,
            registry: registry,
            launcher: (pluginId, payload) => launches.add((pluginId, payload)),
          ),
        ),
      ),
    );
  }

  testWidgets('מוצג רק אחרי שהחיפוש הסתיים, גם בלי תוצאות', (tester) async {
    final button = find.text('המשך במקור החיצוני');
    Future<void> emit(SearchState state) async {
      searchBloc.set(state);
      await tester.pumpAndSettle();
    }

    await pump(tester);
    expect(button, findsOneWidget);

    await emit(finished.copyWith(isLoading: true));
    expect(button, findsNothing);

    await emit(finished.copyWith(errorMessage: 'נכשל'));
    expect(button, findsNothing);

    await emit(finished.copyWith(searchQuery: ''));
    expect(button, findsNothing);

    await emit(finished);
    expect(button, findsOneWidget);
  });

  testWidgets('שורה בלי resultsAction או מחוץ למצב החיפוש אינה מציגה כפתור', (
    tester,
  ) async {
    registry.registerPayload('other.plugin', {
      'id': 'no-action',
      'type': 'checkbox',
      'title': 'בלי כפתור',
      'openPluginOnSubmit': true,
    });
    searchBloc.set(
      finished.copyWith(
        configuration: finished.configuration.copyWith(
          searchMode: SearchMode.exact,
        ),
      ),
    );
    await pump(tester);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byTooltip('המשך במקור החיצוני'), findsNothing);
  });

  testWidgets('בסרגל צר מוצג אייקון בלבד, והכותרת ב-tooltip', (tester) async {
    await pump(tester, iconOnly: true);
    expect(find.text('המשך במקור החיצוני'), findsNothing);
    expect(find.byTooltip('המשך במקור החיצוני'), findsOneWidget);
  });

  testWidgets('כמה כפתורי תוצאות חוקיים נשארים בתוך רוחב הסרגל', (
    tester,
  ) async {
    for (var i = 0; i < 4; i++) {
      registry.registerPayload('many.plugin', {
        'id': 'external-$i',
        'type': 'checkbox',
        'title': 'מקור חיצוני $i',
        'openPluginOnSubmit': true,
        'resultsAction': 'המשך לחיפוש במקור חיצוני נוסף מספר $i',
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: PluginSearchResultsActions(tab: tab, registry: registry),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final last = find.text('המשך לחיפוש במקור חיצוני נוסף מספר 3');
    await tester.ensureVisible(last);
    expect(tester.getRect(last).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(last).right, lessThanOrEqualTo(600));
  });

  testWidgets(
    'כפתור התוצאות שומר את חלון המקור גם כשחלון אחר פעיל',
    (tester) async {
      final origin = AppWindowKeys();
      final active = AppWindowKeys();
      final originNavigations = <String>[];
      final activeNavigations = <String>[];
      final pageLauncher = PluginPageLauncher.instance;
      pageLauncher.register(origin, originNavigations.add);
      pageLauncher.register(active, activeNavigations.add);
      AppWindowKeys.activate(active);
      final viewId = tester.view.viewId;
      pageLauncher.markPageReady('test.plugin', viewId: viewId + 1);
      addTearDown(() {
        pageLauncher.markPageClosed('test.plugin');
        pageLauncher.forgetWindow(viewId);
        pageLauncher.unregister(origin, originNavigations.add);
        pageLauncher.unregister(active, activeNavigations.add);
        AppWindowKeys.resetForTest();
      });
      await tester.pumpWidget(
        AppWindowScope(
          controller: _FakeWindowController(),
          geometry: _FakeWindowGeometry(),
          keys: origin,
          child: MaterialApp(
            home: Scaffold(
              body: PluginSearchResultsActions(tab: tab, registry: registry),
            ),
          ),
        ),
      );
      await tester.tap(find.text('המשך במקור החיצוני'));
      await tester.pump();
      expect(originNavigations, ['test.plugin']);
      expect(activeNavigations, isEmpty);
      expect(pageLauncher.hasPendingFor('test.plugin'), isTrue);
    },
    skip: !engineReady,
  );

  testWidgets(
    'לחיצה שולחת search.requested עם השאילתה, ההיקף והשלילה של הטאב',
    (tester) async {
      searchBloc.set(
        finished.copyWith(
          searchQuery: 'שבת שלום',
          negativeQuery: 'גוי נכרי',
          configuration: finished.configuration.copyWith(
            sortBy: ResultsOrder.relevance,
            numResults: 250,
            proximityScope: SearchScope.sameSection,
            wordMatchMode: WordMatchMode.atLeast,
            wordMatchCount: 2,
            resultGrouping: ResultGroupingMode.identicalText,
          ),
        ),
      );
      tab.globalSearchOptions['קידומות דקדוקיות'] = true;
      tab.negativeGlobalSearchOptions['חלק ממילה'] = true;
      tab.alternativeWords[1] = ['מנוחה'];
      tab.negativeAlternativeWords[0] = ['זר'];
      tab.spacingValues['0-1'] = '3';
      tab.negativeSpacingValues['0-1'] = '4';
      await pump(tester);
      await tester.tap(find.text('המשך במקור החיצוני'));
      await tester.pump();

      expect(launches, hasLength(1));
      expect(launches.single.$1, 'test.plugin');
      expect(launches.single.$2['itemId'], 'external');
      final request = launches.single.$2['request'] as Map<String, dynamic>;
      expect(request['query'], 'שבת שלום');
      expect(request['mode'], 'advanced');
      expect(request['distance'], 2);
      expect(request['facets'], ['/הלכה']);
      expect(request['negativeQuery'], 'גוי נכרי');
      expect(request['order'], 'relevance');
      expect(request['limit'], 250);
      expect(request['proximityScope'], 'sameSection');
      expect(request['wordMatchMode'], 'atLeast');
      expect(request['wordMatchCount'], 2);
      expect(request['grouping'], 'identicalText');
      expect(request['alternativeWords'], {
        '1': ['מנוחה'],
      });
      expect(request['negativeAlternativeWords'], {
        '0': ['זר'],
      });
      expect(request['customSpacing'], {'0-1': '3'});
      expect(request['negativeCustomSpacing'], {'0-1': '4'});
      expect(request['wordOptions'], {
        'שבת_0': {'קידומות דקדוקיות': true},
        'שלום_1': {'קידומות דקדוקיות': true},
      });
      expect(request['negativeWordOptions'], {
        'גוי_0': {'חלק ממילה': true},
        'נכרי_1': {'חלק ממילה': true},
      });
    },
    skip: !engineReady,
  );
}
