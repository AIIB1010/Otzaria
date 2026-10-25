import 'package:flutter/rendering.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:positioned_sliver_list/positioned_list.dart'
    show TargetRectResolver;

/// ספירת התאמות חיפוש בתוכן מפרש.
///
/// הספירה תמיד על טקסט ללא ניקוד — תואמת את ה-regex הגמיש לניקוד של ההדגשה.
/// [partialWordMatch] חייב לשקף את `partialWordHighlight` שאיתו התוכן
/// מרונדר — אחרת המונה קטן ממספר ההדגשות שנראות בפועל (issue #1055).
int countCommentarySearchMatches({
  required String content,
  required String query,
  required TextDisplayProfile displayProfile,
  required bool partialWordMatch,
}) {
  return TextRendererService.countSearchMatches(
    _searchableText(content, displayProfile),
    query,
    partialWordMatch: partialWordMatch,
  );
}

/// מכוון את הקפיצה לתוצאת חיפוש אל ההתאמה ה-[matchIndex] (בספירה של
/// [countCommentarySearchMatches]) בתוך פריט המפרש, ולא אל ראשו: במפרש ארוך
/// ההתאמה נשארה מחוץ למסך (issue #2534).
TargetRectResolver? commentarySearchMatchTarget({
  required String? content,
  required String query,
  required TextDisplayProfile displayProfile,
  required int matchIndex,
}) {
  if (content == null) return null;
  final text = _searchableText(content, displayProfile);
  final end = _matchEnd(text, query, matchIndex);
  final visibleLength = utils.stripHtmlIfNeeded(text).length;
  if (end == null || visibleLength == 0) return null;
  // התו האחרון של ההתאמה, ולא הסוף שלה: בסוף שורה הסוף כבר בשורה הבאה.
  final fraction =
      utils.stripHtmlIfNeeded(text.substring(0, end - 1)).length /
      visibleLength;
  return (_, box) {
    // התו המקביל בטקסט המרונדר, ולא אותו חלק מגובה הפריט: הגובה כולל כותרת
    // וריפוד, ושבירת השורות מזיזה את ההתאמה בשורות שלמות.
    final paragraphs = <RenderParagraph>[];
    void collect(RenderObject child) {
      if (child is RenderParagraph) {
        paragraphs.add(child);
      } else {
        child.visitChildren(collect);
      }
    }

    box.visitChildren(collect);
    final lengths = [
      for (final paragraph in paragraphs)
        paragraph.text.toPlainText(includeSemanticsLabels: false).length,
    ];
    var offset = (fraction * lengths.fold(0, (sum, length) => sum + length))
        .floor();
    for (var i = 0; i < paragraphs.length; i++) {
      if (offset < lengths[i]) {
        final caret = paragraphs[i].getOffsetForCaret(
          TextPosition(offset: offset),
          Rect.zero,
        );
        final top = MatrixUtils.transformPoint(
          paragraphs[i].getTransformTo(box),
          caret,
        ).dy;
        return Rect.fromLTWH(0, top, 0, 0);
      }
      offset -= lengths[i];
    }
    return Rect.fromLTWH(0, fraction * box.size.height, 0, 0);
  };
}

/// סוף ההתאמה ה-[matchIndex]: הקידומת הקצרה ביותר שבה [utils.countMatches]
/// מוצא matchIndex+1 התאמות — כך המיקום תמיד באותה ספירה של המונה.
int? _matchEnd(String text, String query, int matchIndex) {
  int countIn(int length) => utils.countMatches(
    text.substring(0, length),
    query,
    partialWordMatch: true,
  );
  if (matchIndex < 0 || countIn(text.length) <= matchIndex) return null;
  var low = 1;
  var high = text.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (countIn(middle) > matchIndex) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

String _searchableText(String content, TextDisplayProfile displayProfile) {
  final text = utils.removeVolwels(content);
  return displayProfile.removePunctuation
      ? utils.removePunctuation(text)
      : text;
}

/// קטע תצוגה סביב ההתאמה בתוכן מפרש, משמר את פרופיל התצוגה של המפרשים.
String buildCommentarySearchSnippet({
  required String content,
  required String query,
  required TextDisplayProfile displayProfile,
}) {
  var text = utils.removeMarks(
    content,
    nikud: displayProfile.removeNikud,
    teamim: displayProfile.removeTeamim,
  );
  if (displayProfile.removePunctuation) {
    text = utils.removePunctuation(text);
  }
  return SnippetBuilder.buildExcerptText(
    fullText: utils.stripHtmlIfNeeded(text),
    query: query,
    maxChars: 220,
  );
}

/// מייצג תוצאת חיפוש בודדת עם קטע טקסט וכתובת גלובלית לניווט.
///
/// חי כאן ולא בווידג'ט כדי ששני משטחי המפרשים (טקסט ו-PDF) יוכלו לדווח
/// ולצרוך את אותו טיפוס בלי לייבא זה את הווידג'ט של זה.
class CommentarySearchSnippet {
  final String path;
  final String snippet;
  final int globalIndex;

  const CommentarySearchSnippet({
    required this.path,
    required this.snippet,
    required this.globalIndex,
  });
}
