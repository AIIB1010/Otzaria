import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String deferredAutoBackup() {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf(
      'Future<void> _runDeferredAutoBackup() async {',
    );
    final end = source.indexOf('\n}\n', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  test('הגיבוי האוטומטי ממתין לחשיפת החלון לפני שהוא מתחיל', () {
    final body = deferredAutoBackup();
    const revealWait = '_mainWindowRevealedCompleter.future.timeout(';
    expect(body, contains(revealWait));
    expect(
      body.indexOf(revealWait),
      lessThan(body.indexOf('BackupService.shouldPerformAutoBackup()')),
    );
  });

  test('הגיבוי האוטומטי עדיין רץ, רק בחלון הראשי', () {
    final body = deferredAutoBackup();
    expect(
      body.indexOf('if (WindowRole.isSecondary) return;'),
      lessThan(body.indexOf('BackupService.shouldPerformAutoBackup()')),
    );
    expect(body, contains('await BackupService.performAutoBackup();'));
    expect(body, contains('_logNonFatalInitializationError'));
  });
}
