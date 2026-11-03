import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    await pumpLowVision(tester, LvSettingsScreen(updateService: service));
    await tester.pump();

    await tester.ensureVisible(find.text('בדוק אם יש גרסה חדשה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בדוק אם יש גרסה חדשה'));
    await tester.pumpAndSettle();

    expect(find.textContaining('יש גרסה חדשה: 12'), findsOneWidget);
    expect(find.text('עדכן עכשיו'), findsOneWidget);
  });
}
