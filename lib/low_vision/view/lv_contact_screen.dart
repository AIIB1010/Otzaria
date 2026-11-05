import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/input/lv_contact_filter.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// כיול דחיית נגיעות גדולות (אף, לחי, כף יד). מודדים כמה גדולה נגיעה של אצבע
/// במסך הזה, ומשם נגזר הגודל שמעליו נגיעה נדחית. המסך גם מאפשר לבדוק את זה:
/// נוגעים בו עם האף, ורואים אם הנגיעה נדחתה.
class LvContactScreen extends StatefulWidget {
  const LvContactScreen({super.key});

  /// כמה נגיעות אצבע נמדדות בכיול.
  static const int samplesNeeded = 6;

  @override
  State<LvContactScreen> createState() => _LvContactScreenState();
}

class _LvContactScreenState extends State<LvContactScreen> {
  late final LvContactFilter _filter;
  final _samples = <double>[];
  bool _calibrating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _filter = context.read<LvContactFilter>();
    _filter.last.addListener(_onContact);
  }

  @override
  void dispose() {
    _filter.last.removeListener(_onContact);
    _filter.measureOnly = false;
    super.dispose();
  }

  void _start() {
    setState(() {
      _samples.clear();
      _calibrating = true;
      _message = null;
      // בזמן הכיול הכול עובר, גם אם כבר הוגדר סינון קודם.
      _filter.measureOnly = true;
    });
  }

  void _onContact() {
    final sample = _filter.last.value;
    if (sample == null) return;
    if (!_calibrating) {
      setState(() {});
      return;
    }
    if (sample.size <= 0) {
      setState(() {
        _calibrating = false;
        _filter.measureOnly = false;
        _message =
            'המסך לא מדווח על גודל הנגיעה, ולכן אי אפשר לסנן לפי גודל במכשיר הזה.';
      });
      return;
    }
    _samples.add(sample.size);
    if (_samples.length < LvContactScreen.samplesNeeded) {
      setState(() {});
      return;
    }
    final size = _samples.reduce((a, b) => a > b ? a : b);
    context.read<LowVisionCubit>().setFingerSize(size);
    setState(() {
      _calibrating = false;
      _filter.measureOnly = false;
      _message = 'הכיול נשמר. גודל האצבע: ${size.toStringAsFixed(1)}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final state = context.watch<LowVisionCubit>().state;
    final last = _filter.last.value;
    TextStyle style({FontWeight weight = FontWeight.w600}) => TextStyle(
      color: p.foreground,
      fontSize: m.label,
      fontWeight: weight,
      height: 1.3,
    );
    return LvScaffold(
      title: 'כיול נגיעות (אף / כף יד)',
      holdToGoBack: false,
      onBack: () => Navigator.of(context).pop(),
      body: ListView(
        children: [
          Text(
            'אפשר שנגיעה גדולה (אף, לחי, כף יד) לא תיקלט, בלי להקשות על נגיעת '
            'אצבע רגילה. לכיול: לחצו על "התחל כיול" ואז געו במסך באצבע '
            '${LvContactScreen.samplesNeeded} פעמים, כמו שנוגעים בדרך כלל. '
            'אחרי הכיול אפשר לנסות לגעת באף, וכאן יופיע אם הנגיעה נדחתה. את '
            'רמת הסינון קובעים בהגדרות.',
            style: style(),
          ),
          SizedBox(height: m.gap * 2),
          if (_calibrating)
            Text(
              'געו במסך באצבע: ${_samples.length} מתוך '
              '${LvContactScreen.samplesNeeded}',
              style: style(weight: FontWeight.w900),
            )
          else
            LvButton(
              label: 'התחל כיול',
              icon: FluentIcons.hand_left_24_filled,
              onPressed: _start,
            ),
          if (_message != null) ...[
            SizedBox(height: m.gap),
            Text(_message!, style: style(weight: FontWeight.w900)),
          ],
          SizedBox(height: m.gap * 2),
          Text(
            state.fingerSize > 0
                ? 'גודל האצבע השמור: ${state.fingerSize.toStringAsFixed(1)}. '
                      'נגיעה גדולה מ-${state.maxContactSize.toStringAsFixed(1)} '
                      'נדחית.'
                : 'עדיין לא בוצע כיול, ולכן אין סינון.',
            style: style(),
          ),
          SizedBox(height: m.gap),
          Text(
            last == null
                ? 'נגיעה אחרונה: עדיין לא נגעתם'
                : 'נגיעה אחרונה: גודל ${last.size.toStringAsFixed(1)} '
                      '(רדיוס ${last.radiusMajor.toStringAsFixed(1)}, '
                      'size ${last.reportedSize.toStringAsFixed(2)}), '
                      '${last.rejected ? 'נדחתה' : 'התקבלה'}',
            style: style(weight: FontWeight.w900),
          ),
          SizedBox(height: m.gap),
          ValueListenableBuilder<int>(
            valueListenable: _filter.rejectedCount,
            builder: (context, count, _) =>
                Text('נגיעות שנדחו: $count', style: style()),
          ),
          if (state.fingerSize > 0) ...[
            SizedBox(height: m.gap * 2),
            LvButton(
              label: 'בטל כיול (בלי סינון)',
              icon: FluentIcons.dismiss_24_filled,
              filled: false,
              onPressed: () => context.read<LowVisionCubit>().setFingerSize(0),
            ),
          ],
        ],
      ),
    );
  }
}
