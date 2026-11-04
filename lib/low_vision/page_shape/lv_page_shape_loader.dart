import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_default_commentators.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// מיקום מפרש בעמוד. "ימין" ו"שמאל" פיזיים; המיפוי לפי ברירות המחדל של אוצריא
/// (position 0 = ימין, 1 = שמאל, 2 = תחתון, 3 = תחתון נוסף).
enum LvPanelSlot { right, left, bottom, bottomSecond }

class LvPanelSpec {
  const LvPanelSpec(this.slot, this.title);

  final LvPanelSlot slot;
  final String title;
}

class LvPanelData {
  const LvPanelData({
    required this.slot,
    required this.title,
    required this.entries,
  });

  final LvPanelSlot slot;
  final String title;

  /// קטעי המפרש לפי סדר העוגנים בטקסט (HTML גולמי).
  final List<String> entries;
}

class LvPageShapeData {
  const LvPageShapeData({required this.mainLines, required this.panels});

  /// שורות הטקסט הראשי של הקטע (HTML גולמי).
  final List<String> mainLines;
  final List<LvPanelData> panels;

  LvPanelData? panel(LvPanelSlot slot) {
    for (final p in panels) {
      if (p.slot == slot && p.entries.isNotEmpty) return p;
    }
    return null;
  }

  bool get hasCommentary => panels.any((p) => p.entries.isNotEmpty);
}

/// קטע מפרש אחד שקושר לשורה בטקסט הראשי.
typedef LvCommentaryEntry = ({int line, String title, String html});

/// טוען את נתוני "צורת הדף": אילו מפרשים מוגדרים לספר (ברירות המחדל של אוצריא)
/// ואת קטעי המפרשים של קטע נתון. ההזרקות מיועדות לבדיקות.
class LvPageShapeLoader {
  LvPageShapeLoader({
    this._repository,
    this._specsLoader,
    this._entriesLoader,
    this.maxEntriesPerPanel = 250,
  });

  final TextBookRepository? _repository;
  final Future<List<LvPanelSpec>> Function(TextBook book)? _specsLoader;
  final Future<List<LvCommentaryEntry>> Function(
    TextBook book,
    int start,
    int end,
    List<String> titles,
  )?
  _entriesLoader;
  final int maxEntriesPerPanel;

  final _cache = <String, LvPageShapeData>{};

  TextBookRepository get _repo =>
      _repository ?? TextBookRepository(fileSystem: FileSystemData.instance);

  /// המפרשים שהוגדרו לספר. רשימה ריקה = לספר אין צורת הדף.
  Future<List<LvPanelSpec>> loadSpecs(TextBook book) async {
    final custom = _specsLoader;
    if (custom != null) return custom(book);
    final available = await _repo.getAvailableCommentators(book);
    final defaults = await PageShapeDefaultCommentators.getPageShapeDefaults(
      book,
      availableCommentators: available,
    );
    final c = defaults.commentators;
    // מפתחות הפאנלים באוצריא הפוכים לצד הפיזי: 'left' מוצג בימין.
    final pairs = <(LvPanelSlot, String?)>[
      (LvPanelSlot.right, c['left']),
      (LvPanelSlot.left, c['right']),
      (LvPanelSlot.bottom, c['bottom']),
      (LvPanelSlot.bottomSecond, c['bottomRight']),
    ];
    return [
      for (final (slot, title) in pairs)
        if (title != null && title.trim().isNotEmpty)
          LvPanelSpec(slot, title.trim()),
    ];
  }

  /// הטקסט הראשי והמפרשים של השורות [start]..[end] (כולל, 0-based).
  Future<LvPageShapeData> loadSection(
    TextBook book,
    List<String> allLines,
    int start,
    int end,
    List<LvPanelSpec> specs,
  ) async {
    final key = '${book.title}|$start|$end|${specs.length}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final lastLine = allLines.isEmpty ? 0 : allLines.length - 1;
    final from = start.clamp(0, lastLine);
    final to = end.clamp(from, lastLine);
    final main = allLines.isEmpty
        ? const <String>[]
        : allLines.sublist(from, to + 1);

    final titles = [for (final s in specs) s.title];
    var entries = const <LvCommentaryEntry>[];
    if (titles.isNotEmpty) {
      try {
        entries =
            await (_entriesLoader?.call(book, from, to, titles) ??
                _defaultEntries(book, from, to, titles));
      } catch (_) {
        // בלי מפרשים הדף עדיין מציג את הטקסט הראשי.
      }
    }
    final panels = [
      for (final spec in specs)
        LvPanelData(
          slot: spec.slot,
          title: spec.title,
          entries: [
            for (final e in entries)
              if (e.title == spec.title) e.html,
          ].take(maxEntriesPerPanel).toList(),
        ),
    ];
    final data = LvPageShapeData(mainLines: main, panels: panels);
    if (_cache.length > 30) _cache.remove(_cache.keys.first);
    return _cache[key] = data;
  }

  Future<List<LvCommentaryEntry>> _defaultEntries(
    TextBook book,
    int start,
    int end,
    List<String> titles,
  ) async {
    final links = await _repo.getBookLinksInRange(
      book,
      startIndex: start,
      endIndex: end,
      targetBookTitles: titles,
    );
    final wanted = titles.toSet();
    final dependent =
        [
          for (final link in links)
            if (LinkTypes.isDependentTextLink(link.connectionType) &&
                wanted.contains(getTitleFromPath(link.path2)))
              link,
        ]..sort((a, b) {
          final byLine = a.index1.compareTo(b.index1);
          return byLine != 0 ? byLine : a.index2.compareTo(b.index2);
        });
    final contents = await Future.wait([
      for (final link in dependent)
        link.content.then<String?>((v) => v, onError: (_) => null),
    ]);
    return [
      for (var i = 0; i < dependent.length; i++)
        if (contents[i] != null && !contents[i]!.startsWith('שגיאה'))
          (
            line: dependent[i].index1 - 1,
            title: getTitleFromPath(dependent[i].path2),
            html: contents[i]!,
          ),
    ];
  }
}
