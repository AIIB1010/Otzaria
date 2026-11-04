import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/models/lv_toc.dart';
import 'package:otzaria/low_vision/page_shape/lv_page_shape_loader.dart';
import 'package:otzaria/low_vision/page_shape/lv_page_shape_view.dart';
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
    this.pageShapeLoader,
  });

  /// הספר לטעינה.
  final TextBook book;

  /// הספר המקורי כפי ששמור ברשימה (כשהוא הומר ל-[TextBook]).
  final Book? source;

  /// לבדיקות.
  final Future<String> Function()? loadText;
  final Future<List<TocEntry>> Function()? loadToc;
  final LvPageShapeLoader? pageShapeLoader;

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

  // --- צורת הדף ---
  late final LvPageShapeLoader _pageShapeLoader =
      widget.pageShapeLoader ?? LvPageShapeLoader();
  final _pageShapeController = LvPageShapeController();
  List<LvPanelSpec> _panelSpecs = const [];
  bool _pageShapeAvailable = false;
  bool _pageShape = false;
  List<_Section> _sections = const [];
  int _sectionIndex = 0;
  Future<LvPageShapeData>? _pageData;

  /// גרסת הצילום (PDF) של אותו ספר, אם יש.
  Book? _pdfVersion;

  Book get _tracked => widget.source ?? widget.book;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    unawaited(_load());
    unawaited(_findPdfVersion());
  }

  Future<void> _findPdfVersion() async {
    try {
      final library = await DataRepository.instance.library;
      final pdf = library.getCompanionBook(_tracked, PdfBook);
      if (mounted && pdf != null) setState(() => _pdfVersion = pdf);
    } catch (_) {
      // בלי ספרייה נשארים בתצוגת הטקסט.
    }
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
    if (mounted) unawaited(_detectPageShape());
  }

  // ---------- צורת הדף ----------

  /// עלים של עץ התוכן (למשל עמוד בגמרא), לפי סדר הטקסט. בלי תוכן עניינים:
  /// קטעים קבועים של 40 שורות.
  List<_Section> _buildSections(int lineCount) {
    if (lineCount <= 0) return const [];
    final leaves = <LvTocItem>[];
    void walk(List<LvTocItem> items) {
      for (final item in items) {
        if (item.children.isEmpty) {
          leaves.add(item);
        } else {
          walk(item.children);
        }
      }
    }

    walk(_tocTree);
    final starts = <int, String>{};
    for (final leaf in leaves) {
      if (leaf.target >= 0 && leaf.target < lineCount) {
        starts.putIfAbsent(leaf.target, () => leaf.title);
      }
    }
    if (starts.isEmpty) {
      return [
        for (var s = 0, n = 1; s < lineCount; s += 40, n++)
          _Section('חלק $n', s, math.min(s + 39, lineCount - 1)),
      ];
    }
    final sorted = starts.keys.toList()..sort();
    final result = <_Section>[];
    if (sorted.first > 0) result.add(_Section('פתיחה', 0, sorted.first - 1));
    for (var i = 0; i < sorted.length; i++) {
      final end = i + 1 < sorted.length ? sorted[i + 1] - 1 : lineCount - 1;
      result.add(_Section(starts[sorted[i]]!, sorted[i], end));
    }
    return result;
  }

  int _sectionAtLine(int line) {
    for (var i = _sections.length - 1; i >= 0; i--) {
      if (_sections[i].start <= line) return i;
    }
    return 0;
  }

  Future<void> _detectPageShape() async {
    final lines = _lines;
    if (lines == null || lines.isEmpty) return;
    try {
      final specs = await _pageShapeLoader.loadSpecs(widget.book);
      if (!mounted) return;
      setState(() {
        _panelSpecs = specs;
        _pageShapeAvailable = specs.isNotEmpty;
        _sections = _buildSections(lines.length);
      });
      if (specs.isNotEmpty && (_cubit?.state.preferPageShape ?? false)) {
        _enterPageShape();
      }
    } catch (_) {
      // ספר בלי מפרשים מוגדרים: אין צורת הדף, והקורא הרגיל ממשיך לעבוד.
    }
  }

  void _loadSection(int index) {
    final lines = _lines;
    if (lines == null || _sections.isEmpty) return;
    final i = index.clamp(0, _sections.length - 1);
    final section = _sections[i];
    setState(() {
      _sectionIndex = i;
      _pageData = _pageShapeLoader.loadSection(
        widget.book,
        lines,
        section.start,
        section.end,
        _panelSpecs,
      );
    });
    _firstLine = section.start;
    _cubit?.savePosition(_tracked, LvReadingPosition(section.start));
  }

  void _enterPageShape() {
    if (_sections.isEmpty) return;
    _pageShape = true;
    _loadSection(_sectionAtLine(_firstLine));
    _cubit?.setPreferPageShape(true);
  }

  void _exitPageShape() {
    final start = _sections.isEmpty ? 0 : _sections[_sectionIndex].start;
    setState(() => _pageShape = false);
    _cubit?.setPreferPageShape(false);
    _firstLine = start;
    _leadingEdge = 0;
  }

  void _toggleView() => _pageShape ? _exitPageShape() : _enterPageShape();

  void _gotoSection(int index) {
    if (index < 0 || index >= _sections.length) return;
    _loadSection(index);
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

  /// גלילה קטנה, לחוגה פיזית: חמישית מגובה התצוגה.
  void _scrollBy(double direction) {
    if (_viewport <= 0 || !_offsetScroll.isAttached) return;
    unawaited(
      _offsetScroll.animateScroll(
        offset: _viewport * 0.2 * direction,
        duration: const Duration(milliseconds: 90),
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
    if (target == null) return;
    if (_pageShape) {
      _loadSection(_sectionAtLine(target));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLine(target));
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
    final inPageShape = _pageShape && _sections.isNotEmpty;
    return LvReaderChrome(
      book: _tracked,
      progress: inPageShape
          ? 'עמוד ${_sectionIndex + 1} מתוך ${_sections.length}'
          : '$percent% מהספר',
      sectionLabel: inPageShape
          ? _sections[_sectionIndex].title
          : (hasToc && section >= 0 ? _tocFlat[section].title : null),
      // בצורת הדף "עמוד הבא" הוא הקטע הבא (למשל עמוד בגמרא), והזום מגדיל את הדף.
      onNext: inPageShape
          ? () => _gotoSection(_sectionIndex + 1)
          : () => _page(1),
      onPrevious: inPageShape
          ? () => _gotoSection(_sectionIndex - 1)
          : () => _page(-1),
      onZoomIn: inPageShape
          ? _pageShapeController.zoomIn
          : context.read<LowVisionCubit>().zoomIn,
      onZoomOut: inPageShape
          ? _pageShapeController.zoomOut
          : context.read<LowVisionCubit>().zoomOut,
      onScrollUp: () =>
          inPageShape ? _pageShapeController.scroll(-1) : _scrollBy(-1),
      onScrollDown: () =>
          inPageShape ? _pageShapeController.scroll(1) : _scrollBy(1),
      onFirst: () => inPageShape ? _gotoSection(0) : _jumpToLine(0),
      onLast: () => inPageShape
          ? _gotoSection(_sections.length - 1)
          : _jumpToLine(lines.length - 1),
      onNextSection: hasToc && !inPageShape ? _nextSection : null,
      onPreviousSection: hasToc && !inPageShape ? _previousSection : null,
      onContents: hasToc ? _openContents : null,
      extraActions: [
        if (_pageShapeAvailable)
          LvChromeAction(
            label: _pageShape ? 'טקסט' : 'צורת הדף',
            icon: _pageShape
                ? FluentIcons.text_t_24_filled
                : FluentIcons.document_one_page_24_filled,
            onPressed: _toggleView,
          ),
        if (_pdfVersion != null)
          LvChromeAction(
            label: 'צילום',
            icon: FluentIcons.image_24_filled,
            onPressed: () => lvOpenBook(context, _pdfVersion!, replace: true),
          ),
      ],
      child: inPageShape
          ? _pageShapeBody(state)
          : LayoutBuilder(
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

  Widget _pageShapeBody(LowVisionState state) {
    return FutureBuilder<LvPageShapeData>(
      future: _pageData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const LvMessage('לא ניתן לטעון את צורת הדף');
        }
        final data = snapshot.data;
        if (data == null) return const LvMessage('הדף נטען…', busy: true);
        return LvPageShapeView(
          data: data,
          controller: _pageShapeController,
          foreground: state.palette.foreground,
          background: state.palette.background,
          showNikud: state.showNikud,
          glide: state.glide,
        );
      },
    );
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

/// קטע בספר שמוצג כעמוד אחד בצורת הדף: שורות [start]..[end] (כולל).
class _Section {
  const _Section(this.title, this.start, this.end);

  final String title;
  final int start;
  final int end;
}
