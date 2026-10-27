import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';

/// מסד מצב המשתמש המשותף לכל החלונות: היסטוריה, סימניות, שולחנות, סשני
/// חלונות ותורי דיווח.
///
/// חיבור אחד ב-isolate לכל החלונות (WAL); הנעילה של SQLite חשובה רק מול
/// תהליך אחר (גיבוי, checkpoint) ומול [enqueueWrite], שכותב מחיבור משני.
class UserStateDatabase {
  UserStateDatabase._();

  static final UserStateDatabase instance = UserStateDatabase._();

  /// גרסת הסכמה — מקודמים ב-[_migrateSchema] בכל שינוי.
  static const int _schemaVersion = 1;

  /// כתיבה ב-isolate הנוכחי: FakeAsync של `testWidgets` אינו מקבל את התשובה
  /// מ-`Isolate.run`, ובדיקות שמריצות את האפליקציה כולה היו נתקעות.
  @visibleForTesting
  static bool debugWriteInline = false;

  Database? _database;
  String? _pathOverride;
  String? _path;
  List<(String, List<Object?>)>? _openWriteBatch;
  Future<void>? _writeTail;

  /// הפתיחה האחרונה יצרה את הקובץ — אין בו עדיין גרסת סכמה.
  bool get createdOnOpen => _createdOnOpen;
  bool _createdOnOpen = false;

  /// פותח את המסד בנתיב הזה במקום בתיקיית המסדים; לבדיקות בלבד.
  @visibleForTesting
  static UserStateDatabase openAt(String path) =>
      UserStateDatabase._().._pathOverride = path;

  @visibleForTesting
  void overridePath(String path) {
    close();
    _pathOverride = path;
  }

  /// המסד הפתוח, אחרי הכתיבות שכבר בתור: כתיבה על החיבור הזה בזמן שאצווה
  /// נכתבת ב-isolate הייתה נחסמת על הנעילה שלה, על ה-UI.
  Future<Database> get database async {
    // בלי כתיבה ממתינה אין await: מתחת ל-FakeAsync הוא לא היה מתקדם.
    if (_writeTail case final tail?) await _settled(tail);
    return _connection();
  }

  /// הפתיחה עצלה וסינכרונית — כמו `PersonalNotesDatabase`.
  Future<Database> _connection() async {
    final open = _database;
    if (open != null) return open;
    final path =
        _pathOverride ?? await AppPaths.resolveNotesDbPath('user_state.db');
    return _database ??= _open(path);
  }

  /// המסד הפתוח, כשכבר נפתח; לקוראים סינכרוניים שרצים אחרי האתחול.
  Database? get openDatabase => _database;

  Database _open(String path) {
    _path = path;
    // ההמתנה חוסמת את ה-thread המשותף לכל החלונות, ולכן קצרה: היא עוזרת
    // רק מול תהליך אחר (גיבוי, checkpoint).
    final db = openWritableDatabase(
      path,
      'UserStateDatabase',
      busyTimeoutMs: 1000,
    );
    _createSchema(db);
    _migrateSchema(db);
    return db;
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS lists (
        box TEXT NOT NULL,
        key TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (box, key)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS window_sessions (
        slot INTEGER PRIMARY KEY,
        tabs_json TEXT NOT NULL,
        current_index INTEGER NOT NULL,
        active_workspace_id TEXT,
        bounds_json TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pending_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS pending_reports_kind ON pending_reports(kind)',
    );
  }

  void _migrateSchema(Database db) {
    final current = firstIntValue(db.select('PRAGMA user_version')) ?? 0;
    _createdOnOpen = current == 0;
    if (current >= _schemaVersion) return;
    db.execute('PRAGMA user_version = $_schemaVersion');
  }

  /// מריץ את [statements] בטרנזקציה ב-isolate, אחרי הכתיבות שקדמו; מה
  /// שמצטבר בינתיים — באצווה אחת.
  Future<void> enqueueWrite(List<(String, List<Object?>)> statements) {
    if (_openWriteBatch case final open?) {
      open.addAll(statements);
      return _writeTail!;
    }
    final batch = _openWriteBatch = [...statements];
    final tail = _writeTail = _runWriteBatch(_writeTail, batch);
    _settled(tail).then((_) {
      if (identical(_writeTail, tail)) _writeTail = null;
    });
    return tail;
  }

  /// מנקז את כל הכתיבות, גם אלה שנכנסו בזמן הניקוז.
  Future<void> flushWrites() async {
    for (var tail = _writeTail; tail != null; tail = _writeTail) {
      await _settled(tail);
    }
  }

  Future<void> _runWriteBatch(
    Future<void>? previous,
    List<(String, List<Object?>)> batch,
  ) async {
    if (previous != null) await _settled(previous);
    _openWriteBatch = null;
    await _connection();
    if (debugWriteInline) return _runWrites(_path!, batch);
    await _writeInIsolate(_path!, batch);
  }

  // static: closure בתוך מתודת מופע הייתה לוכדת את this ונכשלת בשליחה.
  static Future<void> _writeInIsolate(
    String path,
    List<(String, List<Object?>)> batch,
  ) => Isolate.run(() => _runWrites(path, batch), debugName: 'UserStateWrite');

  static void _runWrites(String path, List<(String, List<Object?>)> batch) {
    final db = openSecondaryWritableConnection(path, 'UserStateWrite');
    try {
      withTransaction(db, () {
        for (final (sql, args) in batch) {
          db.execute(sql, args);
        }
      });
    } finally {
      db.close();
    }
  }

  static Future<void> _settled(Future<void> future) =>
      future.then((_) {}, onError: (_) {});

  /// סוגר את החיבור; הפתיחה הבאה דרך [database] תפתח מחדש.
  void close() {
    final db = _database;
    if (db != null) closeWithCheckpoint(db);
    _database = null;
  }

  /// סוגר ופותח מחדש — אחרי שינוי נתיב הספרייה, שמזיז את תיקיית המסדים.
  ///
  /// ⚠️ פותח מיד ולא בעצלות: `TabsRepository.loadTabs` קורא סינכרונית
  /// מהמסד הפתוח, ואחרי `RestartWidget` הוא רץ לפני כל `await` אחר.
  Future<void> reopen() async {
    await flushWrites();
    close();
    await database;
  }
}
