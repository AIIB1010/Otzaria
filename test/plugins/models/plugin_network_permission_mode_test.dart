import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_network_permission_mode.dart';

void main() {
  tearDown(() => PluginNetworkPermissionMode.debugSetAppVersion(null));

  group('pluginUsesStrictNetworkPermissions', () {
    test('הפרדה מלאה רק מ-0.9.99', () {
      expect(pluginUsesStrictNetworkPermissions('0.0.0'), isFalse);
      expect(pluginUsesStrictNetworkPermissions('0.9.98'), isFalse);
      expect(pluginUsesStrictNetworkPermissions('0.9.98+99800'), isFalse);
      expect(pluginUsesStrictNetworkPermissions('0.9.99'), isTrue);
      expect(pluginUsesStrictNetworkPermissions('0.9.99+99900'), isTrue);
      expect(pluginUsesStrictNetworkPermissions('0.10.0'), isTrue);
      expect(pluginUsesStrictNetworkPermissions('1.0.0'), isTrue);
    });

    test('minAppVersion לא חוקי נחשב ישן; בגרסת אפליקציה — מלא', () {
      expect(pluginUsesStrictNetworkPermissions(''), isFalse);
      expect(pluginUsesStrictNetworkPermissions('abc'), isFalse);
      expect(
        pluginUsesStrictNetworkPermissions('abc', invalidIsStrict: true),
        isTrue,
      );
    });
  });

  group('acceptedNetworkPermissionsFor', () {
    final local = Uri.parse('http://127.0.0.9:8080');
    final remote = Uri.parse('https://api.example.com');

    test('בתקופת המעבר יעד מקומי מקבל שתי הרשאות', () {
      expect(acceptedNetworkPermissionsFor(local, strict: false), {
        'network.localhost',
        'network.access',
      });
    });

    test('מ-0.9.99 יעד מקומי דורש network.localhost בלבד', () {
      expect(acceptedNetworkPermissionsFor(local, strict: true), {
        'network.localhost',
      });
    });

    test('יעד אינטרנט דורש network.access בלבד, בכל מצב', () {
      for (final strict in [true, false]) {
        expect(acceptedNetworkPermissionsFor(remote, strict: strict), {
          'network.access',
        });
      }
    });
  });

  group('PluginNetworkPermissionMode', () {
    test('נקבע לפי גרסת האפליקציה', () async {
      PluginNetworkPermissionMode.debugSetAppVersion('0.9.98');
      expect(await PluginNetworkPermissionMode.isStrict(), isFalse);
      PluginNetworkPermissionMode.debugSetAppVersion('0.9.99');
      expect(await PluginNetworkPermissionMode.isStrict(), isTrue);
    });

    test('גרסת אפליקציה לא חוקית נחשבת מלאה (כשל סגור)', () async {
      for (final version in ['', 'unknown', 'v0.9.99']) {
        PluginNetworkPermissionMode.debugSetAppVersion(version);
        expect(
          await PluginNetworkPermissionMode.isStrict(),
          isTrue,
          reason: version,
        );
      }
    });

    test('כשאי-אפשר לקרוא את הגרסה ההפרדה מלאה (כשל סגור)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      PluginNetworkPermissionMode.debugSetAppVersion(null);
      expect(await PluginNetworkPermissionMode.isStrict(), isTrue);
    });
  });
}
