import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// מגרסה זו `network.localhost` ו-`network.access` נפרדות לחלוטין: יעד מקומי
/// דורש `network.localhost` בלבד, ויעד באינטרנט דורש `network.access` בלבד.
const String pluginStrictNetworkPermissionsVersion = '0.9.99';

/// האם [version] היא גרסה שבה ההרשאות נפרדות לחלוטין.
///
/// באכיפה בזמן ריצה [version] היא גרסת האפליקציה: משם והלאה תוסף שהצהיר רק על
/// `network.access` אינו מגיע לשירות מקומי, ותוסף שהצהיר רק על
/// `network.localhost` אינו מגיע לאינטרנט — בלי קשר ל-`minAppVersion` שלו.
/// בוולידטור [version] היא `minAppVersion` של התוסף: תוסף שדורש את הגרסה הזו
/// ומעלה חייב להצהיר נכון כבר באריזה.
///
/// גרסה לא חוקית: ב-`minAppVersion` של תוסף היא נחשבת ישנה, כי הוולידציה של
/// המניפסט תופסת אותה ([invalidIsStrict] כבוי). בגרסת האפליקציה היא נחשבת
/// מלאה ([invalidIsStrict] דלוק): כשל סגור, כדי שלא תורחב הרשאה.
bool pluginUsesStrictNetworkPermissions(
  String version, {
  bool invalidIsStrict = false,
}) {
  try {
    return PluginVersionUtils.compareCoreVersions(
          version,
          pluginStrictNetworkPermissionsVersion,
        ) >=
        0;
  } on PluginVersionFormatException {
    return invalidIsStrict;
  }
}

/// ההרשאות שכל אחת מהן מספיקה כדי לפנות אל [uri].
///
/// יעד אינטרנט: `network.access` בלבד, תמיד. יעד מקומי: `network.localhost`,
/// ובתקופת המעבר ([strict] כבוי) גם `network.access` — כדי שתוסף שהצהיר על
/// גישה לאינטרנט לשם פנייה לשירות מקומי לא יישבר לפני שיספיק להתעדכן.
Set<String> acceptedNetworkPermissionsFor(Uri uri, {required bool strict}) {
  final required = requiredNetworkPermissionFor(uri);
  if (strict || required == 'network.access') return {required};
  return {required, 'network.access'};
}

/// האם גרסת האפליקציה הנוכחית אוכפת הפרדה מלאה בין הרשאות הרשת.
///
/// הגרסה נקראת פעם אחת. אם אי-אפשר לקרוא אותה ההפרדה מלאה (כשל סגור), כדי
/// ששגיאת קריאה לא תרחיב הרשאות.
class PluginNetworkPermissionMode {
  PluginNetworkPermissionMode._();

  static Future<bool>? _strict;

  static Future<bool> isStrict() => _strict ??= _resolve();

  static Future<bool> _resolve() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return pluginUsesStrictNetworkPermissions(
        appReleaseVersion(info),
        invalidIsStrict: true,
      );
    } catch (_) {
      return true;
    }
  }

  /// קובע גרסת אפליקציה מדומה; `null` מחזיר לקריאה האמיתית.
  @visibleForTesting
  static void debugSetAppVersion(String? version) {
    _strict = version == null
        ? null
        : Future.value(
            pluginUsesStrictNetworkPermissions(version, invalidIsStrict: true),
          );
  }
}
