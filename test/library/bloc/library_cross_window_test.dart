import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../helpers/memory_settings_cache.dart';

class _Store extends HiddenLibraryStore {
  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

Library _library(String title) {
  final root = Library(categories: []);
  root.subCategories.add(
    Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [TextBook(title: '$title ספר')],
      parent: root,
    ),
  );
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DataRepository repo;
  late Library before;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    before = _library('לפני');
    repo = DataRepository()..library = Future.value(before);
  });

  tearDown(() => MultiViewMode.debugOverride = null);

  LibraryBloc loaded() {
    final bloc = LibraryBloc(repository: repo, hiddenStore: _Store());
    bloc.emit(LibraryState(library: before, currentCategory: before));
    return bloc;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('עץ שנבנה מחדש בחלון אחד נבנה מחדש גם בשני, בלי הד חוזר', () async {
    MultiViewMode.debugOverride = true;
    final a = loaded();
    final b = loaded();
    final aStates = <LibraryState>[];
    final sub = a.stream.listen(aStates.add);

    repo.library = Future.value(_library('אחרי'));
    a.add(const HiddenBooksChanged());
    await settle();

    expect(a.state.library!.subCategories.single.title, 'אחרי');
    expect(b.state.library!.subCategories.single.title, 'אחרי');
    // B אינו מודיע הלאה: A בנה את העץ פעם אחת בלבד.
    expect(aStates, hasLength(1));

    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('בלי הדגל ה-bloc של חלון אחר אינו נוגע בעץ', () async {
    final a = loaded();
    final b = loaded();

    repo.library = Future.value(_library('אחרי'));
    a.add(const HiddenBooksChanged());
    await settle();

    expect(a.state.library!.subCategories.single.title, 'אחרי');
    expect(b.state.library, same(before));

    await a.close();
    await b.close();
  });

  test('bloc שנסגר אינו מקבל עוד הודעות', () async {
    MultiViewMode.debugOverride = true;
    final a = loaded();
    final b = loaded();
    await b.close();

    repo.library = Future.value(_library('אחרי'));
    a.add(const HiddenBooksChanged());
    await settle();

    expect(b.state.library, same(before));
    await a.close();
  });
}
