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
    return Column(
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
                flex: 4,
                child: _Key(
                  label: 'רווח',
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
    );
  }
}

class _Key extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final bg = accent ? p.accent : p.surface;
    final fg = accent ? p.onAccent : p.foreground;
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxHeight, box.maxWidth * 1.4);
        final fontSize = math.max(12.0, side * 0.52);
        return Semantics(
          button: true,
          label: semantic ?? label,
          excludeSemantics: true,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(m.radius * 0.7),
              side: BorderSide(color: p.foreground, width: m.border * 0.7),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(m.radius * 0.7),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              onLongPress: onLongPress,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) Icon(icon, size: fontSize, color: fg),
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
            ),
          ),
        );
      },
    );
  }
}
