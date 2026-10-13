/// גלילה ומיקום של הקורא בשורות מקור; מחוץ לתצוגה (bloc, טאבים, ניווט,
/// תוספים) אין אינדקסי פריטים — רק [LineScrollController].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';

export 'package:otzaria/text_book/utils/reading_position.dart';

/// ניווט של קורא חיצוני (תוסף שמחליף את תצוגת הטקסט) — שורת מקור בלבד.
typedef ExternalLineNavigator = Future<void> Function(int line);

/// מה שהתצוגה המחוברת מספקת: הפריסה מול התוכן הנוכחי, וגובה התצוגה.
class ReadingViewportBinding {
  const ReadingViewportBinding({
    required this.segments,
    required this.viewportExtent,
  });

  final ReadingSegments? Function() segments;
  final double Function() viewportExtent;
}

class _Target {
  _Target({
    required this.line,
    this.alignment = kReadingAnchorAlignment,
    this.intraLineFraction = 0,
    this.duration = Duration.zero,
    this.curve = Curves.ease,
    this.waitForAttach = false,
  });

  _Target.anchor(ReadingAnchor anchor)
    : this(
        line: anchor.line,
        alignment: anchor.alignment,
        intraLineFraction: anchor.intraLineFraction,
      );

  final int line;
  final double alignment;
  final double intraLineFraction;
  final Duration duration;
  final Curve curve;
  bool waitForAttach;

  _Target get instant => _Target(
    line: line,
    alignment: alignment,
    intraLineFraction: intraLineFraction,
  );
}

class LineScrollController {
  LineScrollController() {
    positionsListener.itemPositions.addListener(_onItemPositions);
  }

  /// לשימוש הרשימה, פס הגלילה, [ScrollPositionReanchor] ו-ProgressiveScroll בלבד.
  @internal
  final JumpAwareItemScrollController itemController =
      JumpAwareItemScrollController();
  @internal
  final ItemPositionsListener positionsListener =
      ItemPositionsListener.create();
  @internal
  final ScrollOffsetController offsetController = ScrollOffsetController();

  final ValueNotifier<ReadingPosition?> _position = ValueNotifier(null);

  /// המיקום הנוכחי, או יעד הניווט מרגע שהתחיל ועד שנחת.
  ValueListenable<ReadingPosition?> get position => _position;

  ReadingViewportBinding? _binding;
  ExternalLineNavigator? _external;
  _Target? _pending;

  /// יעד שנחת על פריט שטרם נטען: ממתינים לטעינתו ומדייקים שוב.
  _Target? _awaitingLoad;
  ItemPosition? _awaitingItemPosition;
  int _token = 0;
  int _navigating = 0;
  ReadingSegments? _measuredSegments;
  List<ItemPosition> _measuredPositions = const [];
  bool _disposed = false;

  int get navigationGeneration => itemController.navigationGeneration;

  bool get isAttached => _external != null || _nativeReady;

  bool get hasPendingTarget => _pending != null;

  ReadingSegments? get _segments => _binding?.segments();

  bool get _nativeReady =>
      _binding != null &&
      itemController.isAttached &&
      (_segments?.isNotEmpty ?? false);

  ExternalLineNavigator? get externalNavigator => _external;

  set externalNavigator(ExternalLineNavigator? navigator) {
    _external = navigator;
    final pending = _pending;
    if (navigator != null && pending != null) {
      _pending = null;
      unawaited(navigator(pending.line));
    }
  }

  void addBeforeJumpListener(VoidCallback listener) =>
      itemController.addBeforeJumpListener(listener);

  void removeBeforeJumpListener(VoidCallback listener) =>
      itemController.removeBeforeJumpListener(listener);

  /// מחבר תצוגה. תצוגה שמתחלפת חוזרת לעוגן האחרון, אלא אם ממתין ניווט.
  void attach(ReadingViewportBinding binding) {
    _binding = binding;
    final pending = _pending;
    if (pending != null) {
      pending.waitForAttach = false;
    } else if (_measuredSegments != null) {
      final anchor = _anchorFrom(_measuredSegments!, _measuredPositions);
      if (anchor != null) _pending = _Target.anchor(anchor);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushPending());
  }

  void detach(ReadingViewportBinding binding) {
    if (identical(_binding, binding)) _binding = null;
  }

  /// גלילה לשורת המקור [line]. בלי תצוגה מחוברת היעד נשמר ומבוצע בחיבור.
  Future<void> scrollToLine(
    int line, {
    double alignment = kReadingAnchorAlignment,
    double intraLineFraction = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.ease,
  }) {
    final segments = _segments;
    final target = _Target(
      line: segments == null || segments.isEmpty
          ? (line < 0 ? 0 : line)
          : line.clamp(0, segments.layout.lineCount - 1).toInt(),
      alignment: alignment,
      intraLineFraction: intraLineFraction,
      duration: duration,
      curve: curve,
    );
    _awaitingLoad = null;
    _publish(
      ReadingPosition.target(
        target.line,
        intraLineFraction: intraLineFraction,
      ),
    );
    final external = _external;
    if (external != null) {
      _pending = null;
      _token++;
      itemController
        ..notifyBeforeJump()
        ..beginNavigation();
      return external(target.line);
    }
    if (!_nativeReady) {
      _token++;
      _pending = target;
      return Future.value();
    }
    _pending = null;
    return _run(target);
  }

