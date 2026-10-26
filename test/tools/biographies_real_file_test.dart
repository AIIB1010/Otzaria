@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';

/// Checks a real release file. Manual only, needs a local copy of
/// `biographies-app.json.gz`:
/// `flutter test test/tools/biographies_real_file_test.dart --tags manual`
/// `--dart-define=BIO_FILE=<path>`
void main() {
  const path = String.fromEnvironment('BIO_FILE');

  test('decodes a real release file', () {
    final bundle = BiographiesCodec.decode(File(path).readAsBytesSync());
    final entries = bundle.entries;

    expect(entries.length, greaterThan(4000));
    expect(entries.every((b) => b.name.trim().isNotEmpty), isTrue);
    expect(entries.every((b) => b.eraLabel != null), isTrue);
    expect(entries.where((b) => b.summary != null), isNotEmpty);
    expect(entries.where((b) => b.died != null), isNotEmpty);
    expect(entries.map((b) => b.id).toSet().length, entries.length);
    expect(bundle.credits, isNotEmpty);
    expect(
      entries
          .expand((b) => b.sources)
          .every((s) => bundle.credits.containsKey(s.credit)),
      isTrue,
    );
  }, skip: path.isEmpty ? 'BIO_FILE not provided' : false);
}
