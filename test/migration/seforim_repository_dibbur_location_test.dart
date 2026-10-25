import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dibbur-location-');
    database = MyDatabase.withPath(path.join(temp.path, 'test.db'));
    repository = SeforimRepository(database);
    final db = await database.database;
    db.execute(
      'CREATE TABLE line_dh (bookId INTEGER NOT NULL, dhText TEXT NOT NULL, '
      'lineIndex INTEGER NOT NULL, dhDisplay TEXT NOT NULL, '
      'PRIMARY KEY (bookId, dhText, lineIndex)) WITHOUT ROWID',
    );
    for (final bookId in [1, 2]) {
      for (var i = 0; i < 8; i++) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            bookId * 100 + i,
            bookId,
            i,
            '',
            'ספר $bookId, ${i < 4 ? 'עט.' : 'עט:'}, א',
          ],
        );
        if (i.isOdd) {
          db.execute('INSERT INTO line_dh VALUES (?, ?, ?, ?)', [
            bookId,
            'אמר',
            i,
            'אמר',
          ]);
        }
      }
    }
  });

  tearDown(() async {
    database.close();
    await temp.delete(recursive: true);
  });

  Future<void> headings(
    List<(int, String)> headings, {
    bool alternate = false,
    int structureId = 1,
    int bookId = 1,
  }) async {
    final db = await database.database;
    if (alternate) {
      db.execute(
        "INSERT INTO alt_toc_structure (id, bookId, key, title, heTitle) "
        "VALUES (?, ?, ?, 'Chapters', 'פרקים')",
        [structureId, bookId, 'structure-$structureId'],
      );
    }
    for (final (index, text) in headings) {
      db.execute('INSERT OR IGNORE INTO tocText (text) VALUES (?)', [text]);
      final textId =
          db.select('SELECT id FROM tocText WHERE text = ?', [
                text,
              ]).single['id']
              as int;
      db.execute(
        alternate
            ? 'INSERT INTO alt_toc_entry (structureId, textId, level, lineId) VALUES (?, ?, 0, ?)'
            : 'INSERT INTO tocEntry (bookId, textId, level, lineId) VALUES (?, ?, 1, ?)',
        [alternate ? structureId : bookId, textId, bookId * 100 + index],
      );
    }
  }

  Future<List<(int, int)>> find(
    List<String> tokens, {
    List<int> books = const [1],
    int limit = 40,
  }) async => [
    for (final d in await repository.resolveDibburimInBooks(
      books,
      'אמר',
      locations: {1: (bookTitle: 'ספר 1', keyTokens: tokens)},
      limit: limit,
    ))
      (d.bookId, d.lineIndex),
  ];

  test('מפתח של סימן נפתר לפי כותרת TOC, אף שה-heRef מציין דף', () async {
    await headings([(0, 'סימן מח'), (4, 'סימן מט')]);
    expect(await find(['מח']), [(1, 1), (1, 3)]);
  });

  test('TOC מלא של סימן אינו מתרחב לסעיף בעל אותו מספר ב-AltToc', () async {
    await headings([(0, 'סימן א'), (4, 'סימן ב')]);
    await headings([(4, 'סימן ב')], alternate: true);
    final db = await database.database;
    final parentId =
        db.select('SELECT id FROM alt_toc_entry').single['id'] as int;
    db.execute("INSERT INTO tocText (text) VALUES ('סעיף א')");
    db.execute(
      'INSERT INTO alt_toc_entry (structureId, parentId, textId, level, lineId) '
      'VALUES (1, ?, ?, 1, 105)',
      [parentId, db.lastInsertRowId],
    );
    expect(await find(['א']), [(1, 1), (1, 3)]);
  });

  test('פרק חלופי ברמה 0 מסתיים בפרק הבא, בלי לבלוע אותו', () async {
    await headings([(0, 'דף עט.'), (4, 'דף עט:')]);
    await headings([(2, 'הנשרפין'), (6, 'אלו הן הנחנקין')], alternate: true);
    expect(await find(['הנשרפין']), [(1, 3), (1, 5)]);
  });

  test('כותרות זהות בכמה מקומות מאחדות את טווחיהן', () async {
    await headings([
      (0, 'פרק ראשון'),
      (2, 'פרק שני'),
      (4, 'פרק ראשון'),
      (6, 'פרק שלישי'),
    ]);
    expect(await find(['ראשון']), [(1, 1), (1, 5)]);
  });

  test('כותרת במבנה חלופי אחר אינה קוטעת פרק באמצע', () async {
    await headings([(0, 'דף עט.'), (4, 'דף עט:')]);
    await headings([(2, 'הנשרפין'), (6, 'אלו הן הנחנקין')], alternate: true);
    await headings(
      [(0, 'סדר ראשון'), (4, 'סדר שני')],
      alternate: true,
      structureId: 2,
    );
    expect(await find(['הנשרפין']), [(1, 3), (1, 5)]);
  });

  test('שם לא מוכר או התאמת TOC חלקית אינם מוחקים דיבורים', () async {
    await headings([(0, 'פרק ראשון'), (4, 'פרק שני')]);
    expect(await find(['לאקיים']), [(1, 1), (1, 3), (1, 5), (1, 7)]);
    expect(await find(['ראשון', 'לאקיים']), [(1, 1), (1, 3), (1, 5), (1, 7)]);
  });

  test('דף ועמוד עדיין מוגבלים גם בלי TOC', () async {
    expect(await find(['עט', 'א']), [(1, 1), (1, 3)]);
    expect(await find(['עט', 'ב']), [(1, 5), (1, 7)]);
    expect(await find(['עט']), [(1, 1), (1, 3), (1, 5), (1, 7)]);
  });

  test('טווח בספר אחד אינו מסנן ספר משני ללא ציון, והתקרה חלה אחריו', () async {
    await headings([(0, 'סימן מח'), (4, 'סימן מט')]);
    expect(await find(['מט'], books: [1, 2], limit: 3), [
      (1, 5),
      (1, 7),
      (2, 1),
    ]);
  });

  test('מסלול מכיל משתמש באותו טווח לפני התקרה', () async {
    await headings([(0, 'סימן מח'), (4, 'סימן מט')]);
    final found = await repository.resolveDibburimInBooks(
      [1],
      'מר',
      containsBookIds: [1],
      locations: {
        1: (bookTitle: 'ספר 1', keyTokens: ['מט']),
      },
      limit: 1,
    );
    expect(found.single.lineIndex, 5);
  });

  test('ציון מוכר בספר הראשי מסנן שמות לא פתורים בספר משני', () async {
    await headings([(0, 'דף עט.'), (4, 'דף עט:')]);
    final found = await repository.resolveDibburimInBooks(
      [2, 1],
      'אמר',
      locations: {
        1: (bookTitle: 'ספר 1', keyTokens: ['עט', 'א']),
        2: (bookTitle: 'ספר 2', keyTokens: ['סנהדרין', 'עט', 'א']),
      },
      limit: 2,
    );
    expect(found.map((d) => (d.bookId, d.lineIndex)), [(1, 1), (1, 3)]);
  });

  test('ספר שזוהה במלואו אינו מאבד את הבחירה שלו מול ספרים משניים', () async {
    final found = await repository.resolveDibburimInBooks(
      [2, 1],
      'אמר',
      locations: {
        1: (bookTitle: 'ספר 1', keyTokens: []),
        2: (bookTitle: 'ספר 2', keyTokens: ['סנהדרין']),
      },
      limit: 2,
    );
    expect(found.map((d) => (d.bookId, d.lineIndex)), [(1, 1), (1, 3)]);
  });

  test('מיקום ראשי מוכר שומר כינוי שנפתר ב-AltToc של הספר המשני', () async {
    await headings([(0, 'דף עט.'), (4, 'דף עט:')]);
    await headings(
      [(2, 'הנשרפין'), (6, 'אלו הן הנחנקין')],
      alternate: true,
      bookId: 2,
    );
    final found = await repository.resolveDibburimInBooks(
      [1, 2],
      'אמר',
      locations: {
        1: (bookTitle: 'ספר 1', keyTokens: ['עט', 'א']),
        2: (bookTitle: 'ספר 2', keyTokens: ['הנשרפין']),
      },
    );
    expect(found.map((d) => (d.bookId, d.lineIndex)), [
      (1, 1),
      (1, 3),
      (2, 3),
      (2, 5),
    ]);
  });

  test('מיקום ב-heRef של ספר משני נשמר גם בלי TOC מקומי', () async {
    await headings([(0, 'דף עט.'), (4, 'דף עט:')]);
    (await database.database).execute(
      "UPDATE line SET heRef = 'ספר 2, אורח חיים, עט., א' WHERE bookId = 2",
    );
    final found = await repository.resolveDibburimInBooks(
      [1, 2],
      'אמר',
      locations: {
        1: (bookTitle: 'ספר 1', keyTokens: ['עט', 'א']),
        2: (bookTitle: 'ספר 2', keyTokens: ['אורח', 'חיים', 'עט', 'א']),
      },
    );
    expect(found.map((d) => (d.bookId, d.lineIndex)), [
      (1, 1),
      (1, 3),
      (2, 1),
      (2, 3),
      (2, 5),
      (2, 7),
    ]);
  });
}
