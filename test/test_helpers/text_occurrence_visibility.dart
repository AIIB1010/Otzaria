import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// מיקום ההופעה ה-[occurrence] (מ-0) של [query] בטקסט שתחת [within],
/// יחסית לראש חלון הגלילה שמכיל אותו, כחלק מגובה החלון (0 = הקצה העליון,
/// 1 = התחתון).
double textOccurrenceViewportFraction(
  WidgetTester tester,
  Finder within,
  String query,
  int occurrence,
) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: within,
      matching: find.byWidgetPredicate((widget) => widget is RichText),
    ),
  );
  RenderParagraph? paragraph;
  var start = -1;
  var remaining = occurrence;
  for (final candidate in paragraphs) {
    final text = candidate.text.toPlainText();
    for (
      var at = text.indexOf(query);
      at >= 0;
      at = text.indexOf(query, at + query.length)
    ) {
      if (remaining-- == 0) {
        paragraph = candidate;
        start = at;
        break;
      }
    }
    if (paragraph != null) break;
  }
  expect(paragraph, isNotNull, reason: 'אין הופעה מספר $occurrence');
  final match = paragraph!
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + query.length),
      )
      .first
      .toRect()
      .shift(paragraph.localToGlobal(Offset.zero));
  final viewport = tester.getRect(
    find.ancestor(of: within, matching: find.byType(Scrollable)).first,
  );
  return (match.top - viewport.top) / viewport.height;
}

/// האם ההופעה כולה בתוך חלון הגלילה.
Matcher get isInViewport => inInclusiveRange(0.0, 0.95);
