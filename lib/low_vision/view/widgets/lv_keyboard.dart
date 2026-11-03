import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

enum _Layout { hebrew, digits }

const _hebrewRows = [
  ['ק', 'ר', 'א', 'ט', 'ו', 'ן', 'ם', 'פ'],
  ['ש', 'ד', 'ג', 'כ', 'ע', 'י', 'ח', 'ל', 'ך', 'ף'],
  ['ז', 'ס', 'ב', 'ה', 'נ', 'מ', 'צ', 'ת', 'ץ', '״', '׳'],
];

const _digitRows = [
  ['1', '2', '3', '4', '5'],
  ['6', '7', '8', '9', '0'],
  ['-', '.', ',', '"', "'"],
];

/// מקלדת מסך ענקית: אותיות עבריות בלבד, ומקש אחד שמחליף למספרים.
class LvKeyboard extends StatefulWidget {
  const LvKeyboard({
    super.key,
    required this.onText,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  final ValueChanged<String> onText;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  @override
  State<LvKeyboard> createState() => _LvKeyboardState();
}

class _LvKeyboardState extends State<LvKeyboard> {
  _Layout _layout = _Layout.hebrew;

  List<List<String>> get _rows => switch (_layout) {
    _Layout.hebrew => _hebrewRows,
    _Layout.digits => _digitRows,
  };

  void _toggleLayout() => setState(
    () => _layout = _layout == _Layout.hebrew ? _Layout.digits : _Layout.hebrew,
  );

  String get _layoutLabel => switch (_layout) {
    _Layout.hebrew => '123',
    _Layout.digits => 'אבג',
  };

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final gap = m.gap * 0.6;
    // סדר המקשים כמו במקלדת עברית רגילה: ק משמאל ו-פ מימין, ללא היפוך.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (final row in _rows) ...[
            Expanded(
              child: Row(
                children: [
                  for (final key in row) ...[
                    Expanded(
                      child: _Key(
                        label: key,
                        onTap: () => widget.onText(key),
                      ),
                    ),
                    if (key != row.last) SizedBox(width: gap),
                  ],
                ],
              ),
            ),
            SizedBox(height: gap),
          ],
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _Key(label: _layoutLabel, onTap: _toggleLayout),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 4,
                  child: _Key(label: 'רווח', onTap: () => widget.onText(' ')),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 2,
                  child: _Key(label: 'נקה', onTap: widget.onClear),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 2,
                  child: _Key(
                    icon: FluentIcons.backspace_24_filled,
                    semantic: 'מחיקת תו',
                    onTap: widget.onBackspace,
                    onLongPress: widget.onClear,
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 3,
                  child: _Key(
                    label: 'חפש',
                    icon: FluentIcons.search_24_filled,
                    accent: true,
                    onTap: widget.onSubmit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// מקש במקלדת. בזמן לחיצה הוא הופך להפוך-צבעים מלא (שחור עם כיתוב לבן בערכה
/// הבהירה), וההדגשה נשארת גלויה לפחות [_minPressedTime] גם בנגיעה קצרה.
class _Key extends StatefulWidget {
  const _Key({
    this.label,
    this.icon,
    this.semantic,
    this.accent = false,
    required this.onTap,
    this.onLongPress,
  });

  final String? label;
  final IconData? icon;
  final String? semantic;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_Key> createState() => _KeyState();
}

const _minPressedTime = Duration(milliseconds: 160);

class _KeyState extends State<_Key> {
  bool _pressed = false;
  DateTime _pressedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _releaseTimer;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  void _press() {
    _releaseTimer?.cancel();
    _pressedAt = DateTime.now();
    setState(() => _pressed = true);
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
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final bg = _pressed
        ? p.foreground
        : widget.accent
        ? p.accent
        : p.surface;
    final fg = _pressed
        ? p.background
        : widget.accent
        ? p.onAccent
        : p.foreground;
    final label = widget.label;
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxHeight, box.maxWidth * 1.4);
        final fontSize = math.max(12.0, side * 0.52);
        return Semantics(
          button: true,
          label: widget.semantic ?? label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _press(),
            onTapUp: (_) => _release(),
            onTapCancel: _release,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            onLongPress: widget.onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(m.radius * 0.7),
                border: Border.all(color: p.foreground, width: m.border * 0.7),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null)
                          Icon(widget.icon, size: fontSize, color: fg),
                        if (widget.icon != null && label != null)
                          SizedBox(width: fontSize * 0.2),
                        if (label != null)
                          Text(
                            label,
                            style: TextStyle(
                              color: fg,
                              fontSize: label.length > 1
                                  ? fontSize * 0.85
                                  : fontSize,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
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
      },
    );
  }
}