  Future<void> jumpToLine(
    int line, {
    double alignment = kReadingAnchorAlignment,
    double intraLineFraction = 0,
  }) => scrollToLine(
    line,
    alignment: alignment,
    intraLineFraction: intraLineFraction,
    duration: Duration.zero,
  );

  /// היעד יבוצע רק בתצוגה הבאה שתתחבר — למשל ביציאה מצורת הדף.
  void scrollToLineOnNextAttach(int line) {
    _awaitingLoad = null;
    _token++;
    _publish(ReadingPosition.target(line));
    _pending = _Target(line: line, waitForAttach: true);
  }

  /// מיקום שדווח מקורא חיצוני.
  void reportExternalLine(int line) {
    if (line < 0) return;
    _publish(ReadingPosition.target(line));
  }

  /// הנקודה שעל קו העוגן עכשיו.
  ReadingAnchor? captureAnchor() {
    final segments = _segments;
    if (segments == null || _external != null) {
      final current = _position.value;
      return current == null
          ? null
          : ReadingAnchor(
              line: current.topLine,
              intraLineFraction: current.intraLineFraction,
            );
    }
    return _anchorFrom(segments, positionsListener.itemPositions.value);
  }

  Future<void> restoreAnchor(ReadingAnchor anchor) {
    if (!_nativeReady) {
      _token++;
      _pending = _Target.anchor(anchor);
      return Future.value();
    }
    _pending = null;
    return _run(_Target.anchor(anchor));
  }

