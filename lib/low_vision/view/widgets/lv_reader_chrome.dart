import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart' show bookIdentity;
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/view/lv_books_screen.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_search_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_touch_zones.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

/// כפתור נוסף בסרגל העליון של הקורא.
class LvChromeAction {
  const LvChromeAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// מסגרת משותפת לקורא טקסט ולקורא PDF: סרגל עליון עם "חזרה" ענקי, סרגל
/// תחתון עם דפדוף, הגדלה ותוכן עניינים, וכל קיצורי המקלדת.
class LvReaderChrome extends StatefulWidget {
  const LvReaderChrome({
    super.key,
    required this.book,
    required this.child,
    required this.progress,
    required this.onNext,
    required this.onPrevious,
    required this.onZoomIn,
    required this.onZoomOut,
    this.onScrollUp,
    this.onScrollDown,
    this.sectionLabel,
    this.onFirst,
    this.onLast,
    this.onNextSection,
    this.onPreviousSection,
    this.onContents,
    this.contentsLabel = 'תוכן',
    this.contentsIcon = FluentIcons.text_bullet_list_24_filled,
    this.extraActions = const [],
  });

  final Book book;
  final Widget child;

  /// "42%" או "עמוד 5 מתוך 80".
  final String progress;

  /// שם הסעיף הנוכחי; מוצג מתחת לסרגל העליון.
  final String? sectionLabel;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  /// גלילה קטנה (חוגה פיזית). אם חסר, החוגה אינה פעילה במסך הזה.
  final VoidCallback? onScrollUp;
  final VoidCallback? onScrollDown;
  final VoidCallback? onFirst;
  final VoidCallback? onLast;
  final VoidCallback? onNextSection;
  final VoidCallback? onPreviousSection;
  final VoidCallback? onContents;
  final String contentsLabel;
  final IconData contentsIcon;

  /// כפתורים נוספים בסרגל העליון (למשל מעבר בין טקסט, צורת הדף וצילום).
  final List<LvChromeAction> extraActions;

  @override
  State<LvReaderChrome> createState() => _LvReaderChromeState();
}

class _LvReaderChromeState extends State<LvReaderChrome> {
  bool _immersive = false;
  String? _toast;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  /// חיווי גדול ובולט לרגע, למשל "גודל הטקסט: 120%".
  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _toggleImmersive() => setState(() => _immersive = !_immersive);

  void _switchBook(int delta) {
    final cubit = context.read<LowVisionCubit>();
    final books = cubit.openBooks;
    if (books.length < 2) return;
    final id = bookIdentity(widget.book);
    final index = books.indexWhere((b) => bookIdentity(b) == id);
    final target = books[((index < 0 ? 0 : index) + delta) % books.length];
    lvOpenBook(context, target, replace: true);
  }

  VoidCallback? _callbackFor(LvTouchAction action) => switch (action) {
    LvTouchAction.none => null,
    LvTouchAction.nextPage => widget.onNext,
    LvTouchAction.previousPage => widget.onPrevious,
    LvTouchAction.back => () => Navigator.of(context).maybePop(),
    LvTouchAction.zoomIn => widget.onZoomIn,
    LvTouchAction.zoomOut => widget.onZoomOut,
    LvTouchAction.contents => widget.onContents,
    LvTouchAction.nextSection => widget.onNextSection,
    LvTouchAction.previousSection => widget.onPreviousSection,
    LvTouchAction.firstPage => widget.onFirst,
    LvTouchAction.lastPage => widget.onLast,
    LvTouchAction.fullscreen => _toggleImmersive,
    LvTouchAction.colors => context.read<LowVisionCubit>().cyclePalette,
    LvTouchAction.home => _goHome,
  };

