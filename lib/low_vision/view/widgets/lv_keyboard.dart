import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/widgets/lv_pressable.dart';
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
    this.onBack,
  });

  final ValueChanged<String> onText;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  /// כשהוא מוגדר, מקש "חזרה" מחליף את מקש "חפש" (החיפוש ממילא חי).
  final VoidCallback? onBack;

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
                        typing: true,
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
                  child: _Key(
                    label: 'רווח',
                    typing: true,
                    onTap: () => widget.onText(' '),
                  ),
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
                  child: widget.onBack != null
                      ? _Key(
                          label: 'חזרה',
                          // המקלדת עצמה LTR, והחזרה בעברית היא לימין.
                          icon: FluentIcons.arrow_right_24_filled,
                          accent: true,
                          onTap: widget.onBack!,
                        )
                      : _Key(
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

/// מקש במקלדת. בזמן נגיעה הוא הופך לשחור מלא עם כיתוב לבן (הפוך בערכות
/// כהות). אות נכנסת ברגע הנגיעה כשההגדרה "הקלדה בנגיעה" פעילה.
class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    this.semantic,
    this.accent = false,
    required this.onTap,
    this.onLongPress,
    this.typing = false,
  });

  final String? label;
  final IconData? icon;
  final String? semantic;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// מקש שמכניס טקסט (אות, רווח): מופעל ברגע הנגיעה לפי ההגדרה.
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final onDown =
        typing && context.select((LowVisionCubit c) => c.state.keysOnTouchDown);
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxHeight, box.maxWidth * 1.4);
        final fontSize = math.max(12.0, side * 0.52);
        return Semantics(
          button: true,
          label: semantic ?? label,
          onTap: onTap,
          excludeSemantics: true,
          child: LvPressable(
            activateOnDown: onDown,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            onLongPress: onLongPress,
            builder: (context, pressed) {
              final bg = pressed
                  ? p.foreground
                  : accent
                  ? p.accent
                  : p.surface;
              final fg = pressed
                  ? p.background
                  : accent
                  ? p.onAccent
                  : p.foreground;
              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(m.radius * 0.7),
                  border: Border.all(
                    color: p.foreground,
                    width: m.border * 0.7,
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null)
                            Icon(icon, size: fontSize, color: fg),
                          if (icon != null && label != null)
                            SizedBox(width: fontSize * 0.2),
                          if (label != null)
                            Text(
                              label!,
                              style: TextStyle(
                                color: fg,
                                fontSize: label!.length > 1
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
              );
            },
          ),
        );
      },
    );
  }
}
