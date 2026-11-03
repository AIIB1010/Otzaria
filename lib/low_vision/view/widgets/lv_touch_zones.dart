import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// פעולה על צד אחד של המסך, עם חיווי גדול שמופיע בביצוע.
class LvZoneAction {
  const LvZoneAction({
    required this.label,
    required this.icon,
    required this.onTriggered,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTriggered;
}

/// מחוות מגע בטוחות לאדם שאינו רואה היכן הכפתורים.
///
/// - **לחיצה כפולה** על חצי המסך (לחיצה ראשונה ושנייה ברצף, באותו צד) מפעילה
///   את הפעולה של אותו צד. נגיעה בודדת, מקרית, של יד או אף אינה עושה דבר.
/// - **החזקה ארוכה** באצבע אחת במקום אחד (עם טבעת התקדמות) מפעילה [onHoldBack].
/// - נגיעה בכמה אצבעות/כף יד בו-זמנית, או תנועה, מבטלת את כל המחוות.
///
/// הווידג'ט מאזין לאירועי מגע גולמיים בלבד ואינו חוסם גלילה או כפתורים.
class LvTouchZones extends StatefulWidget {
  const LvTouchZones({
    super.key,
    required this.child,
    this.left,
    this.right,
    this.onHoldBack,
    this.holdDuration = const Duration(milliseconds: 900),
    this.doubleTapWindow = const Duration(milliseconds: 500),
  });

  final Widget child;

  /// הפעולה בצד השמאלי / הימני של המסך (פיזית, בלי תלות בכיוון הכתיבה).
  final LvZoneAction? left;
  final LvZoneAction? right;
  final VoidCallback? onHoldBack;
  final Duration holdDuration;
  final Duration doubleTapWindow;

  @override
  State<LvTouchZones> createState() => _LvTouchZonesState();
}

enum _Side { left, right }

/// נגיעה שארכה יותר מזה אינה "לחיצה".
const _maxTapDuration = Duration(milliseconds: 450);

/// תזוזה מעבר לזה (בפיקסלים לוגיים) מבטלת את המחווה.
const _moveSlop = 70.0;
const _doubleTapDistance = 220.0;

class _LvTouchZonesState extends State<LvTouchZones>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onHoldStatus);

  final _pointers = <int>{};
  bool _invalid = false;
  Offset _downPosition = Offset.zero;
  bool _tapStillValid = false;
  Timer? _tapTimer;

  Offset _lastTapPosition = Offset.zero;
  _Side? _lastTapSide;
  Timer? _pendingTimer;

  Offset? _marker;
  Timer? _markerTimer;
  _Side? _flashSide;
  Timer? _flashTimer;

  @override
  void dispose() {
    _hold.dispose();
    _markerTimer?.cancel();
    _flashTimer?.cancel();
    _tapTimer?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  LvZoneAction? _actionFor(_Side side) =>
      side == _Side.left ? widget.left : widget.right;

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_invalid) {
      _invalid = true;
      HapticFeedback.heavyImpact();
      widget.onHoldBack?.call();
    }
  }

  void _onDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length > 1) {
      _invalid = true;
      _hold.reset();
      return;
    }
    _invalid = false;
    _downPosition = event.localPosition;
    _tapStillValid = true;
    _tapTimer?.cancel();
    _tapTimer = Timer(_maxTapDuration, () => _tapStillValid = false);
    if (widget.onHoldBack != null) _hold.forward(from: 0);
  }

  void _onMove(PointerMoveEvent event) {
    if (_invalid || _pointers.length != 1) return;
    if ((event.localPosition - _downPosition).distance > _moveSlop) {
      _invalid = true;
      _hold.reset();
    }
  }

  void _onUp(PointerUpEvent event, double width) {
    _pointers.remove(event.pointer);
    _hold.reset();
    final wasTap =
        !_invalid &&
        _tapStillValid &&
        (event.localPosition - _downPosition).distance <= _moveSlop;
    if (_pointers.isEmpty) {
      final tap = wasTap;
      if (tap) _registerTap(event.localPosition, width);
      // המחווה הבאה מתחילה נקייה.
      _invalid = false;
    }
  }

  void _onCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _hold.reset();
    if (_pointers.isEmpty) _invalid = false;
  }

  void _registerTap(Offset position, double width) {
    final side = position.dx < width / 2 ? _Side.left : _Side.right;
    final isSecond =
        _lastTapSide == side &&
        (position - _lastTapPosition).distance <= _doubleTapDistance;
    if (isSecond) {
      _lastTapSide = null;
      _pendingTimer?.cancel();
      final action = _actionFor(side);
      if (action == null) return;
      HapticFeedback.mediumImpact();
      _flashTimer?.cancel();
      setState(() => _flashSide = side);
      _flashTimer = Timer(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _flashSide = null);
      });
      action.onTriggered();
      return;
    }
    _lastTapSide = side;
    _lastTapPosition = position;
    // הנגיעה הראשונה פוקעת אם השנייה לא הגיעה בזמן.
    _pendingTimer?.cancel();
    _pendingTimer = Timer(widget.doubleTapWindow, () => _lastTapSide = null);
    // עיגול קטן מאשר שהנגיעה נקלטה, בלי לבצע כלום.
    _markerTimer?.cancel();
    setState(() => _marker = position);
    _markerTimer = Timer(widget.doubleTapWindow, () {
      if (mounted) setState(() => _marker = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: (e) => _onUp(e, width),
          onPointerCancel: _onCancel,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              if (_flashSide != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: _flashSide == _Side.left ? 0 : width / 2,
                  width: width / 2,
                  child: IgnorePointer(child: _flash(m, p)),
                ),
              if (_marker != null)
                Positioned(
                  left: _marker!.dx - m.unit * 0.4,
                  top: _marker!.dy - m.unit * 0.4,
                  child: IgnorePointer(
                    child: Container(
                      width: m.unit * 0.8,
                      height: m.unit * 0.8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: p.foreground, width: 4),
                      ),
                    ),
                  ),
                ),
              if (widget.onHoldBack != null)
                AnimatedBuilder(
                  animation: _hold,
                  builder: (context, _) {
                    if (_hold.value < 0.25) return const SizedBox.shrink();
                    final size = m.unit * 2.4;
                    return Positioned(
                      left: math.max(0, _downPosition.dx - size / 2),
                      top: math.max(0, _downPosition.dy - size * 1.2),
                      child: IgnorePointer(
                        child: _holdRing(m, p, size),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _flash(LvMetrics m, p) {
    final action = _actionFor(_flashSide!);
    return Container(
      color: p.foreground.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: action == null
          ? null
          : Container(
              padding: EdgeInsets.symmetric(
                horizontal: m.unit,
                vertical: m.gap * 2,
              ),
              decoration: BoxDecoration(
                color: p.foreground,
                borderRadius: BorderRadius.circular(m.radius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, color: p.background, size: m.iconSize),
                  SizedBox(width: m.gap),
                  Text(
                    action.label,
                    style: TextStyle(
                      color: p.background,
                      fontSize: m.title,
                      fontWeight: FontWeight.w900,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _holdRing(LvMetrics m, p, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.background, shape: BoxShape.circle),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size * 0.9,
            height: size * 0.9,
            child: CircularProgressIndicator(
              value: _hold.value,
              strokeWidth: m.border * 3,
              color: p.foreground,
              backgroundColor: p.foreground.withValues(alpha: 0.2),
            ),
          ),
          Text(
            'חזרה',
            style: TextStyle(
              color: p.foreground,
              fontSize: m.label * 0.8,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
