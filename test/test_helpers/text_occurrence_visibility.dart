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
  final paragraph = tester
      .renderObjectList<RenderParagraph>(
        find.descendant(
          of: within,
          matching: find.byWidgetPredicate((widget) => widget is RichText),
        ),
      )
      .firstWhere((p) => p.text.toPlainText().contains(query));
  final text = paragraph.text.toPlainText();
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = text.indexOf(query, start + 1);
  }
  expect(start, isNonNegative, reason: 'אין הופעה מספר $occurrence');
  final match = paragraph
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
