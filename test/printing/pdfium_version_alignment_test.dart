import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('גרסת PDFium של printing זהה לזו של pdfium_dart', () {
    final config = File('.dart_tool/package_config.json');
    final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'];
    final root =
        (packages as List).firstWhere(
              (package) => package['name'] == 'pdfium_dart',
            )['rootUri']
            as String;
    final hook = config.absolute.uri.resolve(
      '${root.endsWith('/') ? root : '$root/'}hook/build.dart',
    );
    final release = RegExp(
      r"_pdfiumRelease = 'chromium%2F(\d+)'",
    ).firstMatch(File.fromUri(hook).readAsStringSync())!.group(1);
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    // FORCE ולפני ה-include של הפלאגינים, אחרת ברירת המחדל של printing גוברת.
    final pin = RegExp(
      '^set\\(PDFIUM_VERSION "$release" CACHE STRING .* FORCE\\)',
      multiLine: true,
    ).firstMatch(cmake);
    expect(pin, isNotNull);
    expect(
      pin!.start,
      lessThan(cmake.indexOf('include(flutter/generated_plugins.cmake)')),
    );
  });
}
