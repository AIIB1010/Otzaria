/// רכיבי רינדור שמזהים שורת מקור בתוך פריט קריאה: פסקה ממוזגת, שורה
/// שמוצגת כבלוק בתוך פריט, וסמן הבחירה שבשוליים.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';

/// שורת המקור שתחת נקודה בפריט קריאה.
@immutable
class ReaderLineHit {
  const ReaderLineHit({
    required this.lineIndex,
    required this.root,
    this.column,
    this.lineRange,
  });

  final int lineIndex;

  /// מיקום הנקודה בטקסט המוצג של השורה.
  final int? column;

  /// טווח השורה בטקסט ה-RenderParagraph שתחת [root]; null — השורה היא הפסקה כולה.
  final TextRange? lineRange;

  /// תת-העץ שבו נמצאת השורה, לעוזרי ה-hit-test של הבחירה.
  final RenderObject root;
}

/// שורת מקור אחת בתוך פסקה ממוזגת.
@immutable
class ReaderParagraphLineData {
  const ReaderParagraphLineData({
    required this.lineIndex,
    required this.range,
    this.background,
    this.selected = false,
  });

  final int lineIndex;

  /// טווח הטקסט של השורה (UTF-16) בטקסט הפסקה, בלי כותרת ובלי הרווח המחבר.
  final TextRange range;
  final Color? background;
  final bool selected;

  @override
  bool operator ==(Object other) =>
      other is ReaderParagraphLineData &&
      other.lineIndex == lineIndex &&
      other.range == range &&
      other.background == background &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(lineIndex, range, background, selected);
}

/// נושא את מפת השורות של פסקה ממוזגת ומצייר את רקע השורות המודגשות.
class ReaderParagraphLines extends SingleChildRenderObjectWidget {
  const ReaderParagraphLines({
    super.key,
    required this.lines,
    required super.child,
  });

  final List<ReaderParagraphLineData> lines;

  @override
  RenderReaderParagraphLines createRenderObject(BuildContext context) =>
      RenderReaderParagraphLines(lines);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderParagraphLines renderObject,
  ) {
    renderObject.lines = lines;
  }
}

class RenderReaderParagraphLines extends RenderProxyBox {
  RenderReaderParagraphLines(this._lines);

  List<ReaderParagraphLineData> _lines;
  List<ReaderParagraphLineData> get lines => _lines;
  set lines(List<ReaderParagraphLineData> value) {
    if (listEquals(value, _lines)) return;
    _lines = value;
    _rects.clear();
    markNeedsPaint();
  }

  RenderParagraph? _paragraph;
  final Map<int, List<Rect>> _rects = {};

  @override
  void performLayout() {
    super.performLayout();
    _paragraph = null;
    _rects.clear();
  }

  RenderParagraph? get paragraph {
    final cached = _paragraph;
    if (cached != null && cached.attached) return cached;
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    final child = this.child;
    if (child != null) visit(child);
    return _paragraph = found;
  }

  TextRange? rangeForLine(int lineIndex) {
    for (final line in _lines) {
      if (line.lineIndex == lineIndex) return line.range;
    }
    return null;
  }

  /// מלבני הטקסט של השורה במרחב של הפסקה הזו — בגובה שורת התצוגה המלא.
  /// מקטעים סמוכים באותה שורת תצוגה מאוחדים; מקטעים מופרדים (טקסט דו-כיווני)
  /// נשארים נפרדים, כדי לא לכסות את טקסט השורה השכנה.
  List<Rect> lineRects(int lineIndex) {
    final cached = _rects[lineIndex];
    if (cached != null) return cached;
    final range = rangeForLine(lineIndex);
    final paragraph = this.paragraph;
    if (range == null ||
        paragraph == null ||
        !paragraph.hasSize ||
        range.isCollapsed) {
      return const [];
    }
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    final rows = <Rect>[];
    for (final box in boxes) {
      final rect = box.toRect();
      final row = rows.indexWhere(
        (r) =>
            (r.top - rect.top).abs() < 0.5 &&
            (r.bottom - rect.bottom).abs() < 0.5 &&
            rect.left <= r.right + 0.5 &&
            rect.right >= r.left - 0.5,
      );
      if (row < 0) {
        rows.add(rect);
      } else {
        rows[row] = rows[row].expandToInclude(rect);
      }
    }
    final transform = paragraph.getTransformTo(this);
    final result = [
      for (final rect in rows) MatrixUtils.transformRect(transform, rect),
    ];
    _rects[lineIndex] = result;
    return result;
  }

