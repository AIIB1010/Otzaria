import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/plugins/adapters/plugin_calendar_adapter.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_planner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';

/// מצב שהבעלים פרסם: [values] בתוקף מ-[revision] של ההפעלה [epoch].
@immutable
class CalendarAlertsUpdate {
  const CalendarAlertsUpdate({
    required this.epoch,
    required this.revision,
    required this.values,
    this.pluginEventsChanged = false,
  });

  final String epoch;
  final int revision;
  final Map<String, Object?> values;

  /// אירועי התוספים במסד השתנו, ויש לטעון אותם מחדש.
  final bool pluginEventsChanged;

  /// האם העדכון חדש מ-[epoch]/[revision] שכבר הוחלו.
  bool isNewerThan(String? epoch, int revision) =>
      epoch != this.epoch || this.revision > revision;

  static CalendarAlertsUpdate? fromJson(Object? json) {
    if (json is! Map) return null;
    final epoch = json['epoch'];
    final revision = json['revision'];
    final values = json['values'];
    if (epoch is! String || revision is! int || values is! Map) return null;
    return CalendarAlertsUpdate(
      epoch: epoch,
      revision: revision,
      values: Map<String, Object?>.from(values),
      pluginEventsChanged: json['pluginEventsChanged'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'revision': revision,
    'values': values,
    if (pluginEventsChanged) 'pluginEventsChanged': true,
  };
}

/// תוצאת ריצת תזמון. נפרדת מאישור הפקודה, שחוזר לפני התזמון.
@immutable
class CalendarScheduleStatus {
  const CalendarScheduleStatus({
    required this.epoch,
    required this.revision,
    required this.ok,
    this.failures = 0,
  });

  final String epoch;
  final int revision;
  final bool ok;
  final int failures;

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'revision': revision,
    'ok': ok,
    'failures': failures,
  };

  static CalendarScheduleStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final epoch = json['epoch'];
    final revision = json['revision'];
    final ok = json['ok'];
    final failures = json['failures'];
    if (epoch is! String || revision is! int || ok is! bool) return null;
    return CalendarScheduleStatus(
      epoch: epoch,
      revision: revision,
      ok: ok,
      failures: failures is int ? failures : 0,
    );
  }
}

/// הבעלים היחיד של התראות לוח השנה והתוספים בתהליך.
///
/// כל שינוי במצב עובר בתור סדרתי אחד ומוחל על הערך השמור העדכני. התזמון
/// עצמו רץ בעובד יחיד שקורא את המצב מחדש בכל ריצה, כך ששני חלונות לעולם
/// אינם מבטלים ומתזמנים את אותו מזהה במקביל.
class CalendarAlertsOwner {
  CalendarAlertsOwner({
    this._store = const SettingsCalendarAlertsStore(),
    NotificationService? notifications,
    PluginNotificationIdStore? pluginIds,
    Future<List<CustomEvent>> Function()? pluginEvents,
    DateTime Function()? now,
    void Function(Map<String, Object?> message)? broadcast,
    bool? dedupeDuplicates,
  }) : _notificationsOverride = notifications,
       _pluginIdsOverride = pluginIds,
       _pluginEvents =
           pluginEvents ??
           (() => const PluginCalendarAdapter().loadAllPluginEvents()),
       _now = now ?? DateTime.now,
       _broadcast = broadcast ?? _broadcastToWindows,
       _dedupeDuplicates =
           dedupeDuplicates ?? defaultTargetPlatform == TargetPlatform.windows;

  static CalendarAlertsOwner? _instance;

  /// הבעלים של ה-isolate. נבנה בזול ואינו נוגע בתוסף הנייטיבי.
  static CalendarAlertsOwner get instance =>
      _instance ??= CalendarAlertsOwner();

  @visibleForTesting
  static set instanceForTesting(CalendarAlertsOwner? owner) =>
      _instance = owner;

  /// בקשת אפיק: פקודה מחלון משני. רק הבעלים עונה עליה.
  static const String requestCommand = 'calendarAlerts.command';

  /// שידור: המצב השתנה.
  static const String requestStateChanged = 'calendarAlerts.stateChanged';

  /// שידור: תוצאת ריצת תזמון.
  static const String requestScheduleStatus = 'calendarAlerts.scheduleStatus';

