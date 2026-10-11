import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

const _bookId = 'ספר בדיקה';

class _CountingFiles extends Fake implements FileSystemData {
  _CountingFiles(this.text);

  String text;
  int textReads = 0;

  @override
  Future<String> getBookText(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    textReads++;
    return text;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late _CountingFiles files;
  late PersonalNotesRepository repository;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_repository_cache_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
    files = _CountingFiles('שורה ראשונה\nשורה שנייה');
    repository = PersonalNotesRepository(fileSystemData: files);
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  Future<List<PersonalNote>> add(int lineNumber) => repository.addNote(
    bookId: _bookId,
    lineNumber: lineNumber,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
  );

  test(
    'הוספה, עריכה ושינוי מיקום אחרי טעינה אינם קוראים שוב את הספר',
    () async {
      await repository.loadNotes(_bookId);
      final added = await add(1);
      await repository.updateNote(
        bookId: _bookId,
        noteId: added.single.id,
        content: 'חדש',
        contentPlain: 'חדש',
        contentFormat: PersonalNoteContentFormat.plain,
      );
      await repository.repositionNote(
        bookId: _bookId,
        noteId: added.single.id,
        lineNumber: 2,
      );

      expect(files.textReads, 1);
    },
  );

  test('הערה חדשה מקבלת את שורת הספר ומיקום מכווץ לגבולותיו', () async {
    await repository.loadNotes(_bookId);
    final notes = await add(9);

    expect(notes.single.lineNumber, 2);
    expect(notes.single.displayTitle, 'שורה שנייה');
  });

  test('טעינה חוזרת קוראת את הספר מחדש ועריכה משתמשת בגרסה החדשה', () async {
    await repository.loadNotes(_bookId);
    files.text = 'שורה מעודכנת\nשורה שנייה';
    await repository.loadNotes(_bookId);
    final notes = await add(1);

    expect(files.textReads, 2);
    expect(notes.single.displayTitle, 'שורה מעודכנת');
  });

  test('עריכה בספר אחר מזה שנטען קוראת את הספר שלה', () async {
    await repository.loadNotes('ספר אחר');
    await add(1);

    expect(files.textReads, 2);
  });

  test('תוכן ריק אינו נשמר, ועריכה קוראת את הספר שוב', () async {
    files.text = '';
    await repository.loadNotes(_bookId);
    files.text = 'שורה ראשונה';
    final notes = await add(1);

    expect(files.textReads, 2);
    expect(notes.single.displayTitle, 'שורה ראשונה');
  });
}
