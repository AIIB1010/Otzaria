import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/low_vision/update/lv_update_controller.dart';
import 'package:otzaria/low_vision/update/lv_update_service.dart';
import 'package:otzaria/low_vision/view/lv_gestures_screen.dart';
import 'package:otzaria/low_vision/view/lv_input_test_screen.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_shell_controller.dart';
import 'package:otzaria/low_vision/view/widgets/lv_pressable.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

String lvKeyLabel(int keyId) {
  final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
  if (key == null) return '#$keyId';
  final label = key.keyLabel.trim();
  if (label.isEmpty) return key.debugName ?? '#$keyId';
  return label.length == 1 ? label.toUpperCase() : label;
}

/// הגדרות לעוזר רואה: צבעים, גודל טקסט, שיוך מקשים, ומעבר לתוכנה המלאה.
class LvSettingsScreen extends StatefulWidget {
  const LvSettingsScreen({super.key});

  @override
  State<LvSettingsScreen> createState() => _LvSettingsScreenState();
}

class _LvSettingsScreenState extends State<LvSettingsScreen> {
  LvAction? _capturing;

  bool _onRawKey(KeyEvent event) {
    final action = _capturing;
    if (action == null || event is! KeyDownEvent) return false;
    context.read<LowVisionCubit>().setKeyOverride(action.name, [
      event.logicalKey.keyId,
    ]);
    setState(() => _capturing = null);
    return true;
  }

