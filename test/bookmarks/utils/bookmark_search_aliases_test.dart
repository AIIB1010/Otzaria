import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_search_aliases.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

void main() {
  tearDown(AcronymsCache.instance.clear);

  Bookmark bookmark(BookSource source, {bool isSearch = false}) => Bookmark(
    ref: 'משנה תורה הלכות שבת',
    book: TextBook(id: 7, title: 'משנה תורה', source: source),
    index: 0,
    isSearch: isSearch,
  );

  test('מזהה זהה ממקור אחר אינו מקבל כינויים רשמיים', () {
    AcronymsCache.instance.setAcronymsForTesting({
      7: ['רמבם'],
    });
    expect(bookmarkSearchAliases(bookmark(BookSource.official)), ['רמבם']);
    expect(bookmarkSearchAliases(bookmark(BookSource.user)), isEmpty);
    expect(bookmarkSearchAliases(bookmark(BookSource.attached('one'))), isNull);
    expect(bookmarkSearchAliases(bookmark(BookSource.attached('two'))), isNull);
  });

  test('חיפוש שמור אינו מקבל כינויים או כותרת לשינוי כתיב', () {
    AcronymsCache.instance.setAcronymsForTesting({
      7: ['רמבם'],
    });
    final search = bookmark(BookSource.official, isSearch: true);
    expect(bookmarkSearchAliases(search), isEmpty);
    expect(bookmarkSearchTitle(search), isNull);
    expect(bookmarkSearchTitle(bookmark(BookSource.official)), 'משנה תורה');
  });
}
