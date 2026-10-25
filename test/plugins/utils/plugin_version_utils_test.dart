import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';

void main() {
  group('PluginVersionUtils.compareCoreVersions', () {
    int compare(String a, String b) =>
        PluginVersionUtils.compareCoreVersions(a, b).sign;

    test('the hotfix segment orders hotfixes of the same release', () {
      expect(compare('0.9.98.1', '0.9.98'), 1);
      expect(compare('0.9.98', '0.9.98.1'), -1);
      expect(compare('0.9.98.2', '0.9.98.1'), 1);
      expect(compare('0.9.98.10', '0.9.98.9'), 1);
      expect(compare('0.9.98.99', '0.9.99'), -1);
    });

    test('a missing segment counts as zero', () {
      expect(compare('0.9.98.0', '0.9.98'), 0);
      expect(compare('0.9', '0.9.0.0'), 0);
      expect(compare('1.0.0', '0.9.98.1'), 1);
    });

    test('build metadata and prerelease suffixes are ignored', () {
      expect(compare('0.9.98.1+801', '0.9.98.1'), 0);
      expect(compare('0.9.98+99801', '0.9.98.1'), -1);
      expect(compare('0.9.98.1-dev', '0.9.98'), 1);
    });

    test('a malformed version throws', () {
      expect(
        () => PluginVersionUtils.compareCoreVersions('0.9.x', '0.9.98'),
        throwsA(isA<PluginVersionFormatException>()),
      );
    });
  });
}
