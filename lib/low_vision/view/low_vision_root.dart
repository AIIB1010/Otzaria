import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/input/lv_contact_filter.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/update/lv_update_controller.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_home_screen.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_shell_controller.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// שורש מהדורת הראייה הלקויה.
///
/// התוכנה הרגילה ([advancedApp]) נשארת חיה מתחת, כדי שטעינת הספרייה,
/// האינדקס והעדכונים ימשיכו לעבוד; הממשק הפשוט מוצג מעליה. בכפתור ההגדרות
/// הקטן עוברים לתוכנה המלאה (לעוזר רואה), ובכפתור גדול חוזרים.
class LowVisionRoot extends StatefulWidget {
  const LowVisionRoot({super.key, required this.advancedApp});

  final Widget advancedApp;

  @override
  State<LowVisionRoot> createState() => _LowVisionRootState();
}

class _LowVisionRootState extends State<LowVisionRoot> {
  late final LowVisionCubit _cubit;
  late final LvKeyRouter _router;
  final _shell = LvShellController();
  // חי כל עוד האפליקציה פתוחה, כדי שהורדת עדכון לא תיפסק ביציאה ממסך.
  final _updates = LvUpdateController();
  // נגיעות גדולות (אף, כף יד) נזרקות לפני שהן מגיעות לאפליקציה.
  final _contacts = LvContactFilter();
  StreamSubscription<LowVisionState>? _contactSub;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _canPop = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _cubit = LowVisionCubit()..load();
    _router = LvKeyRouter(_cubit);
    _contacts.install();
    _contactSub = _cubit.stream.listen(
      (state) => _contacts.maxSize = state.maxContactSize,
    );
    _shell.advancedListenable.addListener(_onShellChanged);
  }

  void _onShellChanged() => _router.enabled = !_shell.advanced;

  @override
  void dispose() {
    _shell.advancedListenable.removeListener(_onShellChanged);
    _contactSub?.cancel();
    _contacts.dispose();
    _shell.dispose();
    _updates.dispose();
    _router.dispose();
    _cubit.close();
    _canPop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<LvShellController>.value(value: _shell),
        RepositoryProvider<LvKeyRouter>.value(value: _router),
        RepositoryProvider<LvUpdateController>.value(value: _updates),
        RepositoryProvider<LvContactFilter>.value(value: _contacts),
      ],
      child: BlocProvider<LowVisionCubit>.value(
        value: _cubit,
        child: ValueListenableBuilder<bool>(
          valueListenable: _shell.advancedListenable,
          builder: (context, advanced, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: !advanced,
                  child: TickerMode(
                    enabled: advanced,
                    child: widget.advancedApp,
                  ),
                ),
                if (!advanced)
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _canPop,
                      builder: (context, canPop, _) => NavigatorPopHandler(
                        enabled: canPop,
                        onPopWithResult: (_) =>
                            _navigatorKey.currentState?.maybePop(),
                        child: Navigator(
                          key: _navigatorKey,
                          observers: [_PopObserver(_canPop)],
                          onGenerateRoute: (_) =>
                              lvRoute<void>(const LvHomeScreen()),
                        ),
                      ),
                    ),
                  )
                else
                  PositionedDirectional(
                    bottom: 12,
                    start: 12,
                    child: SafeArea(
                      child: _BackToSimple(onTap: _shell.closeAdvanced),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PopObserver extends NavigatorObserver {
  _PopObserver(this._canPop);

  final ValueNotifier<bool> _canPop;

  void _update() {
    final navigator = this.navigator;
    if (navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _canPop.value = navigator.canPop(),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update();
}

class _BackToSimple extends StatelessWidget {
  const _BackToSimple({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = lvPaletteOf(context);
    final m = LvMetrics.of(context);
    return Material(
      color: p.accent,
      elevation: 8,
      borderRadius: BorderRadius.circular(m.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(m.radius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.gap * 2,
            vertical: m.gap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.home_24_filled,
                color: p.onAccent,
                size: m.label,
              ),
              SizedBox(width: m.gap),
              Text(
                'חזרה לתצוגה הפשוטה',
                style: TextStyle(
                  color: p.onAccent,
                  fontSize: m.label * 0.9,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