  /// הטווח האנכי של כל שורה נבחרת, במרחב של הפסקה הזו.
  List<({double top, double bottom})> selectedExtents() {
    final extents = <({double top, double bottom})>[];
    for (final line in _lines) {
      if (!line.selected) continue;
      final rects = lineRects(line.lineIndex);
      if (rects.isEmpty) continue;
      var top = rects.first.top;
      var bottom = rects.first.bottom;
      for (final rect in rects.skip(1)) {
        if (rect.top < top) top = rect.top;
        if (rect.bottom > bottom) bottom = rect.bottom;
      }
      extents.add((top: top, bottom: bottom));
    }
    return extents;
  }

  /// השורה שתחת [globalPosition]; נקודה בכותרת המוזרקת שייכת לשורה שאחריה.
  ReaderLineHit? locate(Offset globalPosition) {
    final paragraph = this.paragraph;
    if (paragraph == null || !paragraph.hasSize || _lines.isEmpty) return null;
    final offset = paragraph
        .getPositionForOffset(paragraph.globalToLocal(globalPosition))
        .offset;
    var line = _lines.last;
    for (final candidate in _lines) {
      if (offset <= candidate.range.end) {
        line = candidate;
        break;
      }
    }
    final column = (offset - line.range.start)
        .clamp(0, line.range.end - line.range.start)
        .toInt();
    return ReaderLineHit(
      lineIndex: line.lineIndex,
      column: column,
      lineRange: line.range,
      root: this,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    for (final line in _lines) {
      final color = line.background;
      if (color == null) continue;
      final paint = Paint()..color = color;
      // סמן הבחירה שמצויר מתחת לטקסט נשאר גלוי מעל רקע השורה.
      final bar = line.selected ? _gutterStrip() : null;
      if (bar != null) {
        canvas.save();
        canvas.clipRect(bar.shift(offset), clipOp: ui.ClipOp.difference);
      }
      for (final rect in lineRects(line.lineIndex)) {
        canvas.drawRect(rect.shift(offset), paint);
      }
      if (bar != null) canvas.restore();
    }
    super.paint(context, offset);
  }

  /// רצועת הסמן של [RenderReaderLineGutter] שמעל, במרחב של הפסקה הזו.
  Rect? _gutterStrip() {
    RenderObject? node = parent;
    while (node != null && node is! RenderReaderLineGutter) {
      node = node.parent;
    }
    if (node is! RenderReaderLineGutter || node._foreground || !node.hasSize) {
      return null;
    }
    final width = node.size.width;
    return MatrixUtils.transformRect(
      node.getTransformTo(this),
      Rect.fromLTRB(
        width - RenderReaderLineGutter.barWidth,
        0,
        width,
        node.size.height,
      ),
    );
  }
}

/// שורת מקור שמוצגת כבלוק נפרד בתוך פריט (שורה מיושרת, טבלה וכו').
class ReaderLineBlock extends SingleChildRenderObjectWidget {
  const ReaderLineBlock({
    super.key,
    required this.lineIndex,
    this.selected = false,
    required super.child,
  });

  final int lineIndex;
  final bool selected;

  @override
  RenderReaderLineBlock createRenderObject(BuildContext context) =>
      RenderReaderLineBlock(lineIndex: lineIndex, selected: selected);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderLineBlock renderObject,
  ) {
    renderObject
      ..lineIndex = lineIndex
      ..selected = selected;
  }
}

class RenderReaderLineBlock extends RenderProxyBox {
  RenderReaderLineBlock({required this.lineIndex, required this._selected});

  int lineIndex;

  bool _selected;
  bool get selected => _selected;
  set selected(bool value) {
    if (value == _selected) return;
    _selected = value;
    markNeedsPaint();
  }
}

