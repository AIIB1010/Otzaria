import 'package:flutter/painting.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

final _tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*>');

/// ממיר HTML פשוט של שורת ספר לטקסט עשיר: הדגשה (`b`, `strong`), גדול/קטן
/// (`big`, `small`), ושבירת שורה. שאר התגיות מוסרות. [showNikud] = false מסיר
/// ניקוד וטעמים.
List<InlineSpan> lvHtmlSpans(
  String html,
  TextStyle base, {
  bool showNikud = true,
}) {
  final text = html.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  final spans = <InlineSpan>[];
  var bold = 0;
  var big = 0;
  var small = 0;
  var last = 0;

  TextStyle current() {
    var style = base;
    if (bold > 0) style = style.copyWith(fontWeight: FontWeight.w900);
    final size = base.fontSize;
    if (size != null) {
      if (big > 0) style = style.copyWith(fontSize: size * 1.2);
      if (small > 0) style = style.copyWith(fontSize: size * 0.8);
    }
    return style;
  }

  void emit(String chunk) {
    if (chunk.isEmpty) return;
    var value = decodeHtmlEntities(chunk);
    if (!showNikud) value = removeVolwels(value);
    spans.add(TextSpan(text: value, style: current()));
  }

  for (final match in _tag.allMatches(text)) {
    emit(text.substring(last, match.start));
    last = match.end;
    final closing = match.group(1) == '/';
    final name = match.group(2)!.toLowerCase();
    final delta = closing ? -1 : 1;
    switch (name) {
      case 'b' || 'strong':
        bold = (bold + delta).clamp(0, 99);
      case 'big':
        big = (big + delta).clamp(0, 99);
      case 'small':
        small = (small + delta).clamp(0, 99);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        bold = (bold + delta).clamp(0, 99);
        big = (big + delta).clamp(0, 99);
    }
  }
  emit(text.substring(last));
  return spans;
}
