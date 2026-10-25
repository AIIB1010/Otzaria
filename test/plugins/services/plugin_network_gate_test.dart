import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_network_permission_mode.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';

PluginManifest _manifest({
  required String minAppVersion,
  required bool enabled,
}) => PluginManifest(
  schemaVersion: 1,
  id: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  description: '',
  author: '',
  homepage: '',
  entrypoint: 'index.html',
  minAppVersion: minAppVersion,
  sdkVersion: '1.x',
  permissions: const ['network.access', 'network.localhost'],
  networkEnabled: enabled,
  networkAllowlist: const ['127.0.0.9', 'https://api.example.com'],
  toolTabTitle: 'Test Plugin',
  toolTabOrder: 1,
  defaultPinned: true,
  publishedDataTypes: const [],
);

class _FakeRegistry implements PluginRegistryRepository {
  _FakeRegistry(this._granted);

  final Set<String> _granted;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      _granted.contains(permission);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// [appVersion] — גרסת האפליקציה שמריצה את התוסף. זו שקובעת אם ההפרדה מלאה;
/// ה-`minAppVersion` של התוסף אינו משפיע.
Future<PluginNetworkDecision> _decide(
  String url, {
  required String appVersion,
  required Set<String> granted,
  String minAppVersion = '0.9.0',
  bool enabled = true,
}) {
  PluginNetworkPermissionMode.debugSetAppVersion(appVersion);
  return evaluatePluginNetworkAccess(
    uri: Uri.parse(url),
    pluginId: 'test.plugin',
    manifest: _manifest(minAppVersion: minAppVersion, enabled: enabled),
    registry: _FakeRegistry(granted),
  );
}

void main() {
  const local = 'http://127.0.0.9:8080/api';
  const remote = 'https://api.example.com/v1';

  tearDown(() => PluginNetworkPermissionMode.debugSetAppVersion(null));

  group('יעד מקומי באוצריא ישנה מ-0.9.99 (תקופת מעבר)', () {
    test('network.localhost לבדה מספיקה', () async {
      expect(
        await _decide(
          local,
          appVersion: '0.9.98',
          granted: {'network.localhost'},
        ),
        PluginNetworkDecision.allowed,
      );
    });

    test('network.access לבדה מספיקה', () async {
      expect(
        await _decide(local, appVersion: '0.9.98', granted: {'network.access'}),
        PluginNetworkDecision.allowed,
      );
    });

    test('בלי אף הרשאה נחסם', () async {
      expect(
        await _decide(local, appVersion: '0.9.98', granted: {}),
        PluginNetworkDecision.permissionMissing,
      );
    });
  });

  group('יעד מקומי באוצריא 0.9.99 ומעלה', () {
    for (final version in ['0.9.99', '0.9.99+99900', '0.10.0']) {
      test('network.localhost מספיקה ($version)', () async {
        expect(
          await _decide(
            local,
            appVersion: version,
            granted: {'network.localhost'},
          ),
          PluginNetworkDecision.allowed,
        );
      });

      test('network.access אינה מחליפה אותה ($version)', () async {
        expect(
          await _decide(
            local,
            appVersion: version,
            granted: {'network.access'},
          ),
          PluginNetworkDecision.permissionMissing,
        );
      });
    }
  });

  test('minAppVersion של התוסף אינו משפיע — קובעת גרסת האפליקציה', () async {
    expect(
      await _decide(
        local,
        appVersion: '0.9.99',
        minAppVersion: '0.9.0',
        granted: {'network.access'},
      ),
      PluginNetworkDecision.permissionMissing,
    );
    expect(
      await _decide(
        local,
        appVersion: '0.9.98',
        minAppVersion: '1.0.0',
        granted: {'network.access'},
      ),
      PluginNetworkDecision.allowed,
    );
  });

  group('הצהרת היעד ב-allowlist נשארת תנאי בכל מצב', () {
    for (final version in ['0.9.98', '0.9.99']) {
      test('כתובת מקומית אחרת שלא הוצהרה נחסמת ($version)', () async {
        expect(
          await _decide(
            'http://127.0.0.8:8080/api',
            appVersion: version,
            granted: {'network.localhost', 'network.access'},
          ),
          PluginNetworkDecision.notAllowlisted,
        );
      });
    }
  });

  group('יעד אינטרנט', () {
    for (final version in ['0.9.98', '0.9.99']) {
      test('network.localhost אינה מתירה אותו ($version)', () async {
        expect(
          await _decide(
            remote,
            appVersion: version,
            granted: {'network.localhost'},
          ),
          PluginNetworkDecision.permissionMissing,
        );
      });
    }
  });

  test(
    'כתובת מחוץ ל-127.0.0.x נחשבת אינטרנט וממתינה ל-network.access',
    () async {
      for (final version in ['0.9.98', '0.9.99']) {
        expect(
          await _decide(
            'http://127.10.10.1:8080/api',
            appVersion: version,
            granted: {'network.localhost'},
          ),
          PluginNetworkDecision.permissionMissing,
          reason: version,
        );
      }
    },
  );

  test('מניפסט בלי network.enabled אינו מצהיר על רשת', () async {
    expect(
      await _decide(
        local,
        appVersion: '0.9.98',
        granted: {'network.localhost', 'network.access'},
        enabled: false,
      ),
      PluginNetworkDecision.notDeclared,
    );
  });
}