/// סמן הבחירה שבשוליים לפריט של כמה שורות: נמתח רק לאורך השורות הנבחרות.
class ReaderLineGutter extends SingleChildRenderObjectWidget {
  const ReaderLineGutter({
    super.key,
    required this.color,
    required this.selectedLines,
    this.foreground = false,
    required super.child,
  });

  final Color color;

  /// משמש לזיהוי שינוי בבחירה; הציור עצמו נקרא מהשורות שבתת-העץ.
  final Set<int> selectedLines;

  /// בציור מתחת לטקסט אותיות בקצה השורה אינן מוסתרות.
  final bool foreground;

  @override
  RenderReaderLineGutter createRenderObject(BuildContext context) =>
      RenderReaderLineGutter(
        color: color,
        selectedLines: selectedLines,
        foreground: foreground,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderLineGutter renderObject,
  ) {
    renderObject
      ..color = color
      ..selectedLines = selectedLines
      ..foreground = foreground;
  }
}

class RenderReaderLineGutter extends RenderProxyBox {
  RenderReaderLineGutter({
    required this._color,
    required this._selectedLines,
    required this._foreground,
  });

  static const double barWidth = 3;

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  Set<int> _selectedLines;
  set selectedLines(Set<int> value) {
    if (setEquals(value, _selectedLines)) return;
    _selectedLines = value;
    markNeedsPaint();
  }

  bool _foreground;
  set foreground(bool value) {
    if (value == _foreground) return;
    _foreground = value;
    markNeedsPaint();
  }

  /// מלבני הסמן במרחב של הרכיב הזה.
  @visibleForTesting
  List<Rect> barRects() {
    final rects = <Rect>[];
    final child = this.child;
    if (_selectedLines.isEmpty || child == null || !hasSize) return rects;
    void add(double top, double bottom) {
      rects.add(
        Rect.fromLTRB(size.width - barWidth, top, size.width, bottom),
      );
    }

    void visit(RenderObject object) {
      if (object is RenderReaderParagraphLines) {
        if (!object.hasSize) return;
        final transform = object.getTransformTo(this);
        for (final extent in object.selectedExtents()) {
          final rect = MatrixUtils.transformRect(
            transform,
            Rect.fromLTRB(0, extent.top, 1, extent.bottom),
          );
          add(rect.top, rect.bottom);
        }
        return;
      }
      if (object is RenderReaderLineBlock) {
        if (object.selected && object.hasSize) {
          final rect = MatrixUtils.transformRect(
            object.getTransformTo(this),
            Offset.zero & object.size,
          );
          add(rect.top, rect.bottom);
        }
        return;
      }
      object.visitChildren(visit);
    }

    visit(child);
    return rects;
  }

  void _paintBars(PaintingContext context, Offset offset) {
    final paint = Paint()..color = _color;
    for (final rect in barRects()) {
      context.canvas.drawRect(rect.shift(offset), paint);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_foreground) _paintBars(context, offset);
    super.paint(context, offset);
    if (_foreground) _paintBars(context, offset);
  }
}

/// שורת המקור שתחת [globalPosition] בתת-העץ של [root], או null כשהנקודה
/// אינה בגובה של פסקה ממוזגת או של בלוק שורה (כרטיס מפרשים, כותרת, רווח).
ReaderLineHit? readerLineAt(RenderObject root, Offset globalPosition) {
  RenderBox? hit;
  void visit(RenderObject object) {
    if (hit != null) return;
    if (object is RenderReaderParagraphLines ||
        object is RenderReaderLineBlock) {
      final box = object as RenderBox;
      if (!box.attached || !box.hasSize) return;
      final dy = box.globalToLocal(globalPosition).dy;
      if (dy >= 0 && dy <= box.size.height) hit = box;
      return;
    }
    object.visitChildren(visit);
  }

  visit(root);
  final box = hit;
  if (box is RenderReaderParagraphLines) return box.locate(globalPosition);
  if (box is RenderReaderLineBlock) {
    return ReaderLineHit(
      lineIndex: box.lineIndex,
      column: renderedTextOffsetAtPosition(
        root: box,
        globalPosition: globalPosition,
      ),
      root: box,
    );
  }
  return null;
}
