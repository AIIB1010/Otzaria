import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/models/lv_toc.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_toc_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_reader_chrome.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';

/// קורא ספרים מצולמים (PDF): עמוד מוגדל, דפדוף בכפתורים, וצבעי ניגודיות
/// שמוחלים על התמונה עצמה (למשל אותיות צהובות על רקע שחור).
class LvPdfReader extends StatefulWidget {
  const LvPdfReader({super.key, required this.book});

  final PdfBook book;

  @override
  State<LvPdfReader> createState() => _LvPdfReaderState();
}

class _LvPdfReaderState extends State<LvPdfReader> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _pageCount = 0;
  List<LvTocItem> _outline = const [];
  List<LvTocItem> _outlineFlat = const [];
  LowVisionCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<LowVisionCubit>();
  }

  @override
  void dispose() {
    unawaited(_cubit?.flush());
    super.dispose();
  }

  int get _initialPage => math.max(
    1,
    context.read<LowVisionCubit>().positionOf(widget.book)?.index ?? 1,
  );

  Future<void> _onReady(PdfDocument document, PdfViewerController c) async {
    if (!mounted) return;
    setState(() => _pageCount = document.pages.length);
    try {
      final tree = LvTocItem.fromPdfOutline(await document.loadOutline());
      if (!mounted) return;
      final flat = LvTocItem.flatten(tree)
        ..sort((a, b) => a.target.compareTo(b.target));
      setState(() {
        _outline = tree;
        _outlineFlat = flat;
      });
    } catch (_) {
      // ללא תוכן עניינים נשארת האפשרות לקפוץ למספר עמוד.
    }
  }

  void _onPageChanged(int? page) {
    if (page == null || !mounted) return;
    setState(() => _page = page);
    _cubit?.savePosition(widget.book, LvReadingPosition(page));
  }

  void _goTo(int page) {
    if (!_controller.isReady) return;
    final target = math.min(math.max(1, page), math.max(1, _pageCount));
    unawaited(_controller.goToPage(pageNumber: target));
  }

  void _nextPage() => _goTo((_controller.pageNumber ?? _page) + 1);
  void _previousPage() => _goTo((_controller.pageNumber ?? _page) - 1);

  void _nextSection() {
    for (final item in _outlineFlat) {
      if (item.target > _page) return _goTo(item.target);
    }
  }

  void _previousSection() {
    for (final item in _outlineFlat.reversed) {
      if (item.target < _page) return _goTo(item.target);
    }
    _goTo(1);
  }

  Future<void> _openContents() async {
    final target = _outline.isNotEmpty
        ? await lvPush<int>(
            context,
            LvTocScreen(items: _outline, bookTitle: widget.book.title),
          )
        : await lvPush<int>(
            context,
            LvGotoPageScreen(pageCount: _pageCount, current: _page),
          );
    if (target != null) _goTo(target);
  }

  /// מטריצה שממפה לבן→רקע ושחור→צבע הטקסט, כדי שהעמוד המצולם ישתמש בערכה.
  static ColorFilter _filterFor(LvPalette palette) {
    double c(double v) => v * 255;
    final fg = palette.foreground;
    final bg = palette.background;
    List<double> row(double f, double b) => [
      (b - f) * 0.2126,
      (b - f) * 0.7152,
      (b - f) * 0.0722,
      0,
      c(f),
    ];
    return ColorFilter.matrix([
      ...row(fg.r, bg.r),
      ...row(fg.g, bg.g),
      ...row(fg.b, bg.b),
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  /// שחור על לבן הוא העמוד המקורי כפי שהוא; שאר הערכות ממופות מחדש.
  static Widget _withPalette(LvPalette palette, Widget child) =>
      palette == LvPalette.blackOnWhite
      ? child
      : ColorFiltered(colorFilter: _filterFor(palette), child: child);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LowVisionCubit>().state;
    final hasOutline = _outlineFlat.isNotEmpty;
    return LvReaderChrome(
      book: widget.book,
      progress: _pageCount > 0 ? 'עמוד $_page מתוך $_pageCount' : '',
      onNext: _nextPage,
      onPrevious: _previousPage,
      onZoomIn: () {
        if (_controller.isReady) unawaited(_controller.zoomUp());
      },
      onZoomOut: () {
        if (_controller.isReady) unawaited(_controller.zoomDown());
      },
      onFirst: () => _goTo(1),
      onLast: () => _goTo(_pageCount),
      onNextSection: hasOutline ? _nextSection : null,
      onPreviousSection: hasOutline ? _previousSection : null,
      onContents: _pageCount > 0 ? _openContents : null,
      contentsLabel: hasOutline ? 'תוכן' : 'עבור לעמוד',
      contentsIcon: hasOutline
          ? FluentIcons.text_bullet_list_24_filled
          : FluentIcons.number_symbol_24_filled,
      child: ColoredBox(
        color: state.palette.background,
        child: _withPalette(
          state.palette,
          PdfViewer.file(
            widget.book.path,
            controller: _controller,
            initialPageNumber: _initialPage,
            params: PdfViewerParams(
              backgroundColor: Colors.white,
              // עמוד אחד במסך וזום עד פי 20, כמו בקורא הרגיל של אוצריא.
              sizeDelegateProvider: const PdfViewerSizeDelegateProviderSmart(
                maxScale: 20,
                smartMaxScale: 20,
                maxPagesVisible: 1,
              ),
              onViewerReady: _onReady,
              onPageChanged: _onPageChanged,
              margin: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// קפיצה לעמוד במקלדת מספרים ענקית.
class LvGotoPageScreen extends StatefulWidget {
  const LvGotoPageScreen({
    super.key,
    required this.pageCount,
    required this.current,
  });

  final int pageCount;
  final int current;

  @override
  State<LvGotoPageScreen> createState() => _LvGotoPageScreenState();
}

class _LvGotoPageScreenState extends State<LvGotoPageScreen> {
  String _digits = '';

  void _add(String d) {
    if (_digits.length >= 5) return;
    setState(() => _digits += d);
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _go() {
    final value = int.tryParse(_digits);
    if (value == null) return;
    Navigator.of(context).pop<int>(value.clamp(1, widget.pageCount));
  }

  bool _onRawKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final char = event.character;
    if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
      _add(char);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _go();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return LvKeyScope(
      onRawKey: _onRawKey,
      actions: {LvAction.back: () => Navigator.of(context).maybePop()},
      child: LvScaffold(
        title: 'עבור לעמוד',
        onBack: () => Navigator.of(context).maybePop(),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(m.gap * 2),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(m.radius),
                border: Border.all(color: p.foreground, width: m.border * 1.5),
              ),
              child: Text(
                _digits.isEmpty
                    ? 'עמוד נוכחי ${widget.current} מתוך ${widget.pageCount}'
                    : '$_digits  /  ${widget.pageCount}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.foreground,
                  fontSize: m.title,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(height: m.gap),
            Expanded(
              child: Column(
                children: [
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ]) ...[
                    Expanded(
                      child: Row(
                        children: [
                          for (final d in row) ...[
                            Expanded(
                              child: LvButton(
                                label: d,
                                filled: false,
                                height: double.infinity,
                                onPressed: () => _add(d),
                              ),
                            ),
                            if (d != row.last) SizedBox(width: m.gap),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: m.gap),
                  ],
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: LvButton(
                            label: 'מחק',
                            icon: FluentIcons.backspace_24_filled,
                            filled: false,
                            height: double.infinity,
                            onPressed: _backspace,
                          ),
                        ),
                        SizedBox(width: m.gap),
                        Expanded(
                          child: LvButton(
                            label: '0',
                            filled: false,
                            height: double.infinity,
                            onPressed: () => _add('0'),
                          ),
                        ),
                        SizedBox(width: m.gap),
                        Expanded(
                          child: LvButton(
                            label: 'עבור',
                            icon: FluentIcons.checkmark_24_filled,
                            height: double.infinity,
                            onPressed: _digits.isEmpty ? null : _go,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
