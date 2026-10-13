import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';

/// TOC עם רשומה לכל שורת כותרת — כמו בספר אמיתי, שבו שורות השבירה של
/// הקריאה הרציפה הן שורות ה-TOC.
List<TocEntry> headerToc(List<String> lines) => [
  for (var i = 0; i < lines.length; i++)
    if (isReadingHeaderLine(lines[i])) TocEntry(text: lines[i], index: i),
];
