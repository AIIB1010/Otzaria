import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// פעולה שמחווה מפעילה, עם החיווי הגדול שמופיע בביצוע.
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

/// מזהה מחוות מגע בטוחות לאדם שאינו רואה היכן הכפתורים.
///
/// עיקרון מרכזי: **כל תזוזה של אצבע מעבר ל-[_moveSlop] הופכת את המגע לגרירה**
/// ("תפיסת העמוד") ומבטלת מיד כל זיהוי של לחיצה או החזקה. לכן גרירה לכל כיוון
/// לא מפעילה בטעות "החזקה ארוכה". הווידג'ט מאזין לאירועי מגע גולמיים בלבד,
/// ולכן אינו חוסם את הגרירה, הצביטה והכפתורים של התוכן שמתחתיו.
///
/// - **לחיצה כפולה** בצד שמאל או ימין (אצבע אחת, באותו צד, ברצף מהיר).
/// - **נגיעה / לחיצה כפולה בשתי או שלוש אצבעות** (נגיעה קצרה בלי תזוזה).
/// - **החזקה ארוכה**: אצבע אחת במקום אחד, עם טבעת התקדמות. תזוזה מבטלת אותה.
/// - נגיעה בודדת באצבע אחת אינה עושה דבר (הגנה מיד ומאף).
class LvTouchZones extends StatefulWidget {
  const LvTouchZones({
    super.key,
    required this.child,
    required this.actions,
    this.holdDuration = const Duration(milliseconds: 1200),
    this.doubleTapWindow = const Duration(milliseconds: 500),
  });

  final Widget child;

  /// הפעולה לכל מחווה; מחווה ללא ערך אינה מזוהה כלל.
  final Map<LvGesture, LvZoneAction> actions;
  final Duration holdDuration;
  final Duration doubleTapWindow;

  @override
  State<LvTouchZones> createState() => _LvTouchZonesState();
}

/// נגיעה שארכה יותר מזה אינה "לחיצה".
const _maxTapDuration = Duration(milliseconds: 450);

/// תזוזה מעבר לזה (בפיקסלים לוגיים) הופכת את המגע לגרירה.
const _moveSlop = 30.0;
const _doubleTapDistance = 220.0;

/// החזקה מופיעה בטבעת רק אחרי חלק מהזמן, כדי שנגיעה רגילה לא תציג אותה.
const _ringStart = 0.3;

enum _TapKey { left, right, two, three }

