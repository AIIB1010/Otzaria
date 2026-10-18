import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/markdown_html_body.dart';

void main() {
  testWidgets('מציג רשימה מקוננת, הדגשה וקישור בלי תחביר Markdown גולמי', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownHtmlBody(
              '## כותרת\n\n'
              '* **0.9.98**\n'
              '  - **מסד מוקטן** בחצי\n'
              '  - [אתר](https://example.com)\n',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rendered = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((t) => t.text.toPlainText())
        .join('\n');
    expect(rendered, contains('כותרת'));
    expect(rendered, contains('0.9.98'));
    expect(rendered, contains('מסד מוקטן'));
    expect(rendered, contains('אתר'));
    expect(rendered, isNot(contains('**')));
    expect(rendered, isNot(contains('](')));
    expect(rendered, isNot(contains('##')));
  });
}
