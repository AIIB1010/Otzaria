import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/view/widgets/lv_pressable.dart';
import 'package:otzaria/low_vision/view/widgets/lv_touch_zones.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// הערכה הנוכחית; בונה מחדש את הווידג'ט כשהמשתמש מחליף צבעים.
LvPalette lvPaletteOf(BuildContext context) =>
    context.select((LowVisionCubit c) => c.state.palette);

/// כפתור ענק: אייקון גדול ותווית, בניגודיות מלאה.
class LvButton extends StatelessWidget {
  const LvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.directionalIcon = false,
    this.filled = true,
    this.height,
    this.selected = false,
    this.iconOnly = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// האייקון כיווני (חץ) ולכן עובר דרך [RtlIcon].
  final bool directionalIcon;
  final bool filled;
  final double? height;

  /// מסומן כפריט הנבחר במקלדת.
  final bool selected;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final enabled = onPressed != null;
    final iconSize = m.iconSize;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: LvPressable(
          onTap: onPressed,
          builder: (context, pressed) {
            // בלחיצה הצבעים מתהפכים, כדי שיהיה ברור שהנגיעה נקלטה.
            final bg = pressed
                ? (filled ? p.background : p.foreground)
                : (filled ? p.accent : p.background);
            final fg = pressed
                ? (filled ? p.foreground : p.background)
                : (filled ? p.onAccent : p.foreground);
            return Container(
              constraints: BoxConstraints(
                minHeight: height ?? m.tapHeight,
                minWidth: m.tapHeight,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: m.gap * 1.5,
                vertical: m.gap,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(m.radius),
                border: Border.all(
                  color: selected || pressed ? p.foreground : p.accent,
                  width: selected ? m.border * 2.5 : m.border,
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null)
                        directionalIcon
                            ? RtlIcon(icon!, size: iconSize, color: fg)
                            : Icon(icon, size: iconSize, color: fg),
                      if (icon != null && !iconOnly) SizedBox(width: m.gap),
                      if (!iconOnly)
                        Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: fg,
                            fontSize: m.label,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// מסך בסיס: כפתור "חזרה" ענק בראש, כותרת, ותוכן.
class LvScaffold extends StatelessWidget {
  const LvScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.actions = const [],
    this.bottom,
    this.backLabel = 'חזרה',
    this.titleWidget,
    this.holdToGoBack = true,
  });

  final String title;

  /// מחליף את הכותרת (למשל שורת חיפוש).
  final Widget? titleWidget;

  /// החזקה ארוכה של אצבע אחת בכל מקום בגוף המסך חוזרת אחורה.
  final bool holdToGoBack;
  final Widget body;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottom;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final holdIsBack = context.select(
      (LowVisionCubit c) =>
          c.state.actionFor(LvGesture.hold) == LvTouchAction.back,
    );
    final holdSeconds = context.select(
      (LowVisionCubit c) => c.state.holdSeconds,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Material(
        color: p.background,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(m.gap),
            child: Column(
              children: [
                SizedBox(
                  height: m.tapHeight,
                  child: Row(
                    children: [
                      if (onBack != null)
                        LvButton(
                          label: backLabel,
                          icon: FluentIcons.arrow_left_24_filled,
                          directionalIcon: true,
                          onPressed: onBack,
                          height: m.tapHeight,
                        ),
                      SizedBox(width: m.gap * 1.5),
                      Expanded(
                        child:
                            titleWidget ??
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                title,
                                maxLines: 1,
                                style: TextStyle(
                                  color: p.foreground,
                                  fontSize: m.title,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                      ),
                      for (final action in actions) ...[
                        SizedBox(width: m.gap),
                        action,
                      ],
                    ],
                  ),
                ),
                SizedBox(height: m.gap),
                Expanded(
                  child: onBack != null && holdToGoBack && holdIsBack
                      ? LvTouchZones(
                          actions: {
                            LvGesture.hold: LvZoneAction(
                              label: LvTouchAction.back.label,
                              icon: LvTouchAction.back.icon,
                              onTriggered: onBack!,
                            ),
                          },
                          holdDuration: Duration(
                            milliseconds: (holdSeconds * 1000).round(),
                          ),
                          child: body,
                        )
                      : body,
                ),
                if (bottom != null) ...[SizedBox(height: m.gap), bottom!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// שורה ענקית ברשימה: כל השורה לחיצה.
class LvRow extends StatelessWidget {
  const LvRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.indent = 0,
    this.titleSize,
    this.fitTitle = false,
  });

  final String title;
  final String? subtitle;

  /// גודל הכותרת (ברירת מחדל: גודל גוף רגיל).
  final double? titleSize;

  /// הכותרת בשורה אחת שמתכווצת לפי הרוחב במקום להיחתך.
  final bool fitTitle;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final int indent;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: m.gap),
      child: LvPressable(
        onTap: onTap,
        builder: (context, pressed) {
          final highlighted = selected || pressed;
          final fg = highlighted ? p.onAccent : p.foreground;
          return Container(
            constraints: BoxConstraints(minHeight: m.tapHeight * 1.3),
            padding: EdgeInsetsDirectional.only(
              start: m.gap * 2 + indent * m.unit * 0.5,
              end: m.gap * 2,
              top: m.gap,
              bottom: m.gap,
            ),
            decoration: BoxDecoration(
              color: highlighted ? p.accent : p.surface,
              borderRadius: BorderRadius.circular(m.radius),
              border: Border.all(color: p.foreground, width: m.border),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, SizedBox(width: m.gap)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fitTitle
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                title,
                                maxLines: 1,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: titleSize ?? m.body,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                              ),
                            )
                          : Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontSize: titleSize ?? m.body,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontSize: m.label * 0.8),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[SizedBox(width: m.gap), trailing!],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// גלילה ברשימה בכפתורי "למעלה" / "למטה" ענקיים לצד התוכן.
class LvScrollButtons extends StatelessWidget {
  const LvScrollButtons({
    super.key,
    required this.onUp,
    required this.onDown,
  });

  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // כשהאזור נמוך (מקלדת גדולה) הכפתורים היו נמעכים, ולכן מוסתרים.
        if (box.maxHeight < m.tapHeight * 2.6) return const SizedBox.shrink();
        return SizedBox(
          width: m.tapHeight * 1.2,
          child: Column(
            children: [
              Expanded(
                child: LvButton(
                  label: 'למעלה',
                  icon: FluentIcons.chevron_up_24_filled,
                  iconOnly: true,
                  onPressed: onUp,
                  height: double.infinity,
                ),
              ),
              SizedBox(height: m.gap),
              Expanded(
                child: LvButton(
                  label: 'למטה',
                  icon: FluentIcons.chevron_down_24_filled,
                  iconOnly: true,
                  onPressed: onDown,
                  height: double.infinity,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// הודעת מצב גדולה (טעינה, ריק, שגיאה) במרכז המסך.
class LvMessage extends StatelessWidget {
  const LvMessage(this.text, {super.key, this.busy = false, this.action});

  final String text;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(m.gap * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                SizedBox(
                  width: m.unit * 1.5,
                  height: m.unit * 1.5,
                  child: CircularProgressIndicator(
                    color: p.foreground,
                    strokeWidth: m.border * 1.5,
                  ),
                ),
                SizedBox(height: m.gap * 2),
              ],
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.foreground,
                  fontSize: m.body,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (action != null) ...[SizedBox(height: m.gap * 2), action!],
            ],
          ),
        ),
      ),
    );
  }
}
