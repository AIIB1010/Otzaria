// רשימת בחירת המפרשים מאזינה ל-bloc בעצמה. גלילה בקורא משדרת מצב בכל שורה,
// והרשימה צריכה להיבנות מחדש רק כשמשתנה משהו שהיא מציגה.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../../helpers/memory_settings_cache.dart';

class _FakeTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _FakeTextBookBloc(super.initialState) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  const commentators = ['רש"י', 'תוספות', 'מהרש"א', 'נדיר'];
  const groups = [
    CommentatorGroup(title: 'ראשונים', commentators: ['רש"י', 'תוספות']),
    CommentatorGroup(title: 'אחרונים', commentators: ['מהרש"א', 'נדיר']),
  ];
  Link link(int line, String title) => Link(
    heRef: title,
    index1: line,
    path2: title,
    index2: 1,
    connectionType: 'commentary',
  );
  // המפרש הנדיר מקושר רק לשורה 30.
  final links = [
    for (var line = 1; line <= 40; line++) ...[
      link(line, 'רש"י'),
      link(line, 'תוספות'),
    ],
    link(30, 'נדיר'),
  ];

  Future<_FakeTextBookBloc> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = _FakeTextBookBloc(
      TextBookLoaded(
        book: TextBook(title: 'ברכות'),
        showLeftPane: false,
        content: List.generate(40, (i) => 'שורה $i'),
        fontSize: 18,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const ['רש"י'],
        commentatorGroups: groups,
        availableCommentators: commentators,
        rareCommentators: const {'נדיר'},
        links: links,
        visibleLinks: const [],
        linksByLine: buildLinksByLineMap(links),
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0, 1, 2],
        selectedIndex: null,
        pinLeftPane: false,
        searchText: '',
      ),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<TextBookBloc>.value(
        value: bloc,
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CommentatorsListView()),
          ),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  Future<void> emit(
    WidgetTester tester,
    TextBookBloc bloc,
    TextBookLoaded Function(TextBookLoaded) update,
  ) async {
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(update(bloc.state as TextBookLoaded));
    await tester.pumpAndSettle();
  }

  final rareTile = find.byWidgetPredicate(
    (w) => w is NavTreeTile && w.title == 'נדיר',
  );

  CommentatorsSelectionPanel panel(WidgetTester tester) =>
      tester.widget(find.byType(CommentatorsSelectionPanel));

  testWidgets('גלילה שאינה משנה את המפרשים המוצגים אינה בונה את הרשימה', (
    tester,
  ) async {
    final bloc = await pumpList(tester);
    final before = panel(tester);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, bloc, (s) => s.copyWith(visibleIndices: [i, i + 1]));
      expect(panel(tester), same(before));
    }
  });

  testWidgets('גלילה לשורה של מפרש נדיר מציגה אותו', (tester) async {
    final bloc = await pumpList(tester);
    expect(rareTile, findsNothing);

    await emit(tester, bloc, (s) => s.copyWith(visibleIndices: [28, 29]));
    expect(panel(tester).lineRelevantCommentators, {'נדיר'});
    expect(rareTile, findsOneWidget);

    await emit(tester, bloc, (s) => s.copyWith(visibleIndices: [2, 3]));
    expect(panel(tester).lineRelevantCommentators, isEmpty);
    expect(rareTile, findsNothing);
  });

  testWidgets('שינוי הבחירה מגיע לרשימה', (tester) async {
    final bloc = await pumpList(tester);

    await emit(
      tester,
      bloc,
      (s) => s.copyWith(activeCommentators: const ['רש"י', 'תוספות']),
    );
    expect(panel(tester).selectedCommentators, ['רש"י', 'תוספות']);
  });

  testWidgets('קישורים חדשים מגיעים לרשימה', (tester) async {
    final bloc = await pumpList(tester);
    final before = panel(tester);

    await emit(tester, bloc, (s) => s.copyWith(links: List.of(links)));
    expect(panel(tester), isNot(same(before)));
  });
}
