import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebView2 prewarm starts once per process and waits for reveal', () {
    final source = File(
      'lib/main.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final singletons = source.substring(
      source.indexOf('Future<void> _initializeProcessSingletons()'),
      source.indexOf('Future<void> _runDeferredWebViewPrewarm()'),
    );
    expect(singletons, contains('unawaited(_runDeferredWebViewPrewarm());'));

    final start = source.indexOf('Future<void> _runDeferredWebViewPrewarm()');
    final deferred = source.substring(start, source.indexOf('\n}\n', start));
    expect(deferred, contains('!Platform.isWindows'));
    expect(
      deferred.indexOf('_mainWindowRevealedCompleter.future.timeout'),
      lessThan(deferred.indexOf('WebViewEnvironmentHolder.prewarm(')),
    );
    expect(deferred, contains('hasEnabledPlugin'));
    expect(deferred, contains('_logNonFatalInitializationError'));
  });
}