  /// לפני שינוי רוחב: קובע את הרשימה על הפריט העליון, ואחרי הפריסה מחזיר את
  /// השורה המדויקת לקו העוגן.
  void keepViewAcrossRelayout() {
    if (!_nativeReady) return;
    final anchor = captureAnchor();
    if (anchor == null) return;
    final top = reanchorTargetPosition(positionsListener.itemPositions.value);
    if (top != null) {
      itemController.jumpTo(index: top.index, alignment: top.itemLeadingEdge);
    }
    final token = ++_token;
    _navigating++;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      _navigating--;
      if (token != _token || _disposed) return;
      await _run(_Target.anchor(anchor));
    });
  }

  ReadingAnchor? _anchorFrom(
    ReadingSegments segments,
    Iterable<ItemPosition> positions,
  ) => readingAnchorFromItems(segments, positions);

  void _publish(ReadingPosition position) {
    if (_disposed || _position.value == position) return;
    _position.value = position;
  }

  void _flushPending() {
    final pending = _pending;
    if (_disposed || pending == null || pending.waitForAttach) return;
    if (!_nativeReady) return;
    _pending = null;
    unawaited(_run(pending));
  }

  Future<void> _run(_Target target) async {
    final binding = _binding;
    final segments = _segments;
    if (binding == null || segments == null || segments.isEmpty) return;
    final token = ++_token;
    _navigating++;
    try {
      await scrollToSourceLine(
        scrollController: itemController,
        scrollOffsetController: offsetController,
        positionsListener: positionsListener,
        segments: segments,
        latestSegments: () => _segments ?? segments,
        lineIndex: target.line,
        viewportExtent: binding.viewportExtent(),
        alignment: target.alignment,
        intraLineFraction: target.intraLineFraction,
        duration: target.duration,
        curve: target.curve,
        isCurrent: () => token == _token && !_disposed,
      );
    } finally {
      _navigating--;
    }
    if (token != _token || _disposed) return;
    final landed = _segments;
    if (landed != null && landed.isNotEmpty) {
      final item = landed.layout.itemForLine(target.line);
      if (!landed[item].isLoaded) {
        _awaitingLoad = target.instant;
        _awaitingItemPosition = _positionOf(item);
        return;
      }
    }
    _measure(landed: target);
  }

  ItemPosition? _positionOf(int item) => positionsListener.itemPositions.value
      .where((p) => p.index == item)
      .firstOrNull;

  void _onItemPositions() {
    if (_disposed || _external != null) return;
    final segments = _segments;
    if (segments == null || segments.isEmpty) return;
    final previousSegments = _measuredSegments;

    if (_pending != null) {
      _flushPending();
      return;
    }
    if (_navigating > 0) return;

    final awaiting = _awaitingLoad;
    if (awaiting != null) {
      _onPositionsWhileAwaitingLoad(awaiting, segments, previousSegments);
      return;
    }

    if (previousSegments != null && !identical(previousSegments, segments)) {
      final anchor = _anchorFrom(previousSegments, _measuredPositions);
      if (anchor != null &&
          _relayoutMovesAnchor(previousSegments, segments, anchor)) {
        // לא מודדים: המיקום שנמדד לפני השינוי הוא שנשמר.
        _measuredSegments = segments;
        unawaited(_run(_Target.anchor(anchor)));
        return;
      }
    }
    _measure();
  }

  /// פריסה חדשה (החלפת מצב רציף), או טעינה של שורה עד העוגן שהזיזה אותו.
  /// טעינה מתחת לעוגן אינה מזיזה אותו, ולכן גלילה שוטפת אינה נקטעת.
  bool _relayoutMovesAnchor(
    ReadingSegments before,
    ReadingSegments after,
    ReadingAnchor anchor,
  ) {
    if (!before.layout.hasSameStructure(after.layout)) return true;
    if (!_loadedChangedUpTo(before, after, anchor.line)) return false;
    final item = after.layout.itemForLine(anchor.line);
    final itemPosition = _positionOf(item);
    final extent = _binding?.viewportExtent() ?? 0;
    if (itemPosition == null || extent <= 0) return true;
    final edges = lineEdgesInViewport(after[item], anchor.line, itemPosition);
    final edge =
        edges.leading +
        anchor.intraLineFraction * (edges.trailing - edges.leading);
    return ((edge - anchor.alignment) * extent).abs() > 0.5;
  }

  static bool _loadedChangedUpTo(
    ReadingSegments before,
    ReadingSegments after,
    int line,
  ) {
    final a = before.loadedLineFlags;
    final b = after.loadedLineFlags;
    if (identical(a, b)) return false;
    bool loaded(List<bool>? flags, int i) =>
        flags == null || (i < flags.length && flags[i]);
    for (var i = 0; i <= line; i++) {
      if (loaded(a, i) != loaded(b, i)) return true;
    }
    return false;
  }

  void _onPositionsWhileAwaitingLoad(
    _Target awaiting,
    ReadingSegments segments,
    ReadingSegments? previousSegments,
  ) {
    final item = segments.layout.itemForLine(awaiting.line);
    if (segments[item].isLoaded) {
      _awaitingLoad = null;
      _measuredSegments = segments;
      unawaited(_run(awaiting));
      return;
    }
    final now = _positionOf(item);
    final before = _awaitingItemPosition;
    _awaitingItemPosition = now;
    // תזוזה בלי שינוי תוכן היא גלילה של המשתמש — מוותרים על הדיוק.
    final contentChanged =
        previousSegments != null && !identical(previousSegments, segments);
    final moved =
        before == null ||
        now == null ||
        (now.itemLeadingEdge - before.itemLeadingEdge).abs() > 0.0005;
    _measuredSegments = segments;
    if (moved && !contentChanged) {
      _awaitingLoad = null;
      _measure();
    }
  }

  /// [landed] הוא יעד שהניווט הסתיים בו. בראש הספר הוא נעצר מעל קו העוגן כי אין
  /// לאן לגלול, ובכל זאת הוא המיקום — אחרת "הבא" היה נתקע בשורה 0.
  void _measure({_Target? landed}) {
    final segments = _segments;
    if (segments == null || segments.isEmpty) return;
    final positions = positionsListener.itemPositions.value.toList();
    _measuredSegments = segments;
    _measuredPositions = positions;
    var position = readingPositionFromItems(segments, positions);
    if (position == null) return;
    if (landed != null &&
        position.topLine < landed.line &&
        _restsAtOrAbove(segments, landed)) {
      position = ReadingPosition(
        topLine: landed.line,
        intraLineFraction: landed.intraLineFraction,
        visibleLines: List<int>.unmodifiable(
          position.visibleLines.where((line) => line >= landed.line),
        ),
        windowFirstLine: position.windowFirstLine,
        windowLastLine: position.windowLastLine,
      );
    }
    _publish(position);
  }

  bool _restsAtOrAbove(ReadingSegments segments, _Target target) {
    final top = _positionOf(0);
    if (top == null || top.itemLeadingEdge < 0) return false;
    final item = segments.layout.itemForLine(target.line);
    final itemPosition = _positionOf(item);
    if (itemPosition == null) return false;
    final edges = lineEdgesInViewport(
      segments[item],
      target.line,
      itemPosition,
    );
    return edges.leading >= 0 &&
        edges.leading <= target.alignment + kAnchorLandingEpsilon;
  }

  void dispose() {
    _disposed = true;
    positionsListener.itemPositions.removeListener(_onItemPositions);
  }
}

/// מספק את [LineScrollController] של הקורא למי שאין לו גישה לטאב.
class LineScrollScope extends InheritedWidget {
  const LineScrollScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final LineScrollController controller;

  static LineScrollController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LineScrollScope>()?.controller;

  @override
  bool updateShouldNotify(LineScrollScope oldWidget) =>
      !identical(oldWidget.controller, controller);
}
