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

  Future<void> _runSearch() async {
    final seq = ++_searchSeq;
    final query = _query.trim();
    List<Book> found;
    try {
      found =
          await (widget.search?.call(query) ??
              DataRepository.instance.findBooks(query, null));
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
      if (_keyboardVisible || _results.isEmpty) {
        _submit();
      } else {
        _open(_results[_selected < 0 ? 0 : _selected]);
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
      child: LvScaffold(
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
        body: LayoutBuilder(
          builder: (context, box) {
            // המקלדת לא תיקח את כל המקום: נשאר לפחות אזור קטן לתוצאות.
            final fixed = (wide ? 0 : m.tapHeight + m.gap * 2) + m.gap;
            final maxKeyboard = box.maxHeight - fixed - m.tapHeight;
            final keyboardHeight = math.min(
              MediaQuery.sizeOf(context).height * keyboardFraction,
              math.max(0.0, maxKeyboard),
            );
            return Column(
              children: [
                if (!wide) ...[queryBar, SizedBox(height: m.gap)],
                Expanded(child: _buildResults(m)),
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

  Widget _buildResults(LvMetrics m) {
    if (_query.trim().isEmpty) {
      return const LvMessage('הקלידו את שם הספר');
    }
    if (_results.isEmpty) {
      return _searching
          ? const LvMessage('מחפש…', busy: true)
          : const LvMessage('לא נמצאו ספרים');
    }
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              children: [
                for (var i = 0; i < _results.length; i++)
                  LvRow(
                    key: _rowKeys.putIfAbsent(i, GlobalKey.new),
                    title: _results[i].title,
                    subtitle: _results[i].author,
                    selected: !_keyboardVisible && i == _selected,
                    onTap: () => _open(_results[i]),
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
  });

  final String query;
  final VoidCallback onClear;
  final LvPalette palette;
  final LvMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final p = palette;
    return Container(
      height: m.tapHeight,
      padding: EdgeInsets.symmetric(horizontal: m.gap * 2, vertical: m.gap),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(m.radius),
        border: Border.all(color: p.foreground, width: m.border * 1.5),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.search_24_filled,
            size: m.iconSize,
            color: p.foreground,
          ),
          SizedBox(width: m.gap),
          Expanded(
            child: Text(
              query.isEmpty ? 'שם הספר…' : query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: query.isEmpty
                    ? p.foreground.withValues(alpha: 0.55)
                    : p.foreground,
                fontSize: m.body,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (query.isNotEmpty)
            LvPressable(
              onTap: onClear,
              builder: (context, pressed) => Container(
                padding: EdgeInsets.all(m.gap),
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
