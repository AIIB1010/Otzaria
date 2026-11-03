import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/models/lv_toc.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_toc_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_reader_chrome.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

final _headingTag = RegExp(r'^\s*<h[1-6][ >]', caseSensitive: false);

/// קורא ספרי טקסט: אותיות ענקיות, גלילה בעמודים, ודילוג מדויק לסעיפים.
class LvTextReader extends StatefulWidget {
  const LvTextReader({
    super.key,
    required this.book,
    this.source,
    this.loadText,
    this.loadToc,
  });

  /// הספר לטעינה.
  final TextBook book;

  /// הספר המקורי כפי ששמור ברשימה (כשהוא הומר ל-[TextBook]).
  final Book? source;

  /// לבדיקות.
  final Future<String> Function()? loadText;
  final Future<List<TocEntry>> Function()? loadToc;

  @override
  State<LvTextReader> createState() => _LvTextReaderState();
}

class _LvTextReaderState extends State<LvTextReader> {
  final _itemScroll = ItemScrollController();
  final _offsetScroll = ScrollOffsetController();
  final _positions = ItemPositionsListener.create();

  List<String>? _lines;
  Object? _error;
  List<LvTocItem> _tocTree = const [];
  List<LvTocItem> _tocFlat = const [];
  int _firstLine = 0;
  double _leadingEdge = 0;
  double _viewport = 0;
  double? _lastScale;
  LowVisionCubit? _cubit;

