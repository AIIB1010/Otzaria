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
import 'package:otzaria/low_vision/update/lv_update_service.dart';
import 'package:otzaria/low_vision/view/lv_shell_controller.dart';
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
  const LvSettingsScreen({super.key, this.updateService});

  /// לבדיקות.
  final LvUpdateService? updateService;

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
                child: _UpdateSection(service: widget.updateService),
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
                title: 'דפדוף בלחיצה כפולה',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'בקורא: לחיצה כפולה בצד אחד של המסך מדפדפת, והחזקה ארוכה '
                      'של אצבע אחת חוזרת אחורה. נגיעה בודדת אינה עושה דבר.',
                      style: _bodyStyle(m, p),
                    ),
                    SizedBox(height: m.gap),
                    LvButton(
                      label: state.swapTapSides
                          ? 'ימין = הבא, שמאל = הקודם (הקישו להחלפה)'
                          : 'שמאל = הבא, ימין = הקודם (הקישו להחלפה)',
                      icon: FluentIcons.arrow_swap_24_filled,
                      filled: false,
                      onPressed: () =>
                          cubit.setSwapTapSides(!state.swapTapSides),
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
    return Material(
      color: palette.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(m.radius),
        side: BorderSide(
          color: selected ? palette.foreground : Colors.grey,
          width: selected ? m.border * 3 : m.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(m.radius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.gap * 2,
            vertical: m.gap * 1.5,
          ),
          child: Text(
            '${selected ? '✓ ' : ''}${palette.label}',
            style: TextStyle(
              color: palette.foreground,
              fontSize: m.label,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

enum _UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  waitingForInstaller,
  needsPermission,
  noRelease,
  error,
}

/// בדיקה והתקנה של בנייה חדשה בלחיצת כפתור.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection({this.service});

  final LvUpdateService? service;

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  late final LvUpdateService _service = widget.service ?? LvUpdateService();
  _UpdateStatus _status = _UpdateStatus.idle;
  LvUpdateInfo? _latest;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _status = _UpdateStatus.checking);
    try {
      final latest = await _service.fetchLatest();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _status = latest == null
            ? _UpdateStatus.noRelease
            : latest.isNewerThan(kLvBuildNumber)
            ? _UpdateStatus.available
            : _UpdateStatus.upToDate;
      });
    } on LvUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _status = _UpdateStatus.error;
        });
      }
    }
  }

  Future<void> _update() async {
    final latest = _latest;
    if (latest == null) return;
    setState(() {
      _status = _UpdateStatus.downloading;
      _progress = 0;
    });
    try {
      final apk = await _service.download(
        latest,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      final result = await _service.install(apk);
      if (!mounted) return;
      setState(
        () => _status = result == LvInstallResult.needsPermission
            ? _UpdateStatus.needsPermission
            : _UpdateStatus.waitingForInstaller,
      );
    } on LvUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _status = _UpdateStatus.error;
        });
      }
    }
  }

  String get _message {
    final current = kLvBuildNumber == 0 ? 'מקומית' : '$kLvBuildNumber';
    return switch (_status) {
      _UpdateStatus.idle => 'גרסה מותקנת: $current',
      _UpdateStatus.checking => 'בודק אם יש גרסה חדשה…',
      _UpdateStatus.upToDate => 'האפליקציה מעודכנת (גרסה $current).',
      _UpdateStatus.available =>
        'יש גרסה חדשה: ${_latest?.build} (מותקנת: $current).',
      _UpdateStatus.downloading => 'מוריד… ${(_progress * 100).round()}%',
      _UpdateStatus.waitingForInstaller =>
        'אשרו את ההתקנה במסך שנפתח. האפליקציה תיסגר ותיפתח מחדש.',
      _UpdateStatus.needsPermission =>
        'אפשרו "התקנה מהאפליקציה הזו" במסך שנפתח, חזרו ולחצו "עדכן עכשיו".',
      _UpdateStatus.noRelease => 'עדיין לא פורסמה גרסה לעדכון.',
      _UpdateStatus.error => _error ?? 'אירעה שגיאה.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final busy =
        _status == _UpdateStatus.checking ||
        _status == _UpdateStatus.downloading;
    final canUpdate =
        _status == _UpdateStatus.available ||
        _status == _UpdateStatus.needsPermission;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _message,
          style: TextStyle(
            color: p.foreground,
            fontSize: m.label,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        SizedBox(height: m.gap),
        if (canUpdate)
          LvButton(
            label: 'עדכן עכשיו',
            icon: FluentIcons.arrow_download_24_filled,
            onPressed: _update,
          )
        else
          LvButton(
            label: 'בדוק אם יש גרסה חדשה',
            icon: FluentIcons.arrow_sync_24_filled,
            filled: false,
            onPressed: busy ? null : _check,
          ),
      ],
    );
  }
}
