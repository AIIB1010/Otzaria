import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// מנווט את המשתמש לדף תוסף ומוסר לו payload כאירוע JS.
///
/// פותר את המרוץ בין הניווט לטעינת ה-WebView: אם דף התוסף עדיין לא סיים
/// boot, ה-payload נשמר כממתין ונמסר רק כשה-[PluginTabPage] מדווח שהדף מוכן.
class PluginPageLauncher {
  static final PluginPageLauncher instance = PluginPageLauncher._();
  PluginPageLauncher._();

  final _navigators = Expando<void Function(String pluginId)>();

  /// מנווט לדף התוסף בחלון הנוכחי — נרשם ע"י MainWindowScreen של כל חלון.
  void Function(String pluginId)? get navigator =>
      _navigators[AppWindowKeys.current];
  set navigator(void Function(String pluginId)? value) =>
      _navigators[AppWindowKeys.current] = value;

  void register(AppWindowKeys keys, void Function(String pluginId) navigator) =>
      _navigators[keys] = navigator;

  /// מסיר את [navigator] רק אם הוא עדיין הרשום בחלון [keys].
  void unregister(
    AppWindowKeys keys,
    void Function(String pluginId) navigator,
  ) {
    if (_navigators[keys] == navigator) _navigators[keys] = null;
  }

  final Map<String, List<({String topic, Map<String, dynamic> payload})>>
  _pending = {};

  /// דפים מוכנים לפי מופע — לתוסף יכולים להיות כמה טאבים פתוחים.
  final Set<PluginInstanceKey> _readyPages = {};

  // שרשרת מסירה פר-תוסף: כל אירוע ממתין לקודמו, כך שהסדר נשמר גם כשאירוע
  // חדש מגיע בזמן ריקון הממתינים.
  final Map<String, Future<void>> _deliveryChain = {};

  /// האם ממתינים ל-[pluginId] אירועים עד שדף שלו יהיה מוכן.
  bool hasPendingFor(String pluginId) =>
      _pending[pluginId]?.isNotEmpty ?? false;

  bool _hasReadyPage(String pluginId) =>
      _readyPages.any((key) => key.pluginId == pluginId);

  /// פותח את דף התוסף. אם סופק [topic], ה-[payload] יימסר לתוסף כאירוע —
  /// מיד אם דף כלשהו כבר מוכן, אחרת לאחר סיום ה-boot של הדף הראשון.
  void open(
    String pluginId, {
    String? topic,
    Map<String, dynamic> payload = const {},
  }) {
    if (topic != null) {
      if (_hasReadyPage(pluginId)) {
        _enqueueDelivery(pluginId, topic, payload);
      } else {
        _pending.putIfAbsent(pluginId, () => []).add((
          topic: topic,
          payload: payload,
        ));
      }
    }
    navigator?.call(pluginId);
  }

  /// נקרא ע"י PluginTabPage כשה-boot הסתיים — האירועים הממתינים נמסרים
  /// בסדרם **לדף שדיווח שהוא מוכן**, לא למופע אחר של אותו תוסף.
  void markPageReady(
    String pluginId, {
    String instanceId = PluginInstanceIds.defaultForeground,
  }) {
    _readyPages.add((pluginId: pluginId, instanceId: instanceId));
    final pending = _pending.remove(pluginId);
    if (pending == null) return;
    debugPrint(
      'PluginPageLauncher: $pluginId ready, delivering ${pending.length} '
      'pending event(s)',
    );
    for (final event in pending) {
      _enqueueDelivery(
        pluginId,
        event.topic,
        event.payload,
        instanceId: instanceId,
      );
    }
  }

  /// נקרא ע"י PluginTabPage בעת dispose של דף התוסף. מצב התוסף (ממתינים,
  /// שרשרת מסירה) מתנקה רק כשלא נשאר אף דף מוכן שלו.
  void markPageClosed(
    String pluginId, {
    String instanceId = PluginInstanceIds.defaultForeground,
  }) {
    _readyPages.remove((pluginId: pluginId, instanceId: instanceId));
    if (_hasReadyPage(pluginId)) return;
    _pending.remove(pluginId);
    _deliveryChain.remove(pluginId);
  }

  void _enqueueDelivery(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    String? instanceId,
  }) {
    final previous = _deliveryChain[pluginId] ?? Future<void>.value();
    final next = previous.then(
      (_) => PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        pluginId,
        topic,
        payload,
        resumeForegroundIfNeeded: true,
        instanceId: instanceId,
      ),
    );
    // catchError כדי ששגיאה במסירה אחת לא תחסום את הבאות בשרשרת.
    _deliveryChain[pluginId] = next.catchError((_) {});
  }
}
