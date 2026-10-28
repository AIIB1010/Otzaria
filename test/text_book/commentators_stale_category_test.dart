import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

class _NoFiles extends Fake implements FileSystemData {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  // כרטיסייה ששוחזרה אחרי החלפת ספרייה: הקטגוריה השמורה כבר לא קיימת במסד.
  final staleBereshit = TextBook(
    title: SeforimFixtureIds.bereshitTitle,
    source: BookSource.official,
    categoryId: 999,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-i2462-');
    final fixture = SeforimFixtureDb.create(
      tempDir,
      SeforimFixtureVariant.full,
    );
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      fixture,
    );
    await SqliteDataProvider.instance.initialize();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows שחרור ה-handle אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test('categoryId ישן: רשימת המפרשים נמצאת לפי שם הספר (#2462)', () async {
    final repository = TextBookRepository(fileSystem: _NoFiles());

    final result = await repository.getCommentatorsWithRarity(staleBereshit);

    expect(result.all, contains(SeforimFixtureIds.rashiTitle));
  });

  test('categoryId ישן: מפרשי טווח השורות נמצאים (#2462)', () async {
    final repository = TextBookRepository(fileSystem: _NoFiles());

    final result = await repository.getCommentatorsInLineRange(
      staleBereshit,
      startLine: 0,
      endLine: 5,
    );

    expect(
      result.map((c) => c.title),
      contains(SeforimFixtureIds.rashiTitle),
    );
  });

  test('categoryId ישן: מפרשי ברירת המחדל נמצאים (#2462)', () async {
    final defaults = await DefaultCommentators.fetchDefaults(staleBereshit);

    expect(
      defaults.commentators.map((c) => c.title),
      contains(SeforimFixtureIds.rashiTitle),
    );
  });
}
