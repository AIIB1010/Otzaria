import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/widgets/lv_keyboard.dart';
import 'package:otzaria/low_vision/view/widgets/lv_pressable.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';

const _maxResults = 60;

/// חיפוש ספרים: שורת חיפוש גדולה, מקלדת ענקית ותוצאות בשורות ענקיות.
class LvSearchScreen extends StatefulWidget {
  const LvSearchScreen({super.key, this.search});

  /// לבדיקות: מחליף את חיפוש הספרייה.
  final Future<List<Book>> Function(String query)? search;

  @override
  State<LvSearchScreen> createState() => _LvSearchScreenState();
}

class _LvSearchScreenState extends State<LvSearchScreen> {
  String _query = '';
  List<Book> _results = const [];
  bool _searching = false;
  bool _keyboardVisible = true;
  int _selected = -1;

  /// במקלדת ענקית במסך רחב: שורה עליונה עם תיבת חיפוש קטנה והתוצאה מובלטת.
  bool _hugeLayout = false;

  /// איזו תוצאה מוצגת בשורה העליונה במקלדת הענקית.
  int _peekIndex = 0;
  int _searchSeq = 0;
  Timer? _debounce;
  final _scroll = ScrollController();
  final _rowKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _selected = -1;
      _peekIndex = 0;
    });
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _searchSeq++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  /// חיפוש בספרייה, בלי כפילויות של מסכתות בבלי (טקסט וגם PDF לאותה מסכת):
  /// מסכת מוצגת פעם אחת, וצורת הפתיחה נקבעת לפי ההגדרה.
  Future<List<Book>> _findInLibrary(String query) async {
    final results = await DataRepository.instance.findBooks(query, null);
    try {
      final library = await DataRepository.instance.library;
      final titles = talmudBavliTextTitles(library);
      return [
        for (final book in results)
          if (!isTalmudBavliPdfLibraryDuplicate(book, titles)) book,
      ];
    } catch (_) {
      return results;
    }
  }

  Future<void> _runSearch() async {
    final seq = ++_searchSeq;
    final query = _query.trim();
    List<Book> found;
    try {
      found = await (widget.search?.call(query) ?? _findInLibrary(query));
    } catch (_) {
      found = const [];
    }
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = found.take(_maxResults).toList();
      _searching = false;
    });
  }

  void _append(String text) => _setQuery(_query + text);

  void _backspace() {
    if (_query.isEmpty) return;
    final chars = _query.characters;
    _setQuery(chars.skipLast(1).toString());
  }

  /// "חפש": מציג את התוצאות על כל המסך.
  void _submit() {
    _debounce?.cancel();
    if (_query.trim().isNotEmpty) unawaited(_runSearch());
    setState(() => _keyboardVisible = false);
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(
      () {
        final from = _selected < 0
            ? (delta > 0 ? -1 : _results.length)
            : _selected;
        _selected = (from + delta).clamp(0, _results.length - 1);
      },
    );
    final context = _rowKeys[_selected]?.currentContext;
    if (context != null) Scrollable.ensureVisible(context, alignment: 0.5);
  }

  void _page(double direction) {
    if (!_scroll.hasClients) return;
    final step = _scroll.position.viewportDimension * 0.85 * direction;
    _scroll.animateTo(
      (_scroll.offset + step).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _open(Book book) => lvOpenBook(context, book);

  /// מקלדת חיצונית: תווים נכנסים לשורת החיפוש.
  bool _onRawKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_hugeLayout && _results.isNotEmpty) {
        _open(_results[_peekIndex.clamp(0, _results.length - 1)]);
      } else if (_selected >= 0 && _results.isNotEmpty) {
        _open(_results[_selected]);
      } else if (_keyboardVisible || _results.isEmpty) {
        _submit();
      } else {
        _open(_results[0]);
      }
      return true;
    }
    final char = event.character;
    if (char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 0x20 &&
        char.codeUnitAt(0) != 0x7f &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _append(char);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final wide = m.isWide;
    final keyboardFraction = context.select(
      (LowVisionCubit c) => c.state.keyboardFraction,
    );
    final hidePeek = context.select(
      (LowVisionCubit c) => c.state.keyboardHidesPeek,
    );
    final sideBySide =
        wide && context.select((LowVisionCubit c) => c.state.searchSideBySide);
    _hugeLayout = wide && hidePeek && _keyboardVisible;
    final queryBar = _QueryBar(
      query: _query,
      onClear: () => _setQuery(''),
      palette: p,
      metrics: m,
    );
    return LvKeyScope(
      onRawKey: _onRawKey,
      actions: {
        LvAction.back: () => Navigator.of(context).maybePop(),
        LvAction.down: () => _move(1),
        LvAction.up: () => _move(-1),
        LvAction.scrollDown: () => _page(0.35),
        LvAction.scrollUp: () => _page(-0.35),
        LvAction.next: () => _page(1),
        LvAction.previous: () => _page(-1),
      },
      child: _hugeLayout
          ? _hugeScreen(m, p)
          : LvScaffold(
              title: 'חיפוש ספרים',
              // החזקה ארוכה על מקש מוחקת הכל, ולכן אין כאן "החזקה לחזרה".
              holdToGoBack: false,
              // במסך צר שורת החיפוש יורדת לשורה משלה, כדי שלא תיעלם בין הכפתורים.
              titleWidget: wide ? queryBar : null,
              onBack: () => Navigator.of(context).maybePop(),
              actions: [
                LvButton(
                  label: _keyboardVisible ? 'הסתר מקלדת' : 'מקלדת',
                  icon: FluentIcons.keyboard_24_filled,
                  iconOnly: !wide,
                  filled: false,
                  onPressed: () =>
                      setState(() => _keyboardVisible = !_keyboardVisible),
                ),
              ],
              body: sideBySide
                  ? _sideBySideBody(m, p, keyboardFraction, hidePeek)
                  : LayoutBuilder(
                      builder: (context, box) {
                        // המקלדת לא תיקח את כל המקום: נשאר לפחות אזור קטן לתוצאות.
                        final fixed =
                            (wide ? 0 : m.tapHeight + m.gap * 2) + m.gap;
                        // נשאר מקום לשורת תוצאה אחת גדולה מעל המקלדת (חוץ מבענקית).
                        final peek = hidePeek
                            ? 0.0
                            : m.tapHeight * 1.3 + m.gap * 2;
                        final maxKeyboard = box.maxHeight - fixed - peek;
                        final keyboardHeight = math.min(
                          MediaQuery.sizeOf(context).height * keyboardFraction,
                          math.max(0.0, maxKeyboard),
                        );
                        return Column(
                          children: [
                            if (!wide) ...[queryBar, SizedBox(height: m.gap)],
                            Expanded(
                              child: hidePeek && _keyboardVisible
                                  ? const SizedBox.shrink()
                                  : _buildResults(m, p),
                            ),
                            if (_keyboardVisible) ...[
                              SizedBox(height: m.gap),
                              SizedBox(
                                height: keyboardHeight,
                                child: LvKeyboard(
                                  onText: _append,
                                  onBackspace: _backspace,
                                  onClear: () => _setQuery(''),
                                  onSubmit: _submit,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
    );
  }

  /// מקלדת ענקית: למעלה תיבת חיפוש קטנה והתוצאה המתאימה ביותר מובלטת לידה,
  /// והמקלדת בגודלה המלא. אין כפתורי "חזרה" ו"הסתר מקלדת" למעלה: ה"חזרה"
  /// נמצאת במקום מקש "חפש" במקלדת, כי החיפוש ממילא חי.
  Widget _hugeScreen(LvMetrics m, LvPalette p) {
    // גובה שמכיל שם ספר בשתי שורות, או שורה אחת ושם המחבר מתחתיה.
    final rowHeight = m.unit * 2.6;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Material(
        color: p.background,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(m.gap),
            child: Column(
              children: [
                SizedBox(
                  height: rowHeight + m.gap,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _QueryBar(
                          query: _query,
                          onClear: () => _setQuery(''),
                          palette: p,
                          metrics: m,
                          height: rowHeight,
                          large: true,
                        ),
                      ),
                      SizedBox(width: m.gap * 1.5),
                      Expanded(child: _topResult(m, p, rowHeight)),
                    ],
                  ),
                ),
                Expanded(
                  child: LvKeyboard(
                    onText: _append,
                    onBackspace: _backspace,
                    onClear: () => _setQuery(''),
                    onSubmit: _submit,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// התוצאה המובלטת בשורה העליונה, עם כפתור למעבר לתוצאה הבאה.
  Widget _topResult(LvMetrics m, LvPalette p, double rowHeight) {
    Widget note(String text, {bool busy = false}) => Container(
      height: rowHeight,
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsets.symmetric(horizontal: m.gap * 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(m.radius),
        border: Border.all(color: p.foreground, width: m.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: p.foreground,
          fontSize: m.title,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (_query.trim().isEmpty) return note('הקלידו את שם הספר');
    if (_results.isEmpty) {
      return note(_searching ? 'מחפש…' : 'לא נמצאו ספרים');
    }
    final index = _peekIndex.clamp(0, _results.length - 1);
    // השורה מתמלאת לגובה המלא, כדי להתיישר עם תיבת החיפוש לידה.
    return SizedBox(
      height: rowHeight + m.gap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _resultRow(m, p, index, emphasized: true)),
          if (_results.length > 1) ...[
            SizedBox(width: m.gap),
            Padding(
              padding: EdgeInsets.only(bottom: m.gap),
              child: SizedBox(
                width: m.tapHeight * 1.1,
                child: LvButton(
                  label: 'התוצאה הבאה (${index + 1} מתוך ${_results.length})',
                  icon: FluentIcons.chevron_right_24_filled,
                  iconOnly: true,
                  filled: false,
                  height: double.infinity,
                  onPressed: () => setState(
                    () => _peekIndex = (index + 1) % _results.length,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// מסך רחב: התוצאות בעמודה מימין והמקלדת משמאל, בגובה מלא. כך נראות הרבה
  /// תוצאות גם כשהמקלדת גדולה. ב"ענקית" המקלדת תופסת את כל הרוחב.
  Widget _sideBySideBody(
    LvMetrics m,
    LvPalette p,
    double keyboardFraction,
    bool hidePeek,
  ) {
    return LayoutBuilder(
      builder: (context, box) {
        final gap = m.gap * 1.5;
        final keyboardOnly = hidePeek && _keyboardVisible;
        final keyboard = LvKeyboard(
          onText: _append,
          onBackspace: _backspace,
          onClear: () => _setQuery(''),
          onSubmit: _submit,
        );
        if (keyboardOnly) return keyboard;
        return Row(
          children: [
            Expanded(child: _buildResults(m, p, compact: true)),
            if (_keyboardVisible) ...[
              SizedBox(width: gap),
              SizedBox(width: box.maxWidth * keyboardFraction, child: keyboard),
            ],
          ],
        );
      },
    );
  }

  /// שורת תוצאה. שם הספר קודם לכול: הוא נשאר גדול, ועובר לשתי שורות כשהוא ארוך.
  /// המחבר חשוב פחות, ולכן מופיע (בצד שמאל, או מתחת לשם) רק אם נשאר לו מקום.
  Widget _resultRow(
    LvMetrics m,
    LvPalette p,
    int i, {
    GlobalKey? key,
    bool compact = false,
    bool emphasized = false,
    bool oneLine = false,
  }) {
    final book = _results[i];
    final author = book.author ?? '';
    final selected = emphasized || i == _selected;
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final inner = box.maxWidth - m.gap * 4 - m.border * 2;
        final base = m.unit * (compact ? 0.9 : 1.05);
        final authorSize = m.unit * 0.6;
        const titleWeight = FontWeight.w800;
        final titleWidth = _textWidth(
          book.title,
          TextStyle(fontSize: base, fontWeight: titleWeight, height: 1.15),
          scaler,
          1,
        );
        final authorWidth = author.isEmpty
            ? 0.0
            : _textWidth(
                author,
                TextStyle(fontSize: authorSize, fontWeight: FontWeight.w600),
                scaler,
                1,
              );
        var size = base;
        var inline = false;
        var below = false;
        if (titleWidth <= inner) {
          inline = authorWidth > 0 && titleWidth + m.gap + authorWidth <= inner;
          below = authorWidth > 0 && !inline && !oneLine;
        } else if (oneLine) {
          // אין גובה לשתי שורות: השם מתכווץ מעט והמחבר מוותר.
          size = math.max(base * inner / titleWidth, base * 0.55);
        } else {
          size = base * 0.8;
          while (size > base * 0.5 &&
              _textWidth(
                    book.title,
                    TextStyle(
                      fontSize: size,
                      fontWeight: titleWeight,
                      height: 1.15,
                    ),
                    scaler,
                    2,
                    maxWidth: inner,
                  ) <
                  0) {
            size *= 0.92;
          }
          below = !emphasized && authorWidth > 0;
        }
        return LvRow(
          key: key,
          title: book.title,
          titleSize: size,
          subtitle: below ? author : null,
          selected: selected,
          trailing: inline
              ? Text(
                  author,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? p.onAccent : p.foreground,
                    fontSize: authorSize,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
          onTap: () => _open(book),
        );
      },
    );
  }

  /// רוחב הטקסט בשורה אחת. עם [maxWidth] מחזיר -1 כשהטקסט לא נכנס ב-[maxLines].
  static double _textWidth(
    String text,
    TextStyle style,
    TextScaler scaler,
    int maxLines, {
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final width = painter.didExceedMaxLines ? -1.0 : painter.width;
    painter.dispose();
    return width;
  }

  Widget _buildResults(LvMetrics m, LvPalette p, {bool compact = false}) {
    if (_query.trim().isEmpty) {
      return const LvMessage('הקלידו את שם הספר');
    }
    if (_results.isEmpty) {
      return _searching
          ? const LvMessage('מחפש…', busy: true)
          : const LvMessage('לא נמצאו ספרים');
    }
    // בזמן הקלדה (המקלדת מוצגת) יש מקום לתוצאה אחת בלבד, אז מציגים את
    // המתאימה ביותר בגדול. "חפש" מציג את כל התוצאות על כל המסך.
    if (_keyboardVisible && !compact) {
      return Align(
        alignment: Alignment.topCenter,
        child: _resultRow(m, p, 0, oneLine: true),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              children: [
                for (var i = 0; i < _results.length; i++)
                  _resultRow(
                    m,
                    p,
                    i,
                    compact: compact,
                    key: _rowKeys.putIfAbsent(i, GlobalKey.new),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: m.gap),
        LvScrollButtons(onUp: () => _page(-1), onDown: () => _page(1)),
      ],
    );
  }
}

class _QueryBar extends StatelessWidget {
  const _QueryBar({
    required this.query,
    required this.onClear,
    required this.palette,
    required this.metrics,
    this.height,
    this.large = false,
  });

  final String query;
  final VoidCallback onClear;
  final LvPalette palette;
  final LvMetrics metrics;

  /// גובה מותאם (בשורה העליונה של המקלדת הענקית).
  final double? height;

  /// במקלדת הענקית: בלי אייקונים, כדי שכל הרוחב יהיה לטקסט, ובגופן הגדול ביותר.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final p = palette;
    return Container(
      height: height ?? m.tapHeight,
      padding: EdgeInsets.symmetric(horizontal: m.gap * 2, vertical: m.gap),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(m.radius),
        border: Border.all(color: p.foreground, width: m.border * 1.5),
      ),
      child: Row(
        children: [
          if (!large) ...[
            Icon(
              FluentIcons.search_24_filled,
              size: m.iconSize,
              color: p.foreground,
            ),
            SizedBox(width: m.gap),
          ],
          Expanded(
            // טקסט ארוך מתכווץ, ולא נחתך: מה שהוקלד אחרון חייב להיראות.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                query.isEmpty ? 'שם הספר…' : query,
                maxLines: 1,
                style: TextStyle(
                  color: query.isEmpty
                      ? p.foreground.withValues(alpha: 0.55)
                      : p.foreground,
                  fontSize: large ? m.unit * 1.05 : m.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (query.isNotEmpty && !large)
            LvPressable(
              onTap: onClear,
              builder: (context, pressed) => Container(
                padding: EdgeInsets.all(m.gap * 0.4),
                decoration: BoxDecoration(
                  color: pressed ? p.foreground : null,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  FluentIcons.dismiss_circle_24_filled,
                  size: m.iconSize * 0.9,
                  color: pressed ? p.background : p.foreground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
