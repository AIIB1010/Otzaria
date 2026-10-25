import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

class _NoFiles extends Fake implements FileSystemData {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('חיבור שמעולם לא נפתח אינו נפתח על ידי טעינת מפרשים', () async {
    final temp = await Directory.systemTemp.createTemp(
      'commentators-unopened-',
    );
    AppPaths.debugOverrideDataRootPath(temp.path);
    addTearDown(() async {
      await SqliteDataProvider.instance.dispose();
      DbReadWorker.disposeForTesting();
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      await temp.delete(recursive: true);
    });
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final dbPath = SeforimFixtureDb.create(temp, SeforimFixtureVariant.full);
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    final provider = SqliteDataProvider.instance;
    final book = TextBook(
      title: SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    final repository = TextBookRepository(fileSystem: _NoFiles());
    expect(provider.canReopenAfterClose, isFalse);
    expect((await repository.getCommentatorsWithRarity(book)).all, isEmpty);
    expect(
      (await DefaultCommentators.fetchDefaults(book)).commentators,
      isEmpty,
    );
    expect(provider.isInitialized, isFalse);
    expect(provider.dbPath, isEmpty);
  });
}
