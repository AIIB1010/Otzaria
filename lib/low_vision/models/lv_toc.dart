import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';

/// פריט בתוכן עניינים, בלי תלות בסוג הספר.
/// [target] הוא אינדקס שורה בספר טקסט או מספר עמוד ב-PDF.
class LvTocItem {
  const LvTocItem(this.title, this.target, [this.children = const []]);

  final String title;
  final int target;
  final List<LvTocItem> children;

  /// כל הפריטים לפי סדר הקריאה (כולל צאצאים).
  static List<LvTocItem> flatten(List<LvTocItem> items) => [
    for (final item in items) ...[item, ...flatten(item.children)],
  ];

  /// עץ הסעיפים של ספר טקסט. שורש יחיד בשם הספר נחשב כותרת ולא סעיף.
  static List<LvTocItem> fromTocEntries(List<TocEntry> roots) {
    var entries = roots;
    if (entries.length == 1 &&
        isBookTitleRoot(entries.first) &&
        entries.first.children.isNotEmpty) {
      entries = entries.first.children;
    }
    LvTocItem convert(TocEntry e) => LvTocItem(
      e.text.trim().isEmpty ? '—' : e.text.trim(),
      e.index,
      [for (final c in e.children) convert(c)],
    );
    return [for (final e in entries) convert(e)];
  }

  static List<LvTocItem> fromPdfOutline(List<PdfOutlineNode> nodes) => [
    for (final n in nodes)
      if (n.dest != null || n.children.isNotEmpty)
        LvTocItem(
          n.title.trim().isEmpty ? '—' : n.title.trim(),
          n.dest?.pageNumber ?? _firstPage(n.children) ?? 1,
          fromPdfOutline(n.children),
        ),
  ];

  static int? _firstPage(List<PdfOutlineNode> nodes) {
    for (final n in nodes) {
      final page = n.dest?.pageNumber ?? _firstPage(n.children);
      if (page != null) return page;
    }
    return null;
  }
}