  Book get _tracked => widget.source ?? widget.book;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<LowVisionCubit>();
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    unawaited(_cubit?.flush());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _lines = null;
      _error = null;
    });
    try {
      final text =
          await (widget.loadText?.call() ??
              TextBookRepository(
                fileSystem: FileSystemData.instance,
              ).getBookContent(widget.book));
      if (!mounted) return;
      final lines = text.isEmpty ? <String>[] : text.split('\n');
      final saved = _cubit?.positionOf(_tracked);
      setState(() {
        _lines = lines;
        if (saved != null) {
          _firstLine = saved.index.clamp(0, math.max(0, lines.length - 1));
          _leadingEdge = saved.fraction;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    unawaited(_loadToc());
  }

  Future<void> _loadToc() async {
    try {
      final roots =
          await (widget.loadToc?.call() ?? widget.book.tableOfContents);
      if (!mounted) return;
      final tree = LvTocItem.fromTocEntries(roots);
      final flat = LvTocItem.flatten(tree)
        ..sort((a, b) => a.target.compareTo(b.target));
      setState(() {
        _tocTree = tree;
        _tocFlat = flat;
      });
    } catch (_) {
      // בלי תוכן עניינים הקורא ממשיך לעבוד, בלי כפתורי הסעיפים.
    }
  }

  void _onPositions() {
    final positions = _positions.itemPositions.value;
    ItemPosition? first;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0) continue;
      if (first == null || p.index < first.index) first = p;
    }
    if (first == null || !mounted) return;
    if (first.index == _firstLine && first.itemLeadingEdge == _leadingEdge) {
      return;
    }
    setState(() {
      _firstLine = first!.index;
      _leadingEdge = first.itemLeadingEdge;
    });
    _cubit?.savePosition(
      _tracked,
      LvReadingPosition(_firstLine, _leadingEdge.clamp(-1.0, 0.0)),
    );
  }

  // --- ניווט ---

  void _page(double direction) {
    if (_viewport <= 0 || !_offsetScroll.isAttached) return;
    unawaited(
      _offsetScroll.animateScroll(
        offset: _viewport * 0.88 * direction,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ),
    );
  }

  void _jumpToLine(int line) {
    final count = _lines?.length ?? 0;
    if (count == 0 || !_itemScroll.isAttached) return;
    _itemScroll.jumpTo(index: line.clamp(0, count - 1));
  }

  /// הסעיף הנוכחי: האחרון שנקודת ההתחלה שלו לא אחרי השורה הנראית.
  int get _currentSectionIndex {
    var low = 0;
    var high = _tocFlat.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_tocFlat[mid].target <= _firstLine) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  void _nextSection() {
    for (final item in _tocFlat) {
      if (item.target > _firstLine) return _jumpToLine(item.target);
    }
    _jumpToLine((_lines?.length ?? 1) - 1);
  }

  void _previousSection() {
    final current = _currentSectionIndex;
    if (current < 0) return _jumpToLine(0);
    if (_tocFlat[current].target < _firstLine || current == 0) {
      return _jumpToLine(_tocFlat[current].target);
    }
    _jumpToLine(_tocFlat[current - 1].target);
  }

  Future<void> _openContents() async {
    final target = await lvPush<int>(
      context,
      LvTocScreen(items: _tocTree, bookTitle: widget.book.title),
    );
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLine(target));
    }
  }

  // --- תצוגה ---

  String _display(String raw, bool showNikud) {
    var text = stripHtmlPreservingBreaks(raw).trim();
    if (!showNikud) text = removeVolwels(text);
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LowVisionCubit>().state;
    final lines = _lines;
    if (_error != null) {
      return LvScaffold(
        title: widget.book.title,
        onBack: () => Navigator.of(context).maybePop(),
        body: LvMessage(
          'לא ניתן לפתוח את הספר',
          action: LvButton(label: 'נסו שוב', onPressed: _load),
        ),
      );
    }
    if (lines == null) {
      return LvScaffold(
        title: widget.book.title,
        onBack: () => Navigator.of(context).maybePop(),
        body: const LvMessage('הספר נטען…', busy: true),
      );
    }
    if (lines.isEmpty) {
      return LvScaffold(
        title: widget.book.title,
        onBack: () => Navigator.of(context).maybePop(),
        body: const LvMessage('לא נמצא טקסט בספר הזה'),
      );
    }
    _restoreAfterZoom(state);
    final section = _currentSectionIndex;
    final hasToc = _tocFlat.isNotEmpty;
    final percent = lines.length <= 1
        ? 100
        : ((_firstLine / (lines.length - 1)) * 100).round();
    return LvReaderChrome(
      book: _tracked,
      progress: '$percent% מהספר',
      sectionLabel: hasToc && section >= 0 ? _tocFlat[section].title : null,
      onNext: () => _page(1),
      onPrevious: () => _page(-1),
      onZoomIn: context.read<LowVisionCubit>().zoomIn,
      onZoomOut: context.read<LowVisionCubit>().zoomOut,
      onFirst: () => _jumpToLine(0),
      onLast: () => _jumpToLine(lines.length - 1),
      onNextSection: hasToc ? _nextSection : null,
      onPreviousSection: hasToc ? _previousSection : null,
      onContents: hasToc ? _openContents : null,
      child: LayoutBuilder(
        builder: (context, box) {
          _viewport = box.maxHeight;
          return _buildList(context, lines, state);
        },
      ),
    );
  }

  /// אחרי שינוי גודל הגופן נשארים באותה שורה, ולא קופצים למקום אחר.
  void _restoreAfterZoom(LowVisionState state) {
    final previous = _lastScale;
    _lastScale = state.textScale;
    if (previous == null || previous == state.textScale) return;
    final line = _firstLine;
    final edge = _leadingEdge.clamp(-1.0, 0.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _itemScroll.isAttached) {
        _itemScroll.jumpTo(index: line, alignment: edge);
      }
    });
  }

  Widget _buildList(
    BuildContext context,
    List<String> lines,
    LowVisionState state,
  ) {
    final m = LvMetrics.of(context);
    final p = state.palette;
    final fontSize = m.unit * 0.95 * state.textScale;
    final style = TextStyle(
      color: p.foreground,
      fontSize: fontSize,
      height: 1.45,
      fontWeight: FontWeight.w500,
    );
    return ScrollablePositionedList.builder(
      itemCount: lines.length,
      itemScrollController: _itemScroll,
      scrollOffsetController: _offsetScroll,
      itemPositionsListener: _positions,
      initialScrollIndex: _firstLine,
      initialAlignment: _leadingEdge.clamp(-1.0, 0.0),
      itemBuilder: (context, index) {
        final raw = lines[index];
        final text = _display(raw, state.showNikud);
        if (text.isEmpty) return SizedBox(height: fontSize * 0.35);
        final heading = _headingTag.hasMatch(raw);
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.gap * 2,
            vertical: fontSize * 0.12,
          ),
          child: Text(
            text,
            style: heading
                ? style.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize * 1.15,
                  )
                : style,
          ),
        );
      },
    );
  }
}
