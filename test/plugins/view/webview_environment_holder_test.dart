import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null));

  group('WebViewEnvironmentHolder.isRuntimeAvailable', () {
    test('override true → מחזיר true', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(true);
      expect(await WebViewEnvironmentHolder.isRuntimeAvailable(), isTrue);
    });

    test('override false → מחזיר false', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      expect(await WebViewEnvironmentHolder.isRuntimeAvailable(), isFalse);
    });

    test('איפוס override מחזיר את הבדיקה להתנהגות הרגילה', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
      // ללא override, על פלטפורמה שאינה Windows התוצאה היא true; ב-Windows
      // ללא platform channel הקריאה נכשלת ומוחזר false. בשני המקרים אסור
      // שהקריאה תזרוק חריגה.
      await expectLater(
        WebViewEnvironmentHolder.isRuntimeAvailable(),
        completes,
      );
    });
  });

  group('WebViewEnvironmentHolder.prewarm', () {
    late List<WebViewEnvironmentSettings> calls;
    final dataRoot = p.join('C:', 'app-data');

    setUp(() {
      calls = [];
      AppPaths.debugOverrideDataRootPath(dataRoot);
      WebViewEnvironmentHolder.debugOverridePrewarm((settings) async {
        calls.add(settings);
      });
    });

    tearDown(() {
      WebViewEnvironmentHolder.debugOverridePrewarm(null);
      AppPaths.debugOverrideDataRootPath(null);
    });

    test('skips the native call when no plugin is enabled', () async {
      final ran = await WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => false,
      );

      expect(ran, isFalse);
      expect(calls, isEmpty);
    });

    test('uses the settings of the real environment', () async {
      final ran = await WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () async => true,
      );

      expect(ran, isTrue);
      expect(
        calls.single.toMap(),
        WebViewEnvironmentHolder.debugEnvironmentSettings(
          p.join(dataRoot, 'webview2'),
        ).toMap(),
      );
    });
  });

  group('WebViewEnvironmentHolder environment settings', () {
    test('uses the requested user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.userDataFolder, r'C:\app-data\webview2');
    });

    test('requires exclusive access to the user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.exclusiveUserDataFolderAccess, isTrue);
    });

    test('registers the plugin asset scheme as a secure origin', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      final registration = settings.customSchemeRegistrations!.single;
      expect(registration.scheme, pluginAssetScheme);
      expect(registration.treatAsSecure, isTrue);
      expect(registration.hasAuthorityComponent, isTrue);
    });
  });
}
