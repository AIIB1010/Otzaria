import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// שינוי מתג תצוגה טוען מחדש כל טאב פתוח עם התוכן הקיים. תוכן העניינים
/// של אותו ספר אינו משתנה, ושליפתו מחדש (עשרות אלפי ערכים בספרים גדולים)
/// מעכבת את הטאב הפעיל מאחורי כל הטאבים שבתור.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingTocProvider provider;
  final bookA = TextBook(title: 'ספר א', categoryId: 1, fileType: 'txt');
  final bookB = TextBook(title: 'ספר ב', categoryId: 2, fileType: 'txt');
  final emptyBook = TextBook(title: 'ספר ריק', categoryId: 3, fileType: 'txt');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    provider = _CountingTocProvider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final book in [bookA, bookB, emptyBook])
          BookCompositeKey.fromBook(book)!: provider,
      },
      providers: [provider],
    );
    addTearDown(LibraryProviderManager.instance.resetForTesting);
  });

  TextBookRepository newRepository() =>
      TextBookRepository(fileSystem: FileSystemData.instance);

  test('טעינה חוזרת של אותו ספר אינה שולפת את תוכן העניינים שוב', () async {
    final repository = newRepository();

    final first = await repository.getTableOfContents(bookA);
    final second = await repository.getTableOfContents(bookA);

    expect(provider.calls, ['ספר א']);
    expect(identical(first, second), isTrue);
  });

  test('ספר אחר, מופע ספר אחר ותוכן עניינים ריק נשלפים כמו קודם', () async {
    final repository = newRepository();

    final a = await repository.getTableOfContents(bookA);
    final b = await repository.getTableOfContents(bookB);
    expect(a.single.text, 'פרק של ספר א');
    expect(b.single.text, 'פרק של ספר ב');

    // מופע חדש של אותו ספר (מהדורה, פתיחה מחדש) אינו נחשב אותו ספר.
    final sameTitle = TextBook(title: 'ספר ב', categoryId: 2, fileType: 'txt');
    final b2 = await repository.getTableOfContents(sameTitle);
    expect(b2.single.text, 'פרק של ספר ב');

    // ריק עשוי להיות כשל זמני בעלייה, ולכן נשלף שוב בטעינה הבאה.
    expect(await repository.getTableOfContents(emptyBook), isEmpty);
    expect(await repository.getTableOfContents(emptyBook), isEmpty);

    // מאגר נפרד (טאב אחר) שולף בעצמו.
    final other = await newRepository().getTableOfContents(bookA);
    expect(other.single.text, 'פרק של ספר א');

    expect(provider.calls, [
      'ספר א',
      'ספר ב',
      'ספר ב',
      'ספר ריק',
      'ספר ריק',
      'ספר א',
    ]);
  });
}

class _CountingTocProvider implements LibraryProvider {
  final calls = <String>[];

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    calls.add(title);
    if (title == 'ספר ריק') return const [];
    return [TocEntry(text: 'פרק של $title', index: 0, level: 1)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
