import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';

typedef LvRawKeyHandler = bool Function(KeyEvent event);

class _Registration {
  _Registration(this.actions, this.raw);
  Map<LvAction, VoidCallback> actions;
  final LvRawKeyHandler? raw;
}

/// מפנה מקשי מקלדת חיצונית למסך העליון בלבד.
///
/// מאזין ל-[HardwareKeyboard] ולא ל-Focus, כך שמגע על המסך לא "גונב" את
/// המקשים מהמשתמש.
class LvKeyRouter {
  LvKeyRouter(this._cubit) {
    HardwareKeyboard.instance.addHandler(_onEvent);
  }

  final LowVisionCubit _cubit;
  final List<_Registration> _stack = [];

  /// כבוי כשהממשק המתקדם מוצג.
  bool enabled = true;

  void dispose() => HardwareKeyboard.instance.removeHandler(_onEvent);

  Object register(Map<LvAction, VoidCallback> actions, LvRawKeyHandler? raw) {
    final entry = _Registration(actions, raw);
    _stack.add(entry);
    return entry;
  }

  void unregister(Object token) => _stack.remove(token);

  void update(Object token, Map<LvAction, VoidCallback> actions) {
    (token as _Registration).actions = actions;
  }

  /// המקשים בפועל לכל פעולה: ברירת מחדל או שיוך מותאם.
  Set<int> keysFor(LvAction action) {
    final custom = _cubit.state.keyOverrides[action.name];
    return custom != null
        ? custom.toSet()
        : {for (final k in action.defaultKeys) k.keyId};
  }

  bool _onEvent(KeyEvent event) {
    if (!enabled || _stack.isEmpty || event is KeyUpEvent) return false;
    final top = _stack.last;
    if (top.raw?.call(event) ?? false) return true;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    final id = event.logicalKey.keyId;
    for (final entry in top.actions.entries) {
      if (keysFor(entry.key).contains(id)) {
        entry.value();
        return true;
      }
    }
    return false;
  }
}

/// מסך ה-low vision מצהיר כאן אילו פעולות מקלדת הוא תומך בהן.
class LvKeyScope extends StatefulWidget {
  const LvKeyScope({
    super.key,
    required this.actions,
    this.onRawKey,
    required this.child,
  });

  final Map<LvAction, VoidCallback> actions;

  /// מקבל כל אירוע מקש לפני המיפוי; מחזיר true כשטיפל בו (למשל הקלדה).
  final LvRawKeyHandler? onRawKey;
  final Widget child;

  static LvKeyRouter routerOf(BuildContext context) =>
      RepositoryProvider.of<LvKeyRouter>(context);

  @override
  State<LvKeyScope> createState() => _LvKeyScopeState();
}

class _LvKeyScopeState extends State<LvKeyScope> {
  late final LvKeyRouter _router;
  Object? _token;

  @override
  void initState() {
    super.initState();
    _router = LvKeyScope.routerOf(context);
    _token = _router.register(
      widget.actions,
      widget.onRawKey == null ? null : (e) => widget.onRawKey!(e),
    );
  }

  @override
  void didUpdateWidget(LvKeyScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _router.update(_token!, widget.actions);
  }

  @override
  void dispose() {
    _router.unregister(_token!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
