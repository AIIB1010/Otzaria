import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/adapters/plugin_calendar_adapter.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_planner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/calendar_alerts_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  var now = DateTime(2026, 10, 20, 9);
  late MemoryAlertsStore store;
  late WindowsLikeNotifications notifications;
  late List<CustomEvent> pluginEvents;
  late List<CalendarScheduleStatus> statuses;

  CalendarAlertsOwner owner({
    WindowsLikeNotifications? using,
    bool dedupe = false,
    bool crashes = false,
  }) {
    final created = CalendarAlertsOwner(
      store: store,
      notifications: using ?? notifications,
      pluginEvents: () async => pluginEvents,
      now: () => now,
      broadcast: (_) {},
      dedupeDuplicates: dedupe,
    );
    created.scheduleStatuses.listen(statuses.add);
    addTearDown(() async {
      // בעלים ש"קרס" נשאר באמצע ריצה לתמיד.
      if (!crashes) await created.idle;
      created.dispose();
    });
    return created;
  }

  Map<String, Object?> eventArgs(CustomEvent event) => {
    'event': jsonDecode(jsonEncode(event.toJson())),
  };

  /// מה שהתוכנית דורשת לפי המצב השמור עכשיו.
  Set<int> expectedPlan() {
    final events = [
      for (final item
          in jsonDecode(store.values[CalendarAlertsKeys.events] as String)
              as List)
        CustomEvent.fromJson(item as Map<String, dynamic>),
      ...pluginEvents,
    ];
    return {
      for (final alert in CalendarAlertPlanner.planEventReminders(
        events: events,
        enabled: store.values[CalendarAlertsKeys.enabled] == true,
        defaultMinutes: store.values[CalendarAlertsKeys.time] as int,
        soundEnabled: true,
        now: now,
      ))
        alert.id,
    };
  }

  setUp(() {
    now = DateTime(2026, 10, 20, 9);
    store = MemoryAlertsStore();
    notifications = WindowsLikeNotifications();
    pluginEvents = [];
    statuses = [];
  });

  test('תזכורת לאירוע חדש מתוזמנת, ומחיקה מבטלת אותה', () async {
    final o = owner();

    final ack = await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    expect(ack['ok'], isTrue);
    expect(notifications.present, {reminderId('a')});
    expect(store.ledger, [reminderId('a')]);

    await o.execute('deleteEvent', {'id': 'a'});
    await o.idle;
    expect(notifications.present, isEmpty);
    expect(store.ledger, isEmpty);
    expect(statuses.last.ok, isTrue);
  });

  test('חלון זמני היום מתארך כשהבעלים מתזמן ביום הבא', () async {
    store.values[CalendarAlertsKeys.zmanAlerts] = jsonEncode({
      'sunrise': const ZmanAlertPreference(
        minutesBefore: 15,
        displayName: 'הנץ',
      ).toJson(),
    });
    now = DateTime(2026, 10, 20, 0, 1);
    final o = owner();
    await o.restoreIfNeeded();
    final firstDay = CalendarAlertPlanner.zmanNotificationId(
      'sunrise',
      DateTime(2026, 10, 20),
    );
    expect(notifications.present, hasLength(46));
    expect(notifications.present, contains(firstDay));

    now = DateTime(2026, 10, 21, 0, 1);
    await o.restoreIfNeeded();

    expect(notifications.everyIdAtMostOnce, isTrue);
    expect(notifications.present, hasLength(46));
    expect(notifications.present, isNot(contains(firstDay)));
    expect(
      notifications.present,
      contains(
        CalendarAlertPlanner.zmanNotificationId(
          'sunrise',
          DateTime(2026, 12, 5),
        ),
      ),
    );
  });

  test('תזמון שנכשל אינו נרשם, והכשל מדווח בנפרד מהאישור', () async {
    notifications.failingIds.add(reminderId('a'));
    final o = owner();

    final ack = await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.execute('upsertEvent', eventArgs(futureEvent('b')));
    await o.idle;

    expect(ack['ok'], isTrue);
    expect(store.ledger, [reminderId('b')]);
    expect(statuses.last.ok, isFalse);
  });

  test('אירוע תוסף אינו נשמר באירועי המשתמש', () async {
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('u').toJson(),
      futureEvent('plugin:k').toJson(),
    ]);
    final o = owner();

    final rejected = await o.execute(
      'upsertEvent',
      eventArgs(futureEvent('plugin:x')),
    );
    await o.execute('snapshot', const {});

    expect(rejected['ok'], isFalse);
    final stored =
        jsonDecode(store.values[CalendarAlertsKeys.events] as String) as List;
    expect(stored.map((e) => (e as Map)['id']), ['u']);
  });

  test('אירועי תוספים מתוזמנים כולם, בלי תלות ב-scope', () async {
    final adapter = PluginCalendarAdapter(
      recordsLoader: (_) async => [
        for (final scope in ['global', 'workspace:w', 'book:b'])
          {
            'plugin_id': 'p',
            'key': scope,
            'scope': scope,
            'payload_json': jsonEncode({
              'title': scope,
              'startsAt': '2026-10-25T18:00:00',
            }),
          },
      ],
    );
    pluginEvents = await adapter.loadAllPluginEvents();
    final shown = await adapter.loadAndMergePluginEvents(const []);
    final o = owner();

    await o.restoreIfNeeded();

    expect(shown.map((e) => e.id), ['p:global']);
    expect(notifications.present, {
      for (final scope in ['global', 'workspace:w', 'book:b'])
        reminderId('p:$scope'),
    });
  });

  test('ב-Windows כפילויות של מזהים שלנו נמחקות פעם אחת', () async {
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('a').toJson(),
    ]);
    store.ledger = [reminderId('a'), 77];
    notifications.counts.addAll({reminderId('a'): 2, 77: 3, 99: 2});
    final o = owner(dedupe: true);

    await o.restoreIfNeeded();

    expect(notifications.counts[reminderId('a')], 1);
    expect(notifications.counts[77], 0);
    // מזהה שאינו שלנו (למשל של תוסף) אינו נוגע.
    expect(notifications.counts[99], 2);
    expect(store.ledger, [reminderId('a')]);
  });

  test('קריסה באמצע ריצה אינה משאירה התראה שאין לבטל', () async {
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('a').toJson(),
      futureEvent('b').toJson(),
    ]);
    store.ledger = [5];
    notifications.counts[5] = 1;
    final crashed = Completer<void>();
    notifications.onSchedule = (call) {
      if (call == 2) {
        notifications.scheduleGate = Completer<void>();
        crashed.complete();
      }
    };
    unawaited(owner(crashes: true).restoreIfNeeded());
    await crashed.future;
    await pumpEventQueue();

    // הרישום נכתב לפני כל פעולה במערכת, ולכן מכסה את כל מה שקיים בה.
    expect(store.ledgerWrites.first.toSet(), {
      5,
      reminderId('a'),
      reminderId('b'),
    });
    expect(store.ledger.toSet().containsAll(notifications.present), isTrue);

    // הפעלה חדשה: האירוע b נמחק בינתיים.
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('a').toJson(),
    ]);
    final restarted = WindowsLikeNotifications()
      ..counts.addAll(notifications.counts);
    await owner(using: restarted).restoreIfNeeded();

    expect(restarted.everyIdAtMostOnce, isTrue);
    expect(restarted.present, {reminderId('a')});
    expect(store.ledger, [reminderId('a')]);
  });

  test('בלי מה לתזמן או לבטל — אין אתחול נייטיבי', () async {
    final o = owner();

    await o.restoreIfNeeded();
    await o.execute('snapshot', const {});
    await o.execute('setNotificationPrefs', {'time': 15});
    await o.execute('setCity', {'city': 'חיפה'});
    await o.idle;

    expect(notifications.initCalls, 0);
  });

  test('שער עלייה תקוע: האישור חוזר מיד, והתזמון קורה פעם אחת אחריו', () async {
    notifications.initGate = Completer<void>();
    final o = owner();

    final ack = await o
        .execute('upsertEvent', eventArgs(futureEvent('a')))
        .timeout(const Duration(seconds: 2));
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await pumpEventQueue();
    expect(ack['ok'], isTrue);
    expect(notifications.scheduled, isEmpty);

    notifications.initGate!.complete();
    await o.idle;

    expect(
      notifications.scheduled.where((s) => s.id == reminderId('a')),
      hasLength(1),
    );
  });

  test(
    'בכל שזירה של פקודות כל מזהה קיים פעם אחת והרישום שווה לתוכנית',
    () async {
      for (var seed = 0; seed < 25; seed++) {
        store = MemoryAlertsStore({
          CalendarAlertsKeys.events: jsonEncode([
            for (final id in ['a', 'b', 'c']) futureEvent(id).toJson(),
          ]),
        });
        notifications = WindowsLikeNotifications();
        final random = Random(seed);
        final o = owner();
        // העלייה כבר תזמנה את המצב השמור.
        await o.restoreIfNeeded();
        final pending = <Future<Object?>>[];

        Future<Object?> randomCommand() {
          final id = ['a', 'b', 'c', 'd', 'e'][random.nextInt(5)];
          return switch (random.nextInt(4)) {
            0 => o.execute('deleteEvent', {'id': id}),
            1 => o.execute('setNotificationPrefs', {
              'enabled': random.nextInt(4) != 0,
            }),
            2 => o.execute('setNotificationPrefs', {
              'time': 10 + random.nextInt(50),
            }),
            _ => o.execute(
              'upsertEvent',
              eventArgs(futureEvent(id, day: 22 + random.nextInt(6))),
            ),
          };
        }

        // פקודות מגיעות גם באמצע ביטול ותזמון.
        notifications.onSchedule = (_) {
          if (random.nextInt(3) == 0) pending.add(randomCommand());
        };
        for (var i = 0; i < 6; i++) {
          pending.add(randomCommand());
        }
        while (pending.isNotEmpty) {
          await pending.removeLast();
        }
        await o.idle;
        notifications.onSchedule = null;

        expect(notifications.everyIdAtMostOnce, isTrue, reason: 'seed $seed');
        expect(notifications.present, expectedPlan(), reason: 'seed $seed');
        expect(store.ledger.toSet(), expectedPlan(), reason: 'seed $seed');
      }
    },
  );

  group('לקוח בחלון הבעלים', () {
    test('עדכון ישן נזרק', () async {
      final client = LocalCalendarAlertsClient(owner());
      final seen = <int>[];
      client.updates.listen((u) => seen.add(u.revision));
      const epoch = 'e';

      expect(
        await client.accept(
          const CalendarAlertsUpdate(epoch: epoch, revision: 5, values: {}),
        ),
        isTrue,
      );
      expect(
        await client.accept(
          const CalendarAlertsUpdate(epoch: epoch, revision: 3, values: {}),
        ),
        isFalse,
      );
      expect(seen, [5]);
      expect(client.appliedRevision, 5);
    });
  });

  group('NotificationService אמיתי', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    final service = NotificationService();

    setUpAll(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      FlutterLocalNotificationsPlatform.instance =
          MacOSFlutterLocalNotificationsPlugin();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDownAll(() {
      debugDefaultTargetPlatformOverride = null;
      NotificationService.startupGate = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    setUp(() {
      service.resetForTesting();
      calls.clear();
    });

    test('אין initialize לפני שער החשיפה, ואחריו בדיוק אחד', () async {
      final reveal = Completer<void>();
      NotificationService.startupGate = () => reveal.future;
      final o = CalendarAlertsOwner(
        store: store,
        notifications: service,
        pluginEvents: () async => const [],
        now: () => now,
        broadcast: (_) {},
        dedupeDuplicates: false,
      );
      addTearDown(o.dispose);

      final ack = await o.execute('upsertEvent', eventArgs(futureEvent('a')));
      await o.execute('upsertEvent', eventArgs(futureEvent('b')));
      await pumpEventQueue();
      expect(ack['ok'], isTrue);
      expect(calls, isEmpty);

      reveal.complete();
      await o.idle;
      final methods = calls.map((c) => c.method).toList();
      expect(methods.where((m) => m == 'initialize'), hasLength(1));
      expect(methods.where((m) => m == 'zonedSchedule'), hasLength(2));
      expect(store.ledger.toSet(), {reminderId('a'), reminderId('b')});
    });
  });
}