  final CalendarAlertsStore _store;
  final NotificationService? _notificationsOverride;
  final PluginNotificationIdStore? _pluginIdsOverride;
  final Future<List<CustomEvent>> Function() _pluginEvents;
  final DateTime Function() _now;
  final void Function(Map<String, Object?> message) _broadcast;
  final bool _dedupeDuplicates;

  NotificationService get _notifications =>
      _notificationsOverride ?? NotificationService();

  late final PluginNotificationIdStore _pluginIds =
      _pluginIdsOverride ?? RegistryPluginNotificationIdStore();

  /// מזהה ההפעלה. יחד עם [revision] מאפשר לחלון לזרוק הודעה ישנה.
  final String epoch = _newEpoch();
  int _revision = 0;
  int get revision => _revision;

  Future<void> _lane = Future<void>.value();
  bool _cleanedStoredEvents = false;
  bool _dedupedPending = false;

  Set<int>? _ledger;
  bool _reconcileRunning = false;
  bool _reconcileRequested = false;
  Completer<void>? _idle;
  Timer? _dailyTimer;

  final StreamController<CalendarAlertsUpdate> _updates =
      StreamController<CalendarAlertsUpdate>.broadcast();
  final StreamController<CalendarScheduleStatus> _statuses =
      StreamController<CalendarScheduleStatus>.broadcast();

  /// עדכוני מצב, לחלון של הבעלים עצמו.
  Stream<CalendarAlertsUpdate> get updates => _updates.stream;

  Stream<CalendarScheduleStatus> get scheduleStatuses => _statuses.stream;

  /// מסתיים כשאין ריצת תזמון פעילה או ממתינה.
  @visibleForTesting
  Future<void> get idle => _idle?.future ?? Future<void>.value();

  static String _newEpoch() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  static void _broadcastToWindows(Map<String, Object?> message) {
    if (WindowBus.instance.slot == null) return;
    WindowBus.instance.broadcast(message);
  }

  /// טוען את הרישום לזיכרון, כדי שאיפוס הגדרות לא ימחק אותו לפני הביטול.
  void primeLedger() => _ledger ??= _store.readLedger().toSet();

  /// משחזר את התזמון אחרי עלייה. נקרא אחרי חשיפת החלון, ורק כשיש מה לשחזר.
  Future<void> restoreIfNeeded() async {
    primeLedger();
    await _inLane(_cleanupStoredPluginEvents);
    _requestReconcile();
    await idle;
  }

  /// ההגדרות נמחקו או שוחזרו: החלונות מתיישרים, והתזמון מבטל מול הרישום
  /// שבזיכרון.
  Future<void> handleSettingsReset() => _inLane(() async {
    _publish(await _store.readValues());
    _requestReconcile();
  });

  /// מטפל בבקשת [requestCommand] שהגיעה באפיק.
  Future<Object?> handleBusRequest(Map<String, dynamic> request) {
    final args = request['args'];
    return execute(
      request['op'] as String? ?? '',
      args is Map ? Map<String, Object?>.from(args) : const {},
    );
  }

  /// מבצע פקודה ומחזיר אישור שעובר בין isolates.
  ///
  /// האישור של פקודת מצב חוזר אחרי השמירה ולפני התזמון.
  Future<Map<String, Object?>> execute(
    String op,
    Map<String, Object?> args,
  ) async {
    try {
      switch (op) {
        case 'ensurePermission':
          return _valueAck(await _ensurePermission());
        case 'sendTest':
          return _valueAck(
            await _ensurePermission() &&
                await _notifications.sendTestNotification(),
          );
        case 'pluginShow':
          return await _pluginShow(args);
        case 'pluginSchedule':
          return await _pluginSchedule(args);
        case 'pluginCancel':
          return await _pluginCancel(args);
        case 'pluginCancelAll':
          return await _pluginCancelAll(args);
        case 'pluginPermissions':
          return _valueAck({
            'granted': _notifications.isInitialized
                ? _notifications.hasPermissions
                : NotificationService.grantsWithoutPrompt,
            'initialized': _notifications.isInitialized,
          });
      }
      final mutate = _stateCommands[op];
      if (mutate == null) return _errorAck('error.unknown_method: $op');
      primeLedger();
      return await _applyState((current) => mutate(this, current, args));
    } on _InvalidCommand catch (error) {
      return _errorAck('error.invalid_params: ${error.message}');
    } catch (error, stackTrace) {
      NotificationService.logFailure(
        'פקודת התראות "$op" נכשלה',
        error,
        stackTrace,
      );
      return _errorAck('$error');
    }
  }

