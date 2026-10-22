import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/settings/dialogs/hidden_books_list_dialog.dart';

void main() {
  testWidgets('קפיצה לסוף הרשימה לא בונה את כל השורות שבדרך (#3022)', (
    tester,
  ) async {
    final keys = [for (var i = 0; i < 3000; i++) 'ספר ${1000 + i}'];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showHiddenBooksListDialog(
                  context: context,
                  hidden: HiddenLibrarySelection(
                    bookKeys: keys.toSet(),
                    categoryPaths: const {},
                  ),
                  titles: const {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final controller = Scrollable.of(
      tester.element(find.text(keys.first)),
    ).position;
    var builtRows = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is ListTile) builtRows++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    controller.jumpTo(controller.maxScrollExtent);
    await tester.pump();

    expect(builtRows, lessThan(100));
    expect(find.text(keys.last), findsOneWidget);
  });
}
