import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:sqlite3/sqlite3.dart';

/// DB שמתעד כל `execute` ונכשל בשגיאת IO על המשפטים ש-[failOn] מזהה.
class _FakeDatabase implements Database {
  _FakeDatabase({required this.failOn, required this.extendedResultCode});

  final bool Function(String sql) failOn;
  final int extendedResultCode;
  final List<String> statements = [];

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    statements.add(sql);
    if (failOn(sql)) {
      throw SqliteException(
        extendedResultCode: extendedResultCode,
        message: 'disk I/O error',
        causingStatement: sql,
      );
    }
  }

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) =>
      ResultSet(
        ['timeout'],
        null,
        [
          [1400],
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// חיבור אמיתי שנכשל בבדיקת ה-WAL כמו WAL שאינו שמיש (IOERR_SHMOPEN).
class _ShmFailingDatabase implements Database {
  _ShmFailingDatabase(this.inner);

  final Database inner;

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    if (sql == 'BEGIN IMMEDIATE') {
      throw SqliteException(
        extendedResultCode: 4618,
        message: 'disk I/O error',
        causingStatement: sql,
      );
    }
    inner.execute(sql, parameters);
  }

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) =>
      inner.select(sql, parameters);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

int _synchronous(Database db) =>
    db.select('PRAGMA synchronous').first.values.first as int;

void main() {
  test('WAL מופעל על קובץ תקין', () {
    final dir = Directory.systemTemp.createTempSync('plugins_host_wal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = sqlite3.open(p.join(dir.path, 'plugins_host.db'));
    addTearDown(db.close);

    enableWalBestEffort(db, 'test');

    expect(db.select('PRAGMA journal_mode').first.values.first, 'wal');
    expect(_synchronous(db), 1, reason: 'NORMAL');
  });

  test('openWritableDatabase: WAL עם synchronous=NORMAL ו-busy_timeout', () {
    final dir = Directory.systemTemp.createTempSync('writable_sync');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = openWritableDatabase(p.join(dir.path, 'notes.db'), 'test');
    addTearDown(db.close);

    expect(db.select('PRAGMA journal_mode').first.values.first, 'wal');
    expect(db.select('PRAGMA synchronous').first.values.first, 1);
    expect(db.select('PRAGMA busy_timeout').first.values.first, 5000);
  });

  test('פתיחה בזמן שחיבור אחר כותב אינה ממתינה לנעילה ונשארת ב-WAL', () {
    final dir = Directory.systemTemp.createTempSync('wal_writer_busy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'cache.db');
    final writer = openWritableDatabase(path, 'writer')
      ..execute('BEGIN IMMEDIATE');
    addTearDown(() {
      writer.execute('ROLLBACK');
      writer.close();
    });

    final stopwatch = Stopwatch()..start();
    final db = openWritableDatabase(path, 'test');
    addTearDown(db.close);

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(db.select('PRAGMA journal_mode').first.values.first, 'wal');
    expect(db.select('PRAGMA locking_mode').first.values.first, 'normal');
    expect(db.select('PRAGMA busy_timeout').first.values.first, 5000);
    writer.execute('ROLLBACK');
    db.execute('CREATE TABLE writable_after_busy(value INTEGER)');
    writer.execute('BEGIN IMMEDIATE');
  });

  for (final initialMode in ['new', 'delete', 'wal']) {
    test(
      'SHM חסום אינו מונע כתיבה אחרי פתיחה ($initialMode)',
      () {
        final dir = Directory.systemTemp.createTempSync('wal_blocked_shm');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = p.join(dir.path, 'cache.db');
        if (initialMode != 'new') {
          final seed = sqlite3.open(path);
          seed.execute('CREATE TABLE existing(value INTEGER)');
          seed.execute('INSERT INTO existing VALUES (7)');
          seed.execute('PRAGMA journal_mode=$initialMode');
          seed.close();
        }
        Directory('$path-shm').createSync();

        final db = openWritableDatabase(path, 'test');
        addTearDown(db.close);

        db.execute('CREATE TABLE writable(value INTEGER)');
        db.execute('INSERT INTO writable VALUES (1)');
        expect(db.select('SELECT value FROM writable').first['value'], 1);
        expect(db.select('PRAGMA busy_timeout').first.values.first, 5000);
        if (initialMode != 'new') {
          expect(db.select('SELECT value FROM existing').first['value'], 7);
        }
      },
      skip: Platform.isWindows
          ? 'כשל SHM ב-Windows דורש פתיחה מחדש (#2981)'
          : false,
    );
  }

  test('בלי WAL (מסד בזיכרון) synchronous נשאר FULL', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);

    enableWalBestEffort(db, 'test');

    expect(db.select('PRAGMA journal_mode').first.values.first, 'memory');
    expect(_synchronous(db), 2, reason: 'FULL');
  });

  test('החזרה ל-journal רגיל משאירה synchronous=FULL', () {
    final dir = Directory.systemTemp.createTempSync('wal_fallback_sync');
    addTearDown(() => dir.deleteSync(recursive: true));
    final inner = sqlite3.open(p.join(dir.path, 'cache.db'));
    addTearDown(inner.close);

    inner.execute('PRAGMA busy_timeout=1337');
    enableWalBestEffort(_ShmFailingDatabase(inner), 'test');

    expect(inner.select('PRAGMA journal_mode').first.values.first, 'delete');
    expect(_synchronous(inner), 2, reason: 'FULL');
    expect(inner.select('PRAGMA busy_timeout').first.values.first, 1337);
  });

  test('closeWithCheckpoint ממזג את ה-WAL גם כשחיבור אחר פתוח', () {
    final dir = Directory.systemTemp.createTempSync('close_checkpoint');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'personal_notes.db');
    final db = sqlite3.open(path);
    enableWalBestEffort(db, 'test');
    db.execute('CREATE TABLE t(x INTEGER)');
    db.execute('INSERT INTO t VALUES (1)');
    // חיבור של חלון מוסתר: בזכותו הסגירה אינה האחרונה.
    final other = sqlite3.open(path)..select('SELECT 1');
    addTearDown(other.close);

    closeWithCheckpoint(db);

    final wal = File('$path-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
  });

  test('כשל בקטימת ה-journal אינו מפיל את פתיחת ה-DB', () {
    // SQLITE_IOERR_TRUNCATE (1546) — נעילה שנשארה על קובץ ה-journal.
    final db = _FakeDatabase(
      failOn: (sql) => sql.contains('journal_mode=WAL'),
      extendedResultCode: 1546,
    );

    expect(() => enableWalBestEffort(db, 'test'), returnsNormally);
  });

  test('BUSY בבדיקת ה-WAL אינו מחזיר ל-journal רגיל ואינו נועל בלעדית', () {
    // SQLITE_BUSY_RECOVERY (261) — חיבור אחר משחזר את ה-WAL; ה-WAL עצמו תקין.
    final db = _FakeDatabase(
      failOn: (sql) => sql == 'BEGIN IMMEDIATE',
      extendedResultCode: 261,
    );

    expect(() => enableWalBestEffort(db, 'test'), returnsNormally);
    expect(db.statements, isNot(contains('PRAGMA locking_mode=EXCLUSIVE')));
    expect(db.statements, isNot(contains('PRAGMA journal_mode=DELETE')));
    expect(db.statements.last, 'PRAGMA busy_timeout=1400');
  });

  test('WAL שאינו שמיש במערכת הקבצים מוחזר ל-journal רגיל', () {
    // SQLITE_IOERR_SHMOPEN (4618) — כרטיס SD ב-Android: ה-PRAGMA עובר,
    // ופתיחת ה-shared-memory נכשלת רק בטרנזקציה הראשונה.
    final db = _FakeDatabase(
      failOn: (sql) => sql == 'BEGIN IMMEDIATE',
      extendedResultCode: 4618,
    );

    expect(() => enableWalBestEffort(db, 'test'), returnsNormally);
    expect(db.statements, contains('PRAGMA journal_mode=DELETE'));
    expect(db.statements, contains('PRAGMA locking_mode=NORMAL'));
    expect(db.statements, isNot(contains('PRAGMA synchronous=NORMAL')));
  });
}
