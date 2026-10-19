/// שורה ארוכה מאוד מוצגת כרצף פסקאות קצרות שנבנות בהדרגה, ונשארת פריט אחד
/// ברשימה. הטקסט המחובר של המקטעים זהה לטקסט השורה.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';

/// שורה שהטקסט הגלוי שלה ארוך מזה מוצגת במקטעים.
const int kLongLineMinChars = 2 * kLongLineChunkChars;

/// האורך המשוער של מקטע; החיתוך ברווח שאחריו. לכל פסקה יש עלות קבועה
/// בפריסה מחדש (שינוי רוחב), ולכן מקטעים קטנים יותר מאטים אותה.
const int kLongLineChunkChars = 16000;

/// כמה מקטעים נבנים בכל פריים, כולל הראשון.
const int kLongLineChunksPerFrame = 1;

/// מקטעי שורה ארוכה: הספאנים ותחילת כל אחד בטקסט השורה.
@immutable
class LongLineSplit {
  const LongLineSplit._(this.text, this.chunks, this.starts);

  /// הטקסט הגלוי של השורה כולה.
  final String text;
  final List<TextSpan> chunks;
  final List<int> starts;
}

final Expando<LongLineSplit> _splitCache = Expando<LongLineSplit>(
  'longLineSplit',
);

/// מפצל את [span] (התוצר השטוח של `SimpleInlineHtml.tryParse`) למקטעים.
/// null כשהשורה קצרה או כשאין בה מקום בטוח לחיתוך.
LongLineSplit? splitLongLine(TextSpan span) {
  final cached = _splitCache[span];
  if (cached != null) return cached;
  final split = _split(span);
  if (split != null) _splitCache[span] = split;
  return split;
}

LongLineSplit? _split(TextSpan span) {
  if (span.style != null || span.recognizer != null) return null;
  final List<TextSpan> leaves;
  if (span.children == null) {
    final text = span.text;
    if (text == null) return null;
    leaves = [TextSpan(text: text)];
  } else {
    if (span.text != null) return null;
    leaves = <TextSpan>[];
    for (final child in span.children!) {
      if (child is! TextSpan ||
          child.children != null ||
          child.text == null ||
          child.recognizer != null) {
        return null;
      }
      leaves.add(child);
    }
  }
  var total = 0;
  for (final leaf in leaves) {
    total += leaf.text!.length;
  }
  if (total <= kLongLineMinChars) return null;

  final chunks = <TextSpan>[];
  final starts = <int>[];
  var current = <TextSpan>[];
  var currentLength = 0;
  var offset = 0;
  void close() {
    if (current.isEmpty) return;
    starts.add(offset - currentLength);
    chunks.add(TextSpan(children: current));
    current = <TextSpan>[];
    currentLength = 0;
  }

  for (final leaf in leaves) {
    var text = leaf.text!;
    // רק ברווח של טקסט בלי עיצוב: לא באמצע מילה, הדגשה או סימון.
    while (text.isNotEmpty &&
        leaf.style == null &&
        currentLength + text.length > kLongLineChunkChars) {
      final cut = _cutAfter(
        text,
        math.max(0, kLongLineChunkChars - currentLength),
      );
      if (cut <= 0) break;
      current.add(TextSpan(text: text.substring(0, cut)));
      currentLength += cut;
      offset += cut;
      close();
      text = text.substring(cut);
    }
    if (text.isEmpty) continue;
    current.add(identical(text, leaf.text) ? leaf : TextSpan(text: text));
    currentLength += text.length;
    offset += text.length;
  }
  close();
  if (chunks.length < 2) return null;
  return LongLineSplit._(span.toPlainText(), chunks, starts);
}

/// אינדקס החיתוך (אחרי רווח) מ-[from] והלאה; עדיף סוף משפט קרוב.
int _cutAfter(String text, int from) {
  final sentence = _sentenceEnd.allMatches(text, from).firstOrNull;
  if (sentence != null && sentence.start - from <= kLongLineChunkChars ~/ 4) {
    return sentence.end;
  }
  final space = text.indexOf(' ', from);
  return space < 0 ? -1 : space + 1;
}

final RegExp _sentenceEnd = RegExp(r'[.:?!] ');

/// מקטע של שורה ארוכה ב-render tree: [start] הוא היסט המקטע בטקסט השורה.
class RenderLongLineChunk extends RenderProxyBox {
  RenderLongLineChunk({required this.lineText, required this.start});

  String lineText;
  int start;
}

/// טקסט השורה וההיסט של [paragraph] בתוכו, כשהפסקה היא מקטע של שורה ארוכה.
({String lineText, int start})? longLineChunkOf(RenderObject paragraph) {
  RenderObject? node = paragraph.parent;
  // בין הפסקה למקטע יש רק את ה-MouseRegion של SelectionFillText.
  for (var depth = 0; node != null && depth < 3; depth++) {
    if (node is RenderLongLineChunk) {
      return (lineText: node.lineText, start: node.start);
    }
    node = node.parent;
  }
  return null;
}

class _LongLineChunk extends SingleChildRenderObjectWidget {
  const _LongLineChunk({
    required this.lineText,
    required this.start,
    required super.child,
  });

  final String lineText;
  final int start;

  @override
  RenderLongLineChunk createRenderObject(BuildContext context) =>
      RenderLongLineChunk(lineText: lineText, start: start);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLongLineChunk renderObject,
  ) {
    renderObject
      ..lineText = lineText
      ..start = start;
  }
}

/// מציג את מקטעי [split] בזה אחר זה. בכל פריים נבנים
/// [kLongLineChunksPerFrame] מקטעים, כדי שהפריסה תתחלק בין כמה פריימים.
class LongLineChunks extends StatefulWidget {
  const LongLineChunks({
    super.key,
    required this.split,
    required this.style,
    this.strutStyle,
    required this.textAlign,
  });

  final LongLineSplit split;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;

  @override
  State<LongLineChunks> createState() => _LongLineChunksState();
}

class _LongLineChunksState extends State<LongLineChunks> {
  /// מקטעים שכבר נבנו נשמרים כאותו מופע, כדי שהוספת מקטע לא תעדכן את כולם.
  final List<Widget> _built = [];
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _addChunks();
  }

  @override
  void didUpdateWidget(LongLineChunks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.split, oldWidget.split) &&
        widget.style == oldWidget.style &&
        widget.strutStyle == oldWidget.strutStyle &&
        widget.textAlign == oldWidget.textAlign) {
      return;
    }
    // הדגשה חדשה באותו טקסט נבנית מחדש בבת אחת; טקסט או גופן אחר — בהדרגה.
    final keep =
        widget.split.text == oldWidget.split.text &&
            widget.style == oldWidget.style
        ? math.min(_built.length, widget.split.chunks.length)
        : 0;
    _built.clear();
    _addChunks(math.max(keep, kLongLineChunksPerFrame));
  }

  void _addChunks([int count = kLongLineChunksPerFrame]) {
    final split = widget.split;
    final end = math.min(_built.length + count, split.chunks.length);
    for (var i = _built.length; i < end; i++) {
      _built.add(
        _LongLineChunk(
          lineText: split.text,
          start: split.starts[i],
          child: SelectionFillText.rich(
            split.chunks[i],
            style: widget.style,
            strutStyle: widget.strutStyle,
            textAlign: widget.textAlign,
          ),
        ),
      );
    }
    _scheduleMore();
  }

  void _scheduleMore() {
    if (_scheduled || _built.length >= widget.split.chunks.length) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      setState(_addChunks);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: List.of(_built),
  );
}