class _LvTouchZonesState extends State<LvTouchZones>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onHoldStatus);

  final _pointers = <int>{};
  int _maxPointers = 0;
  bool _moved = false;
  bool _tapStillValid = false;
  Timer? _tapTimer;
  Offset _downPosition = Offset.zero;
  final _startPositions = <int, Offset>{};

  _TapKey? _pendingKey;
  Offset _pendingPosition = Offset.zero;
  Timer? _pendingTimer;

  Offset? _marker;
  Timer? _markerTimer;
  LvGesture? _flashGesture;
  Timer? _flashTimer;

  @override
  void didUpdateWidget(LvTouchZones oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holdDuration != widget.holdDuration) {
      _hold.duration = widget.holdDuration;
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    _tapTimer?.cancel();
    _pendingTimer?.cancel();
    _markerTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  bool _bound(LvGesture gesture) => widget.actions.containsKey(gesture);

  void _fire(LvGesture gesture) {
    final action = widget.actions[gesture];
    if (action == null) return;
    HapticFeedback.mediumImpact();
    _flashTimer?.cancel();
    setState(() => _flashGesture = gesture);
    _flashTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _flashGesture = null);
    });
    action.onTriggered();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_moved) {
      _moved = true; // המגע הנוכחי נצרך
      HapticFeedback.heavyImpact();
      _fire(LvGesture.hold);
    }
  }

  void _onDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _maxPointers = 0;
      _moved = false;
      _tapStillValid = true;
      _tapTimer?.cancel();
      _tapTimer = Timer(_maxTapDuration, () => _tapStillValid = false);
      _downPosition = event.localPosition;
    }
    _pointers.add(event.pointer);
    _startPositions[event.pointer] = event.localPosition;
    _maxPointers = math.max(_maxPointers, _pointers.length);
    if (_pointers.length == 1 && _bound(LvGesture.hold)) {
      _hold.forward(from: 0);
    } else {
      _hold.reset();
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (_moved) return;
    final start = _startPositions[event.pointer];
    if (start != null && (event.localPosition - start).distance > _moveSlop) {
      _moved = true;
      _hold.reset();
    }
  }

  void _onUp(PointerUpEvent event, double width) {
    _pointers.remove(event.pointer);
    _startPositions.remove(event.pointer);
    _hold.reset();
    if (_pointers.isNotEmpty) return;
    final wasTap = !_moved && _tapStillValid;
    final count = _maxPointers;
    _maxPointers = 0;
    _moved = false;
    if (wasTap) _registerTap(count, event.localPosition, width);
  }

  void _onCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _startPositions.remove(event.pointer);
    _hold.reset();
    if (_pointers.isEmpty) {
      _maxPointers = 0;
      _moved = false;
    }
  }

  void _registerTap(int count, Offset position, double width) {
    final _TapKey key;
    if (count == 1) {
      key = position.dx < width / 2 ? _TapKey.left : _TapKey.right;
    } else if (count == 2) {
      key = _TapKey.two;
    } else if (count == 3) {
      key = _TapKey.three;
    } else {
      return;
    }
    final (single, double) = switch (key) {
      _TapKey.left => (null, LvGesture.doubleTapLeft),
      _TapKey.right => (null, LvGesture.doubleTapRight),
      _TapKey.two => (LvGesture.twoFingerTap, LvGesture.twoFingerDoubleTap),
      _TapKey.three => (
        LvGesture.threeFingerTap,
        LvGesture.threeFingerDoubleTap,
      ),
    };
    final isSecond =
        _pendingKey == key &&
        (count > 1 ||
            (position - _pendingPosition).distance <= _doubleTapDistance);
    if (isSecond) {
      _clearPending();
      if (_bound(double)) _fire(double);
      return;
    }
    _clearPending();
    final singleBound = single != null && _bound(single);
    final doubleBound = _bound(double);
    if (!doubleBound) {
      if (singleBound) _fire(single);
      return;
    }
    // יש מחווה כפולה: ממתינים לנגיעה שנייה. אם אין אחת, מפעילים את הבודדת.
    _pendingKey = key;
    _pendingPosition = position;
    if (count == 1) {
      _markerTimer?.cancel();
      setState(() => _marker = position);
      _markerTimer = Timer(widget.doubleTapWindow, () {
        if (mounted) setState(() => _marker = null);
      });
    }
    _pendingTimer = Timer(widget.doubleTapWindow, () {
      _pendingKey = null;
      if (singleBound) _fire(single);
    });
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingKey = null;
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final flash = _flashGesture;
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
              if (flash != null && flash != LvGesture.hold)
                _flashOverlay(flash, width, m, p),
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
              if (_bound(LvGesture.hold))
                AnimatedBuilder(
                  animation: _hold,
                  builder: (context, _) {
                    if (_hold.value < _ringStart) {
                      return const SizedBox.shrink();
                    }
                    final size = m.unit * 2.4;
                    return Positioned(
                      left: math.max(0, _downPosition.dx - size / 2),
                      top: math.max(0, _downPosition.dy - size * 1.2),
                      child: IgnorePointer(child: _holdRing(m, p, size)),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _flashOverlay(
    LvGesture gesture,
    double width,
    LvMetrics m,
    LvPalette p,
  ) {
    final action = widget.actions[gesture];
    final isLeft = gesture == LvGesture.doubleTapLeft;
    final isRight = gesture == LvGesture.doubleTapRight;
    final pill = action == null
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
          );
    return Positioned(
      top: 0,
      bottom: 0,
      left: isRight ? width / 2 : 0,
      width: (isLeft || isRight) ? width / 2 : width,
      child: IgnorePointer(
        child: Container(
          color: p.foreground.withValues(alpha: 0.12),
          alignment: Alignment.center,
          // מתכווץ לרוחב הצד שבו נגעו, גם במסך צר.
          child: pill == null
              ? null
              : Padding(
                  padding: EdgeInsets.all(m.gap),
                  child: FittedBox(fit: BoxFit.scaleDown, child: pill),
                ),
        ),
      ),
    );
  }

  Widget _holdRing(LvMetrics m, LvPalette p, double size) {
    final label = widget.actions[LvGesture.hold]?.label ?? '';
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
          Padding(
            padding: EdgeInsets.all(size * 0.18),
            child: FittedBox(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.foreground,
                  fontSize: m.label,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
