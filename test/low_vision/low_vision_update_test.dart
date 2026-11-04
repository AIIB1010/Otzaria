import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/low_vision/update/lv_update_controller.dart';
import 'package:otzaria/low_vision/update/lv_update_service.dart';
import 'package:otzaria/low_vision/view/lv_settings_screen.dart';

import 'low_vision_test_harness.dart';

String _release({String body = 'build: 12', bool withApk = true}) =>
    jsonEncode({
      'body': body,
      'assets': [
        if (withApk)
          {
            'name': 'otzaria-humanware.apk',
            'browser_download_url': 'https://example.test/app.apk',
            'size': 4,
          },
      ],
    });

void main() {
  group('LvUpdateService', () {
    test('מפענח מספר בנייה וכתובת הורדה', () {
      final info = LvUpdateService.parseRelease(_release())!;
      expect(info.build, 12);
      expect(info.url, 'https://example.test/app.apk');
      expect(info.isNewerThan(11), isTrue);
      expect(info.isNewerThan(12), isFalse);
    });

    test('release בלי מספר בנייה או בלי APK אינו עדכון', () {
      expect(LvUpdateService.parseRelease(_release(body: 'hello')), isNull);
      expect(LvUpdateService.parseRelease(_release(withApk: false)), isNull);
    });

    test('404 פירושו שעדיין לא פורסמה גרסה', () async {
      final service = LvUpdateService(
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      expect(await service.fetchLatest(), isNull);
    });

    test('שגיאת שרת וחוסר רשת מדווחים בעברית', () async {
      final server = LvUpdateService(
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(server.fetchLatest(), throwsA(isA<LvUpdateException>()));

      final offline = LvUpdateService(
        client: MockClient((_) async => throw const SocketException('x')),
      );
      expect(
        offline.fetchLatest(),
        throwsA(
          isA<LvUpdateException>().having(
            (e) => e.message,
            'message',
            contains('אינטרנט'),
          ),
        ),
      );
    });

    test('מוריד את הקובץ ומדווח התקדמות', () async {
      final dir = Directory.systemTemp.createTempSync('lv_update_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final service = LvUpdateService(
        client: MockClient.streaming((request, _) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
            contentLength: 4,
          );
        }),
        cacheDir: () async => dir,
      );
      final progress = <double>[];
      final file = await service.download(
        const LvUpdateInfo(build: 1, url: 'https://example.test/app.apk'),
        onProgress: progress.add,
      );
      expect(file.readAsBytesSync(), [1, 2, 3, 4]);
      expect(progress.last, 1.0);
    });

    group('הורדה שמתנתקת באמצע (מסך כבוי)', () {
      const info = LvUpdateInfo(build: 1, url: 'https://example.test/a.apk');
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('lv_update_drop'));
      tearDown(() => dir.deleteSync(recursive: true));

      LvUpdateService serviceFor(
        Future<http.StreamedResponse> Function(http.BaseRequest) handler, {
        MethodChannel? channel,
        int maxRetries = 40,
      }) => LvUpdateService(
        client: MockClient.streaming((request, _) => handler(request)),
        channel: channel,
        cacheDir: () async => dir,
        retryDelay: Duration.zero,
        maxRetries: maxRetries,
      );

      test('ממשיכה מאותה נקודה אחרי ניתוק', () async {
        final ranges = <String?>[];
        final service = serviceFor((request) async {
          ranges.add(request.headers['Range']);
          if (ranges.length == 1) {
            return http.StreamedResponse(
              Stream<List<int>>.multi((c) {
                c.add([1, 2]);
                c.addError(const SocketException('reset'));
                c.close();
              }),
              200,
              contentLength: 4,
            );
          }
          return http.StreamedResponse(
            Stream.value([3, 4]),
            206,
            contentLength: 2,
          );
        });
        final file = await service.download(info);
        expect(file.readAsBytesSync(), [1, 2, 3, 4]);
        expect(ranges, [null, 'bytes=2-']);
      });

      test('שרת שמתעלם מ-Range שולח הכול מחדש', () async {
        var calls = 0;
        final service = serviceFor((request) async {
          calls++;
          if (calls == 1) {
            return http.StreamedResponse(
              Stream<List<int>>.multi((c) {
                c.add([1, 2]);
                c.addError(const SocketException('reset'));
                c.close();
              }),
              200,
              contentLength: 4,
            );
          }
          return http.StreamedResponse(
            Stream.value([1, 2, 3, 4]),
            200,
            contentLength: 4,
          );
        });
        final file = await service.download(info);
        expect(file.readAsBytesSync(), [1, 2, 3, 4]);
      });

      test('נכשלת אחרי יותר מדי ניסיונות בלי התקדמות', () async {
        var calls = 0;
        final service = serviceFor((request) async {
          calls++;
          throw const SocketException('offline');
        }, maxRetries: 3);
        await expectLater(
          service.download(info),
          throwsA(isA<LvUpdateException>()),
        );
        expect(calls, 4);
      });

      test('נועלת את המעבד בזמן ההורדה ומשחררת בסופה', () async {
        const channel = MethodChannel('lv_test_keep_awake');
        final calls = <bool>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add((call.arguments as Map)['enabled'] as bool);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final service = serviceFor((request) async {
          return http.StreamedResponse(
            Stream.value([1]),
            200,
            contentLength: 1,
          );
        }, channel: channel);
        await service.download(info);
        expect(calls, [true, false]);
      });
    });

    test('מתקין דרך הערוץ, ומזהה בקשת הרשאה', () async {
      const channel = MethodChannel('lv_test_installer');
      var answer = 'started';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => answer);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = LvUpdateService(channel: channel);
      final apk = File('${Directory.systemTemp.path}/x.apk');
      expect(await service.install(apk), LvInstallResult.started);
      answer = 'needs_permission';
      expect(await service.install(apk), LvInstallResult.needsPermission);
    });
  });

  testWidgets('בהגדרות: בדיקה מציגה שיש גרסה חדשה וכפתור עדכון', (
    tester,
  ) async {
    final service = LvUpdateService(
      client: MockClient((_) async => http.Response(_release(), 200)),
    );
    await pumpLowVision(
      tester,
      const LvSettingsScreen(),
      updates: LvUpdateController(service: service),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.text('בדוק אם יש גרסה חדשה (דורש אינטרנט)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('בדוק אם יש גרסה חדשה (דורש אינטרנט)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('יש גרסה חדשה: 12'), findsOneWidget);
    expect(find.text('עדכן עכשיו'), findsOneWidget);
  });

  test('הורדה ממשיכה ומסתיימת גם כשאף מסך לא מאזין לה', () async {
    final dir = Directory.systemTemp.createTempSync('lv_update_bg');
    addTearDown(() => dir.deleteSync(recursive: true));
    final body = StreamController<List<int>>();
    const channel = MethodChannel('lv_test_installer_bg');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'started');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final controller = LvUpdateController(
      service: LvUpdateService(
        channel: channel,
        cacheDir: () async => dir,
        client: MockClient.streaming((request, _) async {
          if (request.url.host == 'api.github.com') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(_release())),
              200,
            );
          }
          return http.StreamedResponse(body.stream, 200, contentLength: 4);
        }),
      ),
    );
    await controller.check();
    expect(controller.state.value.status, LvUpdateStatus.available);

    final done = controller.update();
    body.add([1, 2]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.value.status, LvUpdateStatus.downloading);
    expect(controller.state.value.progress, 0.5);

    // בדיקה נוספת של "check" באמצע הורדה: מתעלמים ממנה, לא מבטלים.
    await controller.check();
    expect(controller.state.value.status, LvUpdateStatus.downloading);

    body.add([3, 4]);
    await body.close();
    await done;
    expect(controller.state.value.status, LvUpdateStatus.waitingForInstaller);
  });

  group('עדכון מקובץ (בלי אינטרנט)', () {
    LvUpdateController make({
      required Map<String, Object?>? inspectResult,
      required List<String> calls,
      File? picked,
      int installedBuild = 12,
      String installAnswer = 'started',
    }) {
      const channel = MethodChannel('lv_test_local_update');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'inspect') {
              if (inspectResult == null) {
                throw PlatformException(
                  code: 'not_apk',
                  message: 'לא קובץ התקנה',
                );
              }
              return inspectResult;
            }
            return installAnswer;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      return LvUpdateController(
        service: LvUpdateService(channel: channel),
        pickApk: () async => picked,
        installedBuild: installedBuild,
      );
    }

    Map<String, Object?> apk({
      int code = 100020,
      String pkg = 'org.otzaria.humanware',
    }) => {
      'packageName': pkg,
      'versionCode': code,
      'versionName': '1.0',
      'ownPackage': 'org.otzaria.humanware',
    };

    final file = File('${Directory.systemTemp.path}/x.apk');

    test(
      'קובץ חדש יותר של האפליקציה מוכן להתקנה, ומותקן על גבי הקיימת',
      () async {
        final calls = <String>[];
        final c = make(inspectResult: apk(), calls: calls, picked: file);
        await c.pickLocalFile();
        expect(c.state.value.status, LvUpdateStatus.localReady);
        expect(c.state.value.localBuild, 20);

        await c.installLocalFile();
        expect(c.state.value.status, LvUpdateStatus.waitingForInstaller);
        expect(calls, ['inspect', 'install']);
      },
    );

    test('קובץ ישן או זהה אינו מותקן', () async {
      for (final code in [100012, 100005]) {
        final c = make(
          inspectResult: apk(code: code),
          calls: [],
          picked: file,
        );
        await c.pickLocalFile();
        expect(c.state.value.status, LvUpdateStatus.localNotNewer);
        await c.installLocalFile();
        expect(c.state.value.status, LvUpdateStatus.localNotNewer);
      }
    });

    test('קובץ של אפליקציה אחרת נדחה', () async {
      final c = make(
        inspectResult: apk(pkg: 'com.example.other'),
        calls: [],
        picked: file,
      );
      await c.pickLocalFile();
      expect(c.state.value.status, LvUpdateStatus.error);
      expect(c.state.value.error, contains('אינו של אוצריא'));
    });

    test('קובץ שאינו APK מדווח שגיאה בעברית', () async {
      final c = make(inspectResult: null, calls: [], picked: file);
      await c.pickLocalFile();
      expect(c.state.value.status, LvUpdateStatus.error);
      expect(c.state.value.error, contains('לא קובץ התקנה'));
    });

    test('ביטול הבחירה חוזר למצב ההתחלתי', () async {
      final c = make(inspectResult: apk(), calls: [], picked: null);
      await c.pickLocalFile();
      expect(c.state.value.status, LvUpdateStatus.idle);
    });

    test('באנדרואיד 8+ בלי אישור התקנה מבקש אישור ואז אפשר להמשיך', () async {
      final c = make(
        inspectResult: apk(),
        calls: [],
        picked: file,
        installAnswer: 'needs_permission',
      );
      await c.pickLocalFile();
      await c.installLocalFile();
      expect(c.state.value.status, LvUpdateStatus.needsPermission);
      expect(c.state.value.localApk, isNotNull);
    });
  });

  testWidgets('בהגדרות: כפתור עדכון מקובץ מציג גרסה ומתקין', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel('lv_test_local_ui');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'inspect'
              ? {
                  'packageName': 'org.otzaria.humanware',
                  'versionCode': 100030,
                  'versionName': '1',
                  'ownPackage': 'org.otzaria.humanware',
                }
              : 'started';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await pumpLowVision(
      tester,
      const LvSettingsScreen(),
      updates: LvUpdateController(
        service: LvUpdateService(channel: channel),
        pickApk: () async => File('${Directory.systemTemp.path}/y.apk'),
        installedBuild: 14,
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.textContaining('עדכון מקובץ'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('עדכון מקובץ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('גרסה 30'), findsOneWidget);

    await tester.ensureVisible(find.text('התקן את הקובץ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('התקן את הקובץ'));
    await tester.pumpAndSettle();
    expect(calls, ['inspect', 'install']);
    expect(find.textContaining('אשרו את ההתקנה'), findsOneWidget);
  });
}