  /// מחוות מגע ← פעולות, לפי ההגדרות. פעולה שאין לה יעד (למשל תוכן עניינים
  /// בספר בלי תוכן) אינה מזוהה.
  Map<LvGesture, LvZoneAction> _zoneActions(LowVisionState state) {
    final result = <LvGesture, LvZoneAction>{};
    for (final gesture in LvGesture.values) {
      final action = state.actionFor(gesture);
      final callback = _callbackFor(action);
      if (callback == null) continue;
      result[gesture] = LvZoneAction(
        label: action.label,
        icon: action.icon,
        onTriggered: callback,
      );
    }
    return result;
  }

  void _goHome() => Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final cubit = context.read<LowVisionCubit>();
    final pinned = context.select(
      (LowVisionCubit c) => c.isPinned(widget.book),
    );
    final touchState = context.watch<LowVisionCubit>().state;
    final actions = <LvAction, VoidCallback>{
      LvAction.back: () => Navigator.of(context).maybePop(),
      LvAction.home: _goHome,
      LvAction.next: widget.onNext,
      LvAction.previous: widget.onPrevious,
      LvAction.down: widget.onNext,
      LvAction.up: widget.onPrevious,
      if (widget.onScrollUp != null) LvAction.scrollUp: widget.onScrollUp!,
      if (widget.onScrollDown != null)
        LvAction.scrollDown: widget.onScrollDown!,
      LvAction.zoomIn: widget.onZoomIn,
      LvAction.zoomOut: widget.onZoomOut,
      LvAction.contrast: cubit.cyclePalette,
      LvAction.togglePin: () => cubit.togglePin(widget.book),
      LvAction.previousBook: () => _switchBook(-1),
      LvAction.nextBook: () => _switchBook(1),
      LvAction.openBooks: () => lvPush<void>(context, const LvBooksScreen()),
      LvAction.openSearch: () => lvPush<void>(context, const LvSearchScreen()),
      if (widget.onFirst != null) LvAction.first: widget.onFirst!,
      if (widget.onLast != null) LvAction.last: widget.onLast!,
      if (widget.onNextSection != null)
        LvAction.nextSection: widget.onNextSection!,
      if (widget.onPreviousSection != null)
        LvAction.previousSection: widget.onPreviousSection!,
      if (widget.onContents != null) LvAction.contents: widget.onContents!,
      LvAction.select: _toggleImmersive,
    };
    return LvKeyScope(
      actions: actions,
      child: BlocListener<LowVisionCubit, LowVisionState>(
        listenWhen: (a, b) => a.textScale != b.textScale,
        listener: (context, state) =>
            _showToast('גודל הטקסט: ${(state.textScale * 100).round()}%'),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Material(
            color: p.background,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(m.gap),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        if (!_immersive) ...[
                          _topBar(m, p, pinned, cubit),
                          SizedBox(height: m.gap),
                        ],
                        Expanded(
                          child: LvTouchZones(
                            // מחוות המגע ניתנות לשיוך בהגדרות. גרירה באצבע אחת
                            // תמיד מזיזה את התוכן, ולכן אינה מפעילה פעולה.
                            actions: _zoneActions(touchState),
                            holdDuration: Duration(
                              milliseconds: (touchState.holdSeconds * 1000)
                                  .round(),
                            ),
                            child: ClipRect(child: widget.child),
                          ),
                        ),
                        if (!_immersive) ...[
                          SizedBox(height: m.gap),
                          _bottomBar(m),
                        ],
                      ],
                    ),
                    if (_toast != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: m.unit,
                                vertical: m.gap * 2,
                              ),
                              decoration: BoxDecoration(
                                color: p.foreground,
                                borderRadius: BorderRadius.circular(m.radius),
                              ),
                              child: Text(
                                _toast!,
                                style: TextStyle(
                                  color: p.background,
                                  fontSize: m.title,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_immersive)
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: LvButton(
                          label: 'תפריט',
                          icon: FluentIcons.re_order_dots_horizontal_24_filled,
                          onPressed: _toggleImmersive,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(LvMetrics m, LvPalette p, bool pinned, LowVisionCubit cubit) {
    final section = widget.sectionLabel;
    return SizedBox(
      height: m.unit * 1.4,
      child: Row(
        children: [
          LvButton(
            label: 'חזרה',
            icon: FluentIcons.arrow_left_24_filled,
            directionalIcon: true,
            onPressed: () => Navigator.of(context).maybePop(),
            height: double.infinity,
          ),
          SizedBox(width: m.gap * 1.5),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.book.title,
                      maxLines: 1,
                      style: TextStyle(
                        color: p.foreground,
                        fontSize: m.body,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                if (section != null && section.isNotEmpty)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        section,
                        maxLines: 1,
                        style: TextStyle(
                          color: p.foreground,
                          fontSize: m.label * 0.85,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: m.gap),
          if (m.isWide)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.progress,
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: m.label,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          SizedBox(width: m.gap),
          for (final extra in widget.extraActions) ...[
            LvButton(
              label: extra.label,
              icon: extra.icon,
              iconOnly: !m.isWide,
              height: double.infinity,
              onPressed: extra.onPressed,
            ),
            SizedBox(width: m.gap),
          ],
          LvButton(
            label: pinned ? 'קבוע' : 'קבע',
            icon: pinned
                ? FluentIcons.pin_24_filled
                : FluentIcons.pin_24_regular,
            iconOnly: !m.isWide,
            filled: pinned,
            height: double.infinity,
            onPressed: () => cubit.togglePin(widget.book),
          ),
          SizedBox(width: m.gap),
          LvButton(
            label: 'צבעים',
            icon: FluentIcons.color_24_filled,
            iconOnly: !m.isWide,
            filled: false,
            height: double.infinity,
            onPressed: cubit.cyclePalette,
          ),
          SizedBox(width: m.gap),
          LvButton(
            label: 'מסך מלא',
            icon: FluentIcons.full_screen_maximize_24_filled,
            iconOnly: true,
            filled: false,
            height: double.infinity,
            onPressed: _toggleImmersive,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(LvMetrics m) {
    final hasSections = widget.onNextSection != null;
    Widget slot(int flex, Widget child) => Expanded(flex: flex, child: child);
    final gap = SizedBox(width: m.gap);
    return SizedBox(
      height: m.unit * 1.3,
      child: Row(
        children: [
          slot(
            3,
            LvButton(
              label: 'עמוד',
              icon: FluentIcons.arrow_up_24_filled,
              onPressed: widget.onPrevious,
              height: double.infinity,
            ),
          ),
          if (hasSections) ...[
            gap,
            slot(
              3,
              LvButton(
                label: 'סעיף',
                icon: FluentIcons.arrow_previous_24_regular,
                iconOnly: !m.isWide,
                directionalIcon: true,
                filled: false,
                onPressed: widget.onPreviousSection,
                height: double.infinity,
              ),
            ),
          ],
          if (widget.onContents != null) ...[
            gap,
            slot(
              3,
              LvButton(
                label: widget.contentsLabel,
                icon: widget.contentsIcon,
                iconOnly: !m.isWide,
                filled: false,
                onPressed: widget.onContents,
                height: double.infinity,
              ),
            ),
          ],
          gap,
          slot(
            2,
            LvButton(
              label: 'הקטן',
              icon: FluentIcons.subtract_24_filled,
              iconOnly: true,
              filled: false,
              onPressed: widget.onZoomOut,
              height: double.infinity,
            ),
          ),
          gap,
          slot(
            2,
            LvButton(
              label: 'הגדל',
              icon: FluentIcons.add_24_filled,
              iconOnly: true,
              filled: false,
              onPressed: widget.onZoomIn,
              height: double.infinity,
            ),
          ),
          if (hasSections) ...[
            gap,
            slot(
              3,
              LvButton(
                label: 'סעיף',
                icon: FluentIcons.arrow_next_24_regular,
                iconOnly: !m.isWide,
                directionalIcon: true,
                filled: false,
                onPressed: widget.onNextSection,
                height: double.infinity,
              ),
            ),
          ],
          gap,
          slot(
            3,
            LvButton(
              label: 'עמוד',
              icon: FluentIcons.arrow_down_24_filled,
              onPressed: widget.onNext,
              height: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}
