import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/models/book_source.dart';

/// כינויי הספר של [item] לחיפוש ברשימות ההיסטוריה והסימניות.
/// null — מטמון הכינויים עוד לא נטען, והרשימה תנסה שוב.
List<String>? bookmarkSearchAliases(dynamic item) {
  final bookmark = item as Bookmark;
  final id = bookmark.book.id;
  if (bookmark.isSearch || id == null) return const [];
  final cache = AcronymsCache.instance;
  final source = bookmark.book.source;
  if (source is AttachedBookSource) {
    if (cache.attachedAcronymsOf(source.slug) == null) return null;
  } else if (!cache.isLoaded) {
    return null;
  }
  return cache.acronymsFor(source, id) ?? const [];
}

/// חיפושים שמורים מכילים שאילתה, ולא שם ספר שניתן לשנות את כתיבו.
String? bookmarkSearchTitle(dynamic item) {
  final bookmark = item as Bookmark;
  return bookmark.isSearch ? null : bookmark.book.title;
}
