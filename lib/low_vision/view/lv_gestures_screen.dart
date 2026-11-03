import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// מחוות מגע: לכל מחווה בוחרים איזו פעולה היא מפעילה.
class LvGesturesScreen extends StatelessWidget {
  const LvGesturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final cubit = context.read<LowVisionCubit>();
    return LvScaffold(
      title: 'מחוות מגע',
      onBack: () => Navigator.of(context).maybePop(),
      body: BlocBuilder<LowVisionCubit, LowVisionState>(
        builder: (context, state) => ListView(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: m.gap * 2),
              child: Text(
                'גרירה באצבע אחת תמיד תופסת את העמוד ומזיזה אותו לכל כיוון, '
                'גם באלכסון. כל תזוזה מבטלת מיד לחיצה או החזקה, ולכן אין '
                'חשש שגרירה תפעיל משהו. נגיעה בודדת באצבע אחת אינה עושה דבר. '
                'בחרו מה כל מחווה אחרת מפעילה:',
                style: TextStyle(
                  color: p.foreground,
                  fontSize: m.label,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            for (final gesture in LvGesture.values)
              LvRow(
                title: gesture.label,
                subtitle: state.actionFor(gesture).label,
                leading: Icon(
                  state.actionFor(gesture).icon,
                  size: m.iconSize,
                  color: p.foreground,
                ),
                onTap: () async {
                  final chosen = await lvPush<LvTouchAction>(
                    context,
                    LvActionPickerScreen(
                      gesture: gesture,
                      current: state.actionFor(gesture),
                    ),
                  );
                  if (chosen != null) cubit.setTouchBinding(gesture, chosen);
                },
              ),
            SizedBox(height: m.gap),
            LvButton(
              label: 'זמן החזקה: ${state.holdSeconds} שניות (הקישו לשינוי)',
              icon: FluentIcons.timer_24_filled,
              filled: false,
              onPressed: () {
                const options = LowVisionState.holdSecondsOptions;
                final index = options.indexOf(state.holdSeconds);
                cubit.setHoldSeconds(options[(index + 1) % options.length]);
              },
            ),
            SizedBox(height: m.gap),
            LvButton(
              label: state.glide
                  ? 'העמוד ממשיך להחליק אחרי גרירה (הקישו לשינוי)'
                  : 'העמוד נעצר מיד כשהאצבע נעצרת (הקישו לשינוי)',
              icon: FluentIcons.arrow_move_24_filled,
              filled: false,
              onPressed: () => cubit.setGlide(!state.glide),
            ),
            SizedBox(height: m.gap),
            LvButton(
              label: 'איפוס מחוות לברירת מחדל',
              icon: FluentIcons.arrow_reset_24_filled,
              filled: false,
              onPressed: cubit.resetTouchSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// בחירת הפעולה של מחווה. מחזיר את [LvTouchAction] שנבחרה.
class LvActionPickerScreen extends StatelessWidget {
  const LvActionPickerScreen({
    super.key,
    required this.gesture,
    required this.current,
  });

  final LvGesture gesture;
  final LvTouchAction current;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return LvScaffold(
      title: gesture.label,
      onBack: () => Navigator.of(context).maybePop(),
      body: ListView(
        children: [
          for (final action in LvTouchAction.values)
            LvRow(
              title: action.label,
              selected: action == current,
              leading: Icon(
                action.icon,
                size: m.iconSize,
                color: action == current ? p.onAccent : p.foreground,
              ),
              onTap: () => Navigator.of(context).pop<LvTouchAction>(action),
            ),
        ],
      ),
    );
  }
}