  void _openAdvanced() {
    final shell = RepositoryProvider.of<LvShellController>(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    shell.openAdvanced();
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final cubit = context.read<LowVisionCubit>();
    final router = LvKeyScope.routerOf(context);
    return LvKeyScope(
      onRawKey: _onRawKey,
      actions: {
        LvAction.back: () {
          if (_capturing != null) {
            setState(() => _capturing = null);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: LvScaffold(
        title: 'הגדרות',
        onBack: () => Navigator.of(context).maybePop(),
        body: BlocBuilder<LowVisionCubit, LowVisionState>(
          builder: (context, state) => ListView(
            children: [
              _Section(
                title: 'התוכנה המלאה',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'לעוזר רואה: כל ההגדרות של אוצריא, חיפוש בתוך ספרים, '
                      'הורדת ספרייה והוספת ספרים. אפשר לחזור לתצוגה הפשוטה '
                      'בכפתור שבפינה.',
                      style: _bodyStyle(m, p),
                    ),
                    SizedBox(height: m.gap),
                    LvButton(
                      label: 'פתיחת התוכנה המלאה',
                      icon: FluentIcons.apps_24_filled,
                      onPressed: _openAdvanced,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'עדכון האפליקציה',
                child: const _UpdateSection(),
              ),
              _Section(
                title: 'צבעים',
                child: Wrap(
                  spacing: m.gap,
                  runSpacing: m.gap,
                  children: [
                    for (final option in LvPalette.values)
                      _PaletteChip(
                        palette: option,
                        selected: option == state.palette,
                        onTap: () => cubit.setPalette(option),
                      ),
                  ],
                ),
              ),
              _Section(
                title: 'גודל הטקסט בספרים',
                child: Row(
                  children: [
                    LvButton(
                      label: 'הקטן',
                      icon: FluentIcons.subtract_24_filled,
                      onPressed: cubit.zoomOut,
                    ),
                    SizedBox(width: m.gap),
                    Expanded(
                      child: Text(
                        '${(state.textScale * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: _bodyStyle(m, p).copyWith(
                          fontSize: m.title,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SizedBox(width: m.gap),
                    LvButton(
                      label: 'הגדל',
                      icon: FluentIcons.add_24_filled,
                      onPressed: cubit.zoomIn,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'ניקוד וטעמים',
                child: LvButton(
                  label: state.showNikud
                      ? 'מוצגים (הקישו להסתרה)'
                      : 'מוסתרים (הקישו להצגה)',
                  icon: FluentIcons.text_font_24_filled,
                  filled: state.showNikud,
                  onPressed: () => cubit.setShowNikud(!state.showNikud),
                ),
              ),
              _Section(
                title: 'כפתורים פיזיים וחוגה',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'כפתור "חזרה" של המכשיר חוזר מסך אחד אחורה. חוגת עוצמת הקול '
                      'גוללת את הדף בצעדים קטנים (למטה בסיבוב לכיוון אחד, '
                      'ולמעלה בכיוון השני), ואפשר לשייך מחדש כל מקש בהמשך '
                      'המסך. הבדיקה מציגה מה כל כפתור ונגיעה שולחים.',
                      style: _bodyStyle(m, p),
                    ),
                    SizedBox(height: m.gap),
                    LvButton(
                      label: 'בדיקת כפתורים ונגיעה',
                      icon: FluentIcons.hand_left_24_filled,
                      filled: false,
                      onPressed: () => lvPush<void>(
                        context,
                        const LvInputTestScreen(),
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'רגישות נגיעה וגדלים',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'נגיעה חזקה גורמת לאצבע לזוז מעט. ברגישות גבוהה נגיעה '
                      'נקלטת גם אם האצבע זזה. ההגדרות האלה חלות על כל המסכים.',
                      style: _bodyStyle(m, p),
                    ),
                    SizedBox(height: m.gap),
                    _CycleButton(
                      title: 'רגישות נגיעה',
                      labels: LowVisionState.tapToleranceLabels,
                      index: state.tapToleranceIndex,
                      onChanged: cubit.setTapTolerance,
                    ),
                    SizedBox(height: m.gap),
                    _CycleButton(
                      title: 'גודל מסך הבית',
                      labels: LowVisionState.homeSizeLabels,
                      index: state.homeSizeIndex,
                      onChanged: cubit.setHomeSize,
                    ),
                    SizedBox(height: m.gap),
                    _CycleButton(
                      title: 'גודל המקלדת',
                      labels: LowVisionState.keyboardSizeLabels,
                      index: state.keyboardSizeIndex,
                      onChanged: cubit.setKeyboardSize,
                    ),
                    SizedBox(height: m.gap),
                    LvButton(
                      label: state.keysOnTouchDown
                          ? 'אות נכנסת ברגע הנגיעה (הקישו לשינוי)'
                          : 'אות נכנסת בהרמת האצבע (הקישו לשינוי)',
                      icon: FluentIcons.keyboard_24_filled,
                      filled: false,
                      onPressed: () =>
                          cubit.setKeysOnTouchDown(!state.keysOnTouchDown),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'מחוות מגע',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'לחיצה כפולה בצד ימין או שמאל, נגיעה בשתי או שלוש '
                      'אצבעות, החזקה ארוכה: לכל אחת בוחרים מה היא מפעילה.',
                      style: _bodyStyle(m, p),
                    ),
                    SizedBox(height: m.gap),
                    LvButton(
                      label: 'הגדרת מחוות המגע',
                      icon: FluentIcons.hand_left_24_filled,
                      filled: false,
                      onPressed: () =>
                          lvPush<void>(context, const LvGesturesScreen()),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'מקלדת חיצונית ומקשי מאקרו',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _capturing == null
                          ? 'הקישו על פעולה ואז על המקש (או מקש המאקרו) '
                                'שיפעיל אותה.'
                          : 'לחצו עכשיו על המקש עבור: ${_capturing!.label}',
                      style: _bodyStyle(m, p),
                    ),
                    SizedBox(height: m.gap),
                    for (final action in LvAction.values)
                      Padding(
                        padding: EdgeInsets.only(bottom: m.gap),
                        child: LvButton(
                          label:
                              '${action.label}:  ${router.keysFor(action).map(lvKeyLabel).join(' / ')}',
                          filled: _capturing == action,
                          selected: _capturing == action,
                          onPressed: () => setState(
                            () => _capturing = _capturing == action
                                ? null
                                : action,
                          ),
                        ),
                      ),
                    LvButton(
                      label: 'איפוס כל המקשים לברירת מחדל',
                      icon: FluentIcons.arrow_reset_24_filled,
                      filled: false,
                      onPressed: cubit.resetKeyOverrides,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _bodyStyle(LvMetrics m, LvPalette p) => TextStyle(
    color: p.foreground,
    fontSize: m.label,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: m.gap * 2),
      child: Container(
        padding: EdgeInsets.all(m.gap * 1.5),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(m.radius),
          border: Border.all(color: p.foreground, width: m.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: p.foreground,
                fontSize: m.body,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: m.gap),
            child,
          ],
        ),
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final LvPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    return LvPressable(
      onTap: onTap,
      builder: (context, pressed) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.gap * 2,
          vertical: m.gap * 1.5,
        ),
        decoration: BoxDecoration(
          color: pressed ? palette.foreground : palette.background,
          borderRadius: BorderRadius.circular(m.radius),
          border: Border.all(
            color: selected ? palette.foreground : Colors.grey,
            width: selected ? m.border * 3 : m.border,
          ),
        ),
        child: Text(
          '${selected ? '✓ ' : ''}${palette.label}',
          style: TextStyle(
            color: pressed ? palette.background : palette.foreground,
            fontSize: m.label,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// בדיקה והתקנה של בנייה חדשה בלחיצת כפתור. המצב חי ב-[LvUpdateController].
class _UpdateSection extends StatelessWidget {
  const _UpdateSection();

  String _message(LvUpdateState state) {
    final current = kLvBuildNumber == 0 ? 'מקומית' : '$kLvBuildNumber';
    return switch (state.status) {
      LvUpdateStatus.idle => 'גרסה מותקנת: $current',
      LvUpdateStatus.checking => 'בודק אם יש גרסה חדשה…',
      LvUpdateStatus.upToDate => 'האפליקציה מעודכנת (גרסה $current).',
      LvUpdateStatus.available =>
        'יש גרסה חדשה: ${state.latest?.build} (מותקנת: $current).',
      LvUpdateStatus.downloading =>
        'מוריד… ${(state.progress * 100).round()}%\n'
            'אפשר לצאת מהמסך הזה, ההורדה תמשיך ברקע.',
      LvUpdateStatus.waitingForInstaller =>
        'אשרו את ההתקנה במסך שנפתח. האפליקציה תיסגר ותיפתח מחדש.',
      LvUpdateStatus.needsPermission =>
        'אפשרו "התקנה מהאפליקציה הזו" במסך שנפתח, חזרו ולחצו "עדכן עכשיו".',
      LvUpdateStatus.noRelease => 'עדיין לא פורסמה גרסה לעדכון.',
      LvUpdateStatus.error => state.error ?? 'אירעה שגיאה.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final controller = RepositoryProvider.of<LvUpdateController>(context);
    return ValueListenableBuilder<LvUpdateState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final canUpdate =
            state.status == LvUpdateStatus.available ||
            state.status == LvUpdateStatus.needsPermission;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _message(state),
              style: TextStyle(
                color: p.foreground,
                fontSize: m.label,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            if (state.status == LvUpdateStatus.downloading) ...[
              SizedBox(height: m.gap),
              LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                minHeight: m.unit * 0.3,
                color: p.foreground,
                backgroundColor: p.foreground.withValues(alpha: 0.2),
              ),
            ],
            SizedBox(height: m.gap),
            if (canUpdate)
              LvButton(
                label: 'עדכן עכשיו',
                icon: FluentIcons.arrow_download_24_filled,
                onPressed: controller.update,
              )
            else
              LvButton(
                label: 'בדוק אם יש גרסה חדשה',
                icon: FluentIcons.arrow_sync_24_filled,
                filled: false,
                onPressed: state.isBusy ? null : controller.check,
              ),
          ],
        );
      },
    );
  }
}

/// כפתור שמחליף בין מספר אפשרויות בכל לחיצה, ומציג את הנוכחית.
class _CycleButton extends StatelessWidget {
  const _CycleButton({
    required this.title,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final String title;
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => LvButton(
    label: '$title: ${labels[index]} (הקישו לשינוי)',
    icon: FluentIcons.arrow_sync_24_filled,
    filled: false,
    onPressed: () => onChanged((index + 1) % labels.length),
  );
}
