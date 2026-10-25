import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;

import 'database.dart';

/// דיבור-מתחיל בודד, עם `line.id` שלו לשליפת מפרשים על אותה שורה.
typedef DibburCandidate = ({
  int bookId,
  int lineIndex,
  int lineId,
  String display,
  String? heRef,
});

/// ציון בתוך ספר; [refKeyTokens] ריקים מציינים התאמה לספר כולו.
typedef DibburLocation = ({String bookTitle, List<String> keyTokens});

/// גישה ל-`line_dh`; התחילית המנורמלת מוגשת מה-PRIMARY KEY.
class LineDhDao {
  final MyDatabase _db;
  bool? _available;

  LineDhDao(this._db);

  Future<sqlite3.Database> get database => _db.database;

  /// האם המסד הנוכחי מכיל את הטבלה **ואת** עמודת התצוגה. נבדק פעם אחת ונשמר.
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    final db = await database;
    final hasTable = db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'line_dh' LIMIT 1",
        )
        .isNotEmpty;
    if (!hasTable) return _available = false;
    final hasDisplay = db
        .select("PRAGMA table_info('line_dh')")
        .any((row) => row['name'] == 'dhDisplay');
    return _available = hasDisplay;
  }

  /// הדיבורים שתחילתם [prefix], בסדר הספרים שנמסר ואז לפי שורה.
  /// [contains] סורק גם את פנים הדיבור, ולכן מיועד לקבוצת ספרים מצומצמת.
  /// [where] מסנן לפני התקרה, כך שדיבורים שנדחו אינם תופסים את מקומה.
  Future<List<DibburCandidate>> dibburimForBooks(
    List<int> bookIds,
    String prefix, {
    bool contains = false,
    int limit = 40,
    bool Function(DibburCandidate dibbur)? where,
  }) async {
    if (bookIds.isEmpty || prefix.isEmpty || !await isAvailable()) {
      return const [];
    }
    final db = await database;
    final match = contains
        ? "d.dhText LIKE '%' || ? || '%'"
        // התו הגבוה ביותר ב-Unicode סוגר את טווח התחילית מלמעלה.
        : 'd.dhText >= ? AND d.dhText < ? || char(1114111)';
    final statement = db.prepare(
      'SELECT d.bookId, d.lineIndex, d.dhDisplay AS display, '
      'l.id AS lineId, l.heRef '
      'FROM line_dh d '
      'JOIN line l ON l.bookId = d.bookId AND l.lineIndex = d.lineIndex '
      'WHERE d.bookId = ? AND $match '
      'ORDER BY d.lineIndex LIMIT ?',
    );
    final found = <DibburCandidate>[];
    try {
      // לא ממיינים את כל הספרים כשכבר הספר הראשון ממלא את התקרה.
      for (final bookId in bookIds.toSet()) {
        if (found.length >= limit) break;
        final cursor = statement.selectCursor(
          [
            bookId,
            prefix,
            if (!contains) prefix,
            where == null ? limit - found.length : -1,
          ],
        );
        while (found.length < limit && cursor.moveNext()) {
          final row = cursor.current;
          final dibbur = (
            bookId: row['bookId'] as int,
            lineIndex: row['lineIndex'] as int,
            lineId: row['lineId'] as int,
            display: (row['display'] as String?) ?? '',
            heRef: row['heRef'] as String?,
          );
          if (where == null || where(dibbur)) found.add(dibbur);
        }
      }
    } finally {
      statement.close();
    }
    return found;
  }
}
