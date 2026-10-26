// קובץ פגום בודד אינו מפיל ייבוא ספרייה שלם (§76).
//
// הרגרסיה שהבדיקה מונעת: מרגע שהממירים זורקים חריגה מוקלדת על קובץ שאינו
// ניתן לקריאה, `processDirectory` היה מפסיק באמצע והשאר לא היה נסרק כלל.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/generator/generator.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory library;

  /// הספרים יושבים בתת-תיקייה: `processDirectory` יוצר ממנה קטגוריה, וקבצים
  /// ברמת השורש (בלי קטגוריית-אב) מדולגים בכל מקרה.
  late Directory category;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('generator-corrupted-');
    library = Directory(p.join(tempDir.path, 'ספרייה'))..createSync();
    category = Directory(p.join(library.path, 'קטגוריה'))..createSync();
    database = MyDatabase.withPath(p.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
    }
  });

  Future<void> writeText(String name, String content) =>
      File(p.join(category.path, name)).writeAsString(content, flush: true);

  test('קובץ DOCX פגום מדולג ושאר הספרים נסרקים', () async {
    // סדר אלפביתי: הפגום נסרק *באמצע*, כך שכשל היה קוטע את מה שאחריו.
    await writeText('אלף.txt', '<h1>ספר ראשון</h1>\nתוכן');
    await writeText('בית.docx', 'זה בכלל לא ZIP — קובץ פגום');
    await writeText('גימל.txt', '<h1>ספר שלישי</h1>\nתוכן');

    final generator = DatabaseGenerator(repository);
    await generator.processDirectory(library.path, null, 0);

    final titles = (await repository.getAllBooksLean())
        .map((b) => b.title)
        .toSet();

    expect(titles, contains('אלף'));
    expect(
      titles,
      contains('גימל'),
      reason: 'הספר שאחרי הפגום חייב להיסרק — אחרת הכשל קטע את הייבוא',
    );
    expect(titles, isNot(contains('בית')));
  });

  test('כמה קבצים פגומים ברצף אינם עוצרים את הסריקה', () async {
    await writeText('אלף.docx', 'לא ZIP');
    await writeText('בית.odt', 'לא ZIP');
    await writeText('גימל.doc', 'לא CFB');
    await writeText('דלת.txt', '<h1>שורד</h1>\nתוכן');

    final generator = DatabaseGenerator(repository);
    await generator.processDirectory(library.path, null, 0);

    final titles = (await repository.getAllBooksLean())
        .map((b) => b.title)
        .toSet();

    expect(titles, contains('דלת'));
  });
}
