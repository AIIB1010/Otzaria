import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

/// שורות הקטלוג של seforim.db נקראות על חיבור משלהן מחוץ ל-UI isolate, וזהות
/// למה שהחיבור הראשי היה מחזיר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;
  late String libraryPath;

  Future<void> openLibrary(SeforimFixtureVariant variant) async {
    final created = SeforimFixtureDb.create(Directory(libraryPath), variant);
    File(
      created,
    ).renameSync(p.join(libraryPath, DatabaseConstants.databaseFileName));
    await provider.sqliteProvider.dispose();
    provider.clearCache();
    await provider.initialize();
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_catalog_off_ui');
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
  });

  tearDown(() async {
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  for (final variant in [
    SeforimFixtureVariant.full,
    SeforimFixtureVariant.minimal,
    SeforimFixtureVariant.missingAuthorTables,
  ]) {
    test(
      'שורות הקטלוג זהות לשאילתה על החיבור הראשי (${variant.name})',
      () async {
        await openLibrary(variant);
        final repository = provider.sqliteProvider.repository!;
        final db = await repository.database.database;

        final rows = readOfficialCatalogSync(provider.sqliteProvider.dbPath);

        expect(rows.books, repository.database.bookDao.getAllBooksMinimal(db));
        expect(
          rows.categories,
          repository.database.categoryDao.getAllCategoryRows(db),
        );
        expect(rows.authors, repository.database.bookDao.getBookAuthorsMap(db));
      },
    );
  }

  test('בניית הקטלוג אינה שואלת את החיבור של ה-UI isolate', () async {
    await openLibrary(SeforimFixtureVariant.full);
    final db = await provider.sqliteProvider.repository!.database.database;
    // טרנזקציה פתוחה על החיבור הראשי: BEGIN נוסף עליו נכשל.
    db.execute('BEGIN');
    try {
      final library = await provider.buildLibraryCatalog({}, libraryPath);
      expect(
        library.getAllBooks().map((book) => book.title),
        contains(SeforimFixtureIds.bereshitTitle),
      );
    } finally {
      db.execute('ROLLBACK');
    }
  });
}
