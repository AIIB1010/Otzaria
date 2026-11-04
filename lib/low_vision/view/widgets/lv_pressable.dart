import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';

/// נגיעה סלחנית לאדם שלוחץ חזק או שהאצבע שלו זזה מעט.
///
/// ב-Flutter הרגיל נגיעה מתבטלת אם האצבע זזה יותר מ-18 פיקסלים (כ-3 מ"מ במסך
/// 16"), ובתוך רשימה גם גרירה קלה מתחילה גלילה ומבטלת אותה. לכן כאן הנגיעה
/// מזוהה לפי אירועי מגע גולמיים: היא מופעלת בהרמת האצבע כל עוד האצבע זזה פחות
/// מהסף שבהגדרות ("רגישות נגיעה"), גם אם נמשכה זמן רב, וגם אם הגלילה זזה מעט.
/// בגרירה אמיתית (מעבר לסף) או בנגיעה בשתי אצבעות היא מתבטלת.
///
/// [activateOnDown]: מפעיל ברגע הנגיעה (למקשי מקלדת).
class LvPressable extends StatefulWidget {
  const LvPressable({
    super.key,
    required this.builder,
    required this.onTap,
    this.onLongPress,
    this.activateOnDown = false,
  });

  final Widget Function(BuildContext context, bool pressed) builder;

  /// null = כבוי.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool activateOnDown;

  @override
  State<LvPressable> createState() => _LvPressableState();
}

/// ההדגשה נשארת גלויה לפחות כך, גם בנגיעה קצרה מאוד.
const _minPressedTime = Duration(milliseconds: 160);
const _longPressTime = Duration(milliseconds: 600);
const _scrollCancelDistance = 8.0;

class _LvPressableState extends State<LvPressable> {
  int? _pointer;
  Offset _downPosition = Offset.zero;
  double _slop = 45;
  double? _scrollAtDown;
  bool _cancelled = false;
  bool _fired = false;
  bool _pressed = false;
  DateTime _pressedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _releaseTimer;
  Timer? _longPressTimer;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  double? _scrollPixels() {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.position.hasPixels) return null;
    return scrollable.position.pixels;
  }

  void _onDown(PointerDownEvent event) {
    if (widget.onTap == null) return;
    if (_pointer != null) {
      // אצבע שנייה: כף יד או גרירה בשתי אצבעות, לא נגיעה.
      _cancel();
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _slop = BlocProvider.of<LowVisionCubit>(context).state.tapSlop;
    _scrollAtDown = _scrollPixels();
    _cancelled = false;
    _fired = false;
    _releaseTimer?.cancel();
    _pressedAt = DateTime.now();
    setState(() => _pressed = true);
    if (widget.activateOnDown) {
      _fired = true;
      widget.onTap?.call();
    } else if (widget.onLongPress != null) {
      _longPressTimer = Timer(_longPressTime, () {
        if (_cancelled || _fired) return;
        _fired = true;
        widget.onLongPress?.call();
      });
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled) return;
    if ((event.position - _downPosition).distance > _slop) _cancel();
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _longPressTimer?.cancel();
    final scrolled = _scrollAtDown != null && _scrollPixels() != null
        ? ((_scrollPixels()! - _scrollAtDown!).abs() > _scrollCancelDistance)
        : false;
    final shouldFire =
        !_cancelled &&
        !_fired &&
        !scrolled &&
        (event.position - _downPosition).distance <= _slop;
    _release();
    if (shouldFire) widget.onTap?.call();
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _cancel();
  }

  void _cancel() {
    _cancelled = true;
    _longPressTimer?.cancel();
    _release();
  }

  void _release() {
    final remaining = _minPressedTime - DateTime.now().difference(_pressedAt);
    _releaseTimer?.cancel();
    if (remaining <= Duration.zero) {
      if (mounted) setState(() => _pressed = false);
      return;
    }
    _releaseTimer = Timer(remaining, () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.builder(context, _pressed),
    );
  }
}
