import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// מספר הבנייה של ה-APK הזה (מספר הריצה ב-CI); 0 בבנייה מקומית.
const int kLvBuildNumber = int.fromEnvironment('LV_BUILD');

/// ה-release שה-CI מעדכן בכל בנייה תקינה של ענף HumanWare.
const String kLvReleaseApi =
    'https://api.github.com/repos/AIIB1010/Otzaria/releases/tags/humanware-latest';

class LvUpdateInfo {
  const LvUpdateInfo({required this.build, required this.url, this.sizeBytes});

  final int build;
  final String url;
  final int? sizeBytes;

  bool isNewerThan(int current) => build > current;
}

/// תוצאת בקשת ההתקנה מהמתקין של Android.
enum LvInstallResult { started, needsPermission }

/// מה שנקרא מתוך קובץ APK בלי להתקין אותו.
class LvApkInfo {
  const LvApkInfo({
    required this.packageName,
    required this.versionCode,
    required this.ownPackage,
  });

  final String packageName;
  final int versionCode;
  final String ownPackage;

  /// האם זה קובץ של האפליקציה הזו.
  bool get isOurs => packageName == ownPackage;

  /// מספר הבנייה: `versionCode` הוא 100000 ועוד מספר הריצה ב-CI.
  int get build => versionCode - kLvVersionCodeBase;
}

/// ראו `--build-number` ב-workflow.
const int kLvVersionCodeBase = 100000;

class LvUpdateException implements Exception {
  const LvUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// בודק אם יש בנייה חדשה ב-GitHub, מוריד אותה ומפעיל את מתקין Android.
class LvUpdateService {
  LvUpdateService({
    http.Client? client,
    MethodChannel? channel,
    Future<Directory> Function()? cacheDir,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _channel =
           channel ??
           const MethodChannel('org.otzaria.humanware/apk_installer'),
       _cacheDir = cacheDir ?? getTemporaryDirectory;

  final http.Client _client;
  final MethodChannel _channel;
  final Future<Directory> Function() _cacheDir;
  final Duration requestTimeout;

  /// הבנייה האחרונה שפורסמה, או null כשעדיין לא פורסמה אף אחת.
  Future<LvUpdateInfo?> fetchLatest() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse(kLvReleaseApi),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const LvUpdateException(
        'אין תשובה מהשרת. בדקו את החיבור לאינטרנט.',
      );
    } on SocketException {
      throw const LvUpdateException('אין חיבור לאינטרנט.');
    } on http.ClientException {
      throw const LvUpdateException('אין חיבור לאינטרנט.');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw LvUpdateException('השרת החזיר שגיאה (${response.statusCode}).');
    }
    return parseRelease(utf8.decode(response.bodyBytes));
  }

  /// מפענח את תשובת GitHub. מחזיר null כשחסר מספר בנייה או קובץ APK.
  static LvUpdateInfo? parseRelease(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;
    final notes = json['body'] as String? ?? '';
    final build = RegExp(r'build:\s*(\d+)').firstMatch(notes)?.group(1);
    if (build == null) return null;
    for (final asset in (json['assets'] as List? ?? const [])) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String?;
      if (name.endsWith('.apk') && url != null) {
        return LvUpdateInfo(
          build: int.parse(build),
          url: url,
          sizeBytes: (asset['size'] as num?)?.toInt(),
        );
      }
    }
    return null;
  }

  /// מוריד את ה-APK לתיקיית המטמון, ומדווח התקדמות בין 0 ל-1.
  Future<File> download(
    LvUpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/otzaria-humanware-update.apk');
    final sink = file.openWrite();
    try {
      final response = await _client
          .send(http.Request('GET', Uri.parse(info.url)))
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw LvUpdateException('ההורדה נכשלה (${response.statusCode}).');
      }
      final total = response.contentLength ?? info.sizeBytes;
      var received = 0;
      // timeout על כל חתיכה: חיבור שנתקע באמצע לא יתלה את המסך.
      await for (final chunk in response.stream.timeout(requestTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } on TimeoutException {
      throw const LvUpdateException('ההורדה נתקעה. נסו שוב.');
    } on SocketException {
      throw const LvUpdateException('החיבור לאינטרנט נותק באמצע ההורדה.');
    } on http.ClientException {
      throw const LvUpdateException('החיבור לאינטרנט נותק באמצע ההורדה.');
    } finally {
      await sink.close();
    }
    return file;
  }

  /// קורא את שם החבילה והגרסה של [apk]. זורק [LvUpdateException] אם אינו APK.
  Future<LvApkInfo> inspect(File apk) async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('inspect', {
        'path': apk.path,
      });
      return LvApkInfo(
        packageName: map?['packageName'] as String? ?? '',
        versionCode: (map?['versionCode'] as num?)?.toInt() ?? 0,
        ownPackage: map?['ownPackage'] as String? ?? '',
      );
    } on PlatformException catch (error) {
      throw LvUpdateException(error.message ?? 'הקובץ אינו קובץ התקנה תקין.');
    } on MissingPluginException {
      throw const LvUpdateException('עדכון מתוך האפליקציה זמין רק באנדרואיד.');
    }
  }

  Future<LvInstallResult> install(File apk) async {
    try {
      final result = await _channel.invokeMethod<String>('install', {
        'path': apk.path,
      });
      return result == 'needs_permission'
          ? LvInstallResult.needsPermission
          : LvInstallResult.started;
    } on PlatformException catch (error) {
      throw LvUpdateException(error.message ?? 'ההתקנה נכשלה.');
    } on MissingPluginException {
      throw const LvUpdateException('עדכון מתוך האפליקציה זמין רק באנדרואיד.');
    }
  }

  void dispose() => _client.close();
}
