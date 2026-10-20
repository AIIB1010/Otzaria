import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

ItemPosition? _firstStartingInView(Iterable<ItemPosition> positions) {
  ItemPosition? best;
  for (final position in positions) {
    if (position.itemLeadingEdge < 0 || position.itemLeadingEdge > 1) continue;
    if (best == null || position.itemLeadingEdge < best.itemLeadingEdge) {
      best = position;
    }
  }
  return best;
}

/// כשרוחב התצוגה משתנה, מחזיר את הפסקה הנבחרת לגובה שבו הייתה, כדי שפתיחת
/// חלונית לא תדחוף אותה מהמסך כשהפסקאות שמעליה מתארכות. בלי פסקה נבחרת
/// הרשימה עצמה שומרת את הפריט שבראש התצוגה.
class ScrollPositionReanchor extends StatefulWidget {
  const ScrollPositionReanchor({
    super.key,
    required this.scrollController,
    required this.positionsListener,
    required this.child,
    this.enabled = true,
    this.preferredIndex,
    this.layoutKey,
  });

  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final bool enabled;
  final int? preferredIndex;

  /// שינוי שלו (למשל מרווח השורות) משנה את גובה הפריטים כמו שינוי רוחב.
  final Object? layoutKey;
  final Widget child;

  @override
  State<ScrollPositionReanchor> createState() => _ScrollPositionReanchorState();
}

class _ScrollPositionReanchorState extends State<ScrollPositionReanchor> {
  (double, Object?)? _lastLayout;
  double? _selectedEdge;
  bool _holdSelectedEdge = false;
  ScrollableState? _scrollable;
  double _pixels = 0;

  bool get _isScrolling =>
      _scrollable?.mounted == true &&
      _scrollable!.position.isScrollingNotifier.value;

  @override
  void initState() {
    super.initState();
    widget.positionsListener.itemPositions.addListener(_onPositions);
  }

  @override
  void didUpdateWidget(covariant ScrollPositionReanchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final listenerChanged =
        widget.positionsListener != oldWidget.positionsListener;
    if (listenerChanged) {
      _scrollable = null;
      oldWidget.positionsListener.itemPositions.removeListener(_onPositions);
      widget.positionsListener.itemPositions.addListener(_onPositions);
    }
    if (listenerChanged || widget.preferredIndex != oldWidget.preferredIndex) {
      _trackSelected();
    }
  }

  @override
  void dispose() {
    widget.positionsListener.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  // בזמן גלילה המיקומים כוללים גם את הסחיפה של שינוי הרוחב; היסט הגלילה
  // לבדו מזיז אז את הפסקה.
  void _onPositions() {
    if (!_holdSelectedEdge && !_isScrolling) _trackSelected();
  }

  void _trackSelected() {
    final index = widget.preferredIndex;
    _selectedEdge = index == null
        ? null
        : widget.positionsListener.itemPositions.value
              .where((p) => p.index == index)
              .map((p) => p.itemLeadingEdge)
              .where((edge) => edge >= 0 && edge <= 1)
              .firstOrNull;
  }

  /// נקרא לפני שהרשימה נפרסת ברוחב החדש, ולכן [_selectedEdge] עדיין מהרוחב
  /// הקודם.
  void _onLayout(double width) {
    final previous = _lastLayout;
    final layout = (width, widget.layoutKey);
    _lastLayout = layout;
    if (previous == null || previous == layout || !widget.enabled) return;
    if (_isScrolling) return;
    // בלי פסקה נבחרת במסך: הפריט הראשון שתחילתו במסך. הרשימה לבדה שומרת את
    // החלק שנגלל מהפריט העליון, וכרטיס מקונן בו אינו נמתח עם הטקסט.
    final selectedEdge = _selectedEdge;
    final top = selectedEdge == null
        ? _firstStartingInView(widget.positionsListener.itemPositions.value)
        : null;
    final index = selectedEdge == null ? top?.index : widget.preferredIndex;
    final edge = selectedEdge ?? top?.itemLeadingEdge;
    if (index == null || edge == null) return;
    // גם גלגלת שהסתיימה באותו פריים מבטלת את העיגון המתוזמן.
    final pixels = _pixels;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.scrollController.isAttached ||
          _isScrolling ||
          _pixels != pixels) {
        return;
      }
      widget.scrollController.jumpTo(index: index, alignment: edge);
      if (index != widget.preferredIndex) return;
      // מדידת הרשימה באותו פריים היא של הפריסה שלפני הקפיצה; בלי ההשהיה
      // אנימציית רוחב מקפיצה את הפסקה בכל פריים בין שני גבהים.
      _selectedEdge = edge;
      _holdSelectedEdge = true;
      SchedulerBinding.instance.scheduleFrameCallback(
        (_) => _holdSelectedEdge = false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _onLayout(constraints.maxWidth);
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        );
      },
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    if (notification.context != null) {
      _scrollable = Scrollable.maybeOf(notification.context!);
    }
    final edge = _selectedEdge;
    if (edge != null && notification is ScrollUpdateNotification) {
      final moved =
          edge - (notification.scrollDelta ?? 0) / metrics.viewportDimension;
      _selectedEdge = moved >= 0 && moved <= 1 ? moved : null;
    }
    _pixels = metrics.pixels;
    return false;
  }
}
