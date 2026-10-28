// issue #3336: צומת סמנטי של AdaptiveSidePane מעל התוכן נוצר ומתמזג לפי התוכן,
// וגשר הנגישות של Windows קורס על ה-reparent המקונן שזה גורם (flutter#175041).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';

void main() {
  Widget host({required bool float}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Text('toolbar'),
          Expanded(
            child: AdaptiveSidePane(
              isOpen: true,
              alignment: AlignmentDirectional.centerEnd,
              paneWidth: 300,
              minMainContentWidth: 420,
              onClose: () {},
              floatOverContent: float,
              mainContent: const Text('main'),
              paneContent: const Column(
                children: [
                  Text('pane 0', textDirection: TextDirection.ltr),
                  Text('pane 1'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  for (final float in [false, true]) {
    testWidgets(
      'החלונית אינה מוסיפה צומת סמנטי מעל התוכן (float=$float, issue #3336)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(float: float));
        await tester.pumpAndSettle();

        final toolbar = tester.getSemantics(find.text('toolbar'));
        for (final text in ['pane 0', 'pane 1', 'main']) {
          final node = tester.getSemantics(find.text(text));
          expect(node.label, text, reason: 'לא מוזג לצומת משותף');
          expect(
            node.parent,
            same(toolbar.parent),
            reason: 'אין צומת ביניים מעל $text',
          );
        }
        handle.dispose();
      },
    );
  }
}