  static final Map<
    String,
    Map<String, Object?>? Function(
      CalendarAlertsOwner owner,
      Map<String, Object?> current,
      Map<String, Object?> args,
    )
  >
  _stateCommands = {
    'snapshot': (_, _, _) => null,
    'pluginEventsChanged': (owner, _, _) {
      // אירועי תוספים אינם במפתחות; החלונות טוענים אותם מחדש מהמסד.
      owner._pluginEventsChanged = true;
      return null;
    },
    'upsertEvent': (_, current, args) =>
        _upsertEvents(current, [_eventArg(args['event'])]),
    'deleteEvent': (_, current, args) {
      final id = _stringArg(args, 'id');
      return _replaceEvents(current, (events) {
        events.removeWhere((e) => _idOf(e) == id);
      });
    },
    'setEventGoogleId': (_, current, args) {
      final id = _stringArg(args, 'id');
      final googleId = _stringArg(args, 'googleId');
      return _replaceEvents(current, (events) {
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (_idOf(event) == id && event is Map) {
            events[i] = {...event, 'googleEventId': googleId};
          }
        }
      });
    },
    'replaceSourceEvents': (_, current, args) {
      final events = _eventsArg(args['events']);
      switch (args['kind']) {
        case 'ics':
          final sourceId = _stringArg(args, 'sourceId');
          final subscriptions = _decodeList(
            current[CalendarAlertsKeys.icsSubscriptions],
          );
          final index = subscriptions.indexWhere((s) => _idOf(s) == sourceId);
          // מנוי שהוסר בינתיים אינו חוזר עם אירועיו.
          if (index == -1) return null;
          final refreshed = args['lastRefresh'];
          if (refreshed is int && subscriptions[index] is Map) {
            subscriptions[index] = {
              ...subscriptions[index] as Map,
              'lastRefresh': refreshed,
            };
          }
          return {
            ...?_replaceEvents(current, (stored) {
              stored.removeWhere(
                (e) => e is Map && e['icsSourceId'] == sourceId,
              );
              stored.addAll(events);
            }),
            ..._changed(
              current,
              CalendarAlertsKeys.icsSubscriptions,
              jsonEncode(subscriptions),
            ),
          };
        case 'google' || 'file':
          return _upsertEvents(current, events);
        default:
          throw const _InvalidCommand('kind');
      }
    },
    'removeSourceEvents': (_, current, args) {
      switch (args['kind']) {
        case 'google':
          // אירוע שנוצר באוצריא ונדחף לגוגל שומר id מקומי, ולכן נשאר.
          return _replaceEvents(current, (events) {
            events.removeWhere(
              (e) =>
                  e is Map &&
                  e['googleEventId'] != null &&
                  e['googleEventId'] == e['id'],
            );
          });
        case 'ics':
          final sourceId = _stringArg(args, 'sourceId');
          return _replaceEvents(current, (events) {
            events.removeWhere(
              (e) => e is Map && e['icsSourceId'] == sourceId,
            );
          });
        default:
          throw const _InvalidCommand('kind');
      }
    },
    'addIcsSubscription': (_, current, args) {
      final subscription = args['subscription'];
      if (subscription is! Map || _idOf(subscription) == null) {
        throw const _InvalidCommand('subscription');
      }
      final sourceId = _idOf(subscription);
      final events = _eventsArg(args['events']);
      final subscriptions = _decodeList(
        current[CalendarAlertsKeys.icsSubscriptions],
      )..removeWhere((s) => _idOf(s) == sourceId);
      subscriptions.add(Map<String, Object?>.from(subscription));
      return {
        ...?_replaceEvents(current, (stored) {
          stored.removeWhere((e) => e is Map && e['icsSourceId'] == sourceId);
          stored.addAll(events);
        }),
        ..._changed(
          current,
          CalendarAlertsKeys.icsSubscriptions,
          jsonEncode(subscriptions),
        ),
      };
    },
    'removeIcsSubscription': (_, current, args) {
      final id = _stringArg(args, 'id');
      final subscriptions = _decodeList(
        current[CalendarAlertsKeys.icsSubscriptions],
      )..removeWhere((s) => _idOf(s) == id);
      return {
        ...?_replaceEvents(current, (events) {
          events.removeWhere((e) => e is Map && e['icsSourceId'] == id);
        }),
        ..._changed(
          current,
          CalendarAlertsKeys.icsSubscriptions,
          jsonEncode(subscriptions),
        ),
      };
    },
    'setNotificationPrefs': (_, current, args) {
      final enabled = args['enabled'];
      final time = args['time'];
      final sound = args['sound'];
      if ((enabled != null && enabled is! bool) ||
          (time != null && time is! int) ||
          (sound != null && sound is! bool)) {
        throw const _InvalidCommand('prefs');
      }
      return {
        if (enabled != null)
          ..._changed(current, CalendarAlertsKeys.enabled, enabled),
        if (time != null) ..._changed(current, CalendarAlertsKeys.time, time),
        if (sound != null)
          ..._changed(current, CalendarAlertsKeys.sound, sound),
      };
    },
    'setZmanAlert': (_, current, args) {
      final timeId = _stringArg(args, 'timeId');
      final pref = args['pref'];
      final alerts = _decodeMap(current[CalendarAlertsKeys.zmanAlerts]);
      if (pref == null) {
        alerts.remove(timeId);
      } else {
        if (ZmanAlertPreference.fromJson(pref, fallbackName: timeId) == null) {
          throw const _InvalidCommand('pref');
        }
        alerts[timeId] = pref;
      }
      return _changed(
        current,
        CalendarAlertsKeys.zmanAlerts,
        jsonEncode(alerts),
      );
    },
    'setCity': (_, current, args) =>
        _changed(current, CalendarAlertsKeys.city, _stringArg(args, 'city')),
  };

  bool _pluginEventsChanged = false;

  Future<Map<String, Object?>> _applyState(
    Map<String, Object?>? Function(Map<String, Object?> current) mutate,
  ) => _inLane(() async {
    await _cleanupStoredPluginEvents();
    final current = await _store.readValues();
    _pluginEventsChanged = false;
    final changed = mutate(current) ?? const {};
    final pluginEventsChanged = _pluginEventsChanged;
    if (changed.isEmpty && !pluginEventsChanged) {
      return {
        'ok': true,
        ...CalendarAlertsUpdate(
          epoch: epoch,
          revision: _revision,
          values: current,
        ).toJson(),
      };
    }
    if (changed.isNotEmpty) {
      await _store.writeValues(changed);
      current.addAll(changed);
    }
    final update = _publish(current, pluginEventsChanged: pluginEventsChanged);
    _requestReconcile();
    return {'ok': true, ...update.toJson()};
  });

  Future<T> _inLane<T>(Future<T> Function() body) {
    final result = _lane.then((_) => body());
    _lane = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  CalendarAlertsUpdate _publish(
    Map<String, Object?> values, {
    bool pluginEventsChanged = false,
  }) {
    _revision++;
    final update = CalendarAlertsUpdate(
      epoch: epoch,
      revision: _revision,
      values: Map.unmodifiable(values),
      pluginEventsChanged: pluginEventsChanged,
    );
    _updates.add(update);
    _broadcast({'type': requestStateChanged, ...update.toJson()});
    return update;
  }

  /// אירועי תוספים נשמרו בעבר יחד עם אירועי המשתמש; הם נטענים מהמסד.
  Future<void> _cleanupStoredPluginEvents() async {
    if (_cleanedStoredEvents) return;
    _cleanedStoredEvents = true;
    final current = await _store.readValues();
    final changed = _replaceEvents(current, (_) {});
    if (changed == null) return;
    await _store.writeValues(changed);
    current.addAll(changed);
    _publish(current);
  }

  Map<String, Object?> _valueAck(Object? value) => {
    'ok': true,
    'epoch': epoch,
    'revision': _revision,
    'value': value,
  };

  Map<String, Object?> _errorAck(String error) => {
    'ok': false,
    'epoch': epoch,
    'revision': _revision,
    'error': error,
  };

  // ---------------------------------------------------------------------
  // הרשאות ותוספים
  // ---------------------------------------------------------------------

  Future<bool> _ensurePermission() async {
    final notifications = _notifications;
    if (!await notifications.ensureInitialized()) return false;
    if (await notifications.checkPermissions()) return true;
    return Platform.isMacOS
        ? notifications.forceRequestPermissions()
        : notifications.requestPermissions();
  }

  Future<Map<String, Object?>> _pluginShow(Map<String, Object?> args) async {
    final pluginId = _stringArg(args, 'pluginId');
    final id = _intArg(args, 'id');
    final ready = await _pluginReady();
    if (ready != null) return ready;
    await _notifications.showNotification(
      id: id,
      title: _stringArg(args, 'title'),
      body: _stringArg(args, 'body'),
    );
    await _trackPluginIds(pluginId, add: {id});
    return _valueAck({'id': id});
  }

  Future<Map<String, Object?>> _pluginSchedule(
    Map<String, Object?> args,
  ) async {
    final pluginId = _stringArg(args, 'pluginId');
    final id = _intArg(args, 'id');
    final at = DateTime.tryParse(_stringArg(args, 'at'));
    if (at == null) throw const _InvalidCommand('at');
    final ready = await _pluginReady();
    if (ready != null) return ready;
    await _notifications.cancelNotifications([id]);
    await _notifications.scheduleNotification(
      id: id,
      title: _stringArg(args, 'title'),
      body: _stringArg(args, 'body'),
      eventDate: at,
      reminderMinutes: 0,
    );
    await _trackPluginIds(pluginId, add: {id});
    return _valueAck({'id': id});
  }

  Future<Map<String, Object?>?> _pluginReady() async {
    if (!await _notifications.ensureInitialized()) {
      return _errorAck(
        'error.unavailable: Notification service not initialized',
      );
    }
    if (!_notifications.hasPermissions) {
      return _errorAck('error.forbidden: Notification permissions not granted');
    }
    return null;
  }

  Future<Map<String, Object?>> _pluginCancel(Map<String, Object?> args) async {
    final pluginId = _stringArg(args, 'pluginId');
    final id = _intArg(args, 'id');
    // ביטול שנכשל משאיר את המזהה ברישום, כדי שאפשר יהיה לנסות שוב.
    await _notifications.cancelNotifications([id]);
    await _trackPluginIds(pluginId, remove: {id});
    return _valueAck(true);
  }

  Future<Map<String, Object?>> _pluginCancelAll(
    Map<String, Object?> args,
  ) async {
    final pluginId = _stringArg(args, 'pluginId');
    final ids = await _inLane(() => _pluginIds.read(pluginId));
    if (ids.isEmpty) return _valueAck(true);
    await _notifications.cancelNotifications(ids);
    await _trackPluginIds(pluginId, remove: ids.toSet());
    return _valueAck(true);
  }

  /// read-modify-write של רישום התוסף בתור של הבעלים, כך ששני גשרים שרושמים
  /// במקביל אינם דורסים זה את זה.
  Future<void> _trackPluginIds(
    String pluginId, {
    Set<int> add = const {},
    Set<int> remove = const {},
  }) => _inLane(() async {
    final ids = [...await _pluginIds.read(pluginId)];
    final before = ids.length;
    ids.removeWhere(remove.contains);
    final removed = before != ids.length;
    var added = false;
    for (final id in add) {
      if (!ids.contains(id)) {
        ids.add(id);
        added = true;
      }
    }
    if (added || removed) await _pluginIds.write(pluginId, ids);
  });

  // ---------------------------------------------------------------------
  // התזמון
  // ---------------------------------------------------------------------

  void _requestReconcile() {
    _reconcileRequested = true;
    if (_reconcileRunning) return;
    _reconcileRunning = true;
    final idle = _idle = Completer<void>();
    unawaited(_runReconciler(idle));
  }

  Future<void> _runReconciler(Completer<void> idle) async {
    try {
      while (_reconcileRequested) {
        _reconcileRequested = false;
        final revision = _revision;
        try {
          await _reconcileOnce(revision);
        } catch (error, stackTrace) {
          NotificationService.logFailure(
            'תזמון התראות לוח השנה נכשל',
            error,
            stackTrace,
          );
          _reportStatus(revision, ok: false, failures: 1);
        }
        // שינוי שקרה תוך כדי הריצה מתוזמן בריצה נוספת על המצב החדש.
        if (_revision != revision) _reconcileRequested = true;
      }
    } finally {
      _reconcileRunning = false;
      idle.complete();
    }
  }

  Future<void> _reconcileOnce(int revision) async {
    final values = await _store.readValues();
    final plan = <int, PlannedAlert>{};
    final now = _now();
    final events = [
      ..._decodeEvents(values[CalendarAlertsKeys.events]),
      ...await _pluginEvents(),
    ];
    for (final alert in CalendarAlertPlanner.planEventReminders(
      events: events,
      enabled: values[CalendarAlertsKeys.enabled] == true,
      defaultMinutes: values[CalendarAlertsKeys.time] as int? ?? 60,
      soundEnabled: values[CalendarAlertsKeys.sound] != false,
      now: now,
    )) {
      plan[alert.id] = alert;
    }
    final zmanAlerts = _decodeZmanAlerts(values[CalendarAlertsKeys.zmanAlerts]);
    for (final alert in CalendarAlertPlanner.planZmanAlerts(
      alerts: zmanAlerts,
      city: values[CalendarAlertsKeys.city] as String? ?? 'ירושלים',
      now: now,
    )) {
      plan[alert.id] = alert;
      // חישוב זמני היום כבד; מפנים את ה-isolate בין יום ליום.
      await Future<void>.delayed(Duration.zero);
    }

    primeLedger();
    final previous = _ledger!;
    if (plan.isEmpty && previous.isEmpty) {
      _armDailyTimer(active: false);
      _reportStatus(revision, ok: true);
      return;
    }

    final notifications = _notifications;
    if (!await notifications.ensureInitialized()) {
      _reportStatus(revision, ok: false, failures: plan.length);
      return;
    }
    await _removeDuplicatesOnce({...previous, ...plan.keys});

    // הרישום נכתב לפני כל פעולה: קריסה באמצע לא תשאיר התראה שאין לבטל.
    final ahead = {...previous, ...plan.keys};
    if (!setEquals(ahead, previous)) await _writeLedger(ahead);

    final present = <int>{};
    var failures = 0;
    for (final id in previous.difference(plan.keys.toSet())) {
      try {
        await notifications.cancelNotifications([id]);
      } catch (error, stackTrace) {
        present.add(id);
        failures++;
        NotificationService.logFailure('ביטול התראה נכשל', error, stackTrace);
      }
    }
    final permitted = notifications.hasPermissions;
    if (!permitted) failures += plan.length;
    for (final alert in plan.values) {
      try {
        await notifications.cancelNotifications([alert.id]);
      } catch (error, stackTrace) {
        present.add(alert.id);
        failures++;
        NotificationService.logFailure('ביטול התראה נכשל', error, stackTrace);
        continue;
      }
      if (!permitted) continue;
      try {
        await notifications.scheduleNotification(
          id: alert.id,
          title: alert.title,
          body: alert.body,
          eventDate: alert.eventDate,
          reminderMinutes: alert.reminderMinutes,
          soundEnabled: alert.soundEnabled,
        );
        present.add(alert.id);
      } catch (error, stackTrace) {
        failures++;
        NotificationService.logFailure('תזמון התראה נכשל', error, stackTrace);
      }
    }
    await _writeLedger(present);
    _armDailyTimer(active: plan.isNotEmpty);
    _reportStatus(revision, ok: failures == 0, failures: failures);
  }

  Future<void> _writeLedger(Set<int> ids) async {
    _ledger = {...ids};
    await _store.writeLedger(ids.toList());
  }

  /// ב-Windows תזמון אינו דורס מופע קיים, ולכן גרסאות קודמות השאירו כפילויות.
  Future<void> _removeDuplicatesOnce(Set<int> ours) async {
    if (!_dedupeDuplicates || _dedupedPending) return;
    _dedupedPending = true;
    try {
      final counts = <int, int>{};
      for (final id in await _notifications.pendingNotificationIds()) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
      for (final entry in counts.entries) {
        if (entry.value < 2 || !ours.contains(entry.key)) continue;
        for (var i = 0; i < entry.value; i++) {
          await _notifications.cancelNotifications([entry.key]);
        }
      }
    } catch (error, stackTrace) {
      NotificationService.logFailure(
        'ניקוי התראות כפולות נכשל',
        error,
        stackTrace,
      );
    }
  }

  /// מאריך את החלון המתגלגל פעם ביום, כל עוד יש מה לתזמן.
  void _armDailyTimer({required bool active}) {
    _dailyTimer?.cancel();
    _dailyTimer = null;
    if (!active) return;
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 5);
    _dailyTimer = Timer(next.difference(now), _requestReconcile);
  }

  void _reportStatus(int revision, {required bool ok, int failures = 0}) {
    final status = CalendarScheduleStatus(
      epoch: epoch,
      revision: revision,
      ok: ok,
      failures: failures,
    );
    _statuses.add(status);
    _broadcast({'type': requestScheduleStatus, ...status.toJson()});
  }

  @visibleForTesting
  void dispose() {
    _dailyTimer?.cancel();
    unawaited(_updates.close());
    unawaited(_statuses.close());
  }

  // ---------------------------------------------------------------------
  // עזרי מצב
  // ---------------------------------------------------------------------

  static Object? _idOf(Object? item) => item is Map ? item['id'] : null;

  static List<Object?> _decodeList(Object? json) {
    if (json is! String) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return [...decoded];
    } catch (_) {}
    return [];
  }

  static Map<String, Object?> _decodeMap(Object? json) {
    if (json is! String) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return {};
  }

  static List<CustomEvent> _decodeEvents(Object? json) => [
    for (final item in _decodeList(json))
      if (item is Map && !'${item['id']}'.contains(':')) ?_tryParseEvent(item),
  ];

  static CustomEvent? _tryParseEvent(Map item) {
    try {
      return CustomEvent.fromJson(Map<String, dynamic>.from(item));
    } catch (_) {
      return null;
    }
  }

  static Map<String, ZmanAlertPreference> _decodeZmanAlerts(Object? json) => {
    for (final entry in _decodeMap(json).entries)
      entry.key: ?ZmanAlertPreference.fromJson(
        entry.value,
        fallbackName: entry.key,
      ),
  };

  /// מחיל [edit] על האירועים השמורים ומסיר אירועי תוספים. null = לא השתנה.
  static Map<String, Object?>? _replaceEvents(
    Map<String, Object?> current,
    void Function(List<Object?> events) edit,
  ) {
    final before = current[CalendarAlertsKeys.events];
    final events = _decodeList(before);
    edit(events);
    events.removeWhere((e) => e is Map && '${e['id']}'.contains(':'));
    final encoded = jsonEncode(events);
    return encoded == before || (before == null && events.isEmpty)
        ? null
        : {CalendarAlertsKeys.events: encoded};
  }

  static Map<String, Object?>? _upsertEvents(
    Map<String, Object?> current,
    List<Map<String, Object?>> updates,
  ) => _replaceEvents(current, (events) {
    for (final update in updates) {
      final index = events.indexWhere((e) => _idOf(e) == update['id']);
      if (index == -1) {
        events.add(update);
      } else {
        events[index] = update;
      }
    }
  });

  static Map<String, Object?> _changed(
    Map<String, Object?> current,
    String key,
    Object value,
  ) => current[key] == value ? const {} : {key: value};

  static Map<String, Object?> _eventArg(Object? json) {
    if (json is! Map) throw const _InvalidCommand('event');
    final event = Map<String, Object?>.from(json);
    final id = event['id'];
    if (id is! String || id.contains(':') || _tryParseEvent(event) == null) {
      throw const _InvalidCommand('event');
    }
    // הסבב ב-JSON מבטיח שמה שנשמר זהה למה שיישלח לחלונות.
    return Map<String, Object?>.from(jsonDecode(jsonEncode(event)) as Map);
  }

  static List<Map<String, Object?>> _eventsArg(Object? json) {
    if (json is! List) throw const _InvalidCommand('events');
    return [for (final event in json) _eventArg(event)];
  }

  static String _stringArg(Map<String, Object?> args, String name) {
    final value = args[name];
    if (value is! String) throw _InvalidCommand(name);
    return value;
  }

  static int _intArg(Map<String, Object?> args, String name) {
    final value = args[name];
    if (value is! int) throw _InvalidCommand(name);
    return value;
  }
}

class _InvalidCommand implements Exception {
  const _InvalidCommand(this.message);
  final String message;
}
