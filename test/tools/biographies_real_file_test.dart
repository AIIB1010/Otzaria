@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_biography_compatibility.dart';
import 'package:otzaria/tools/biographies/widgets/biography_card.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';

/// בדיקות נתוני אמת: `--tags manual --dart-define=BIO_FILE=<path>`
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
    final legacyIds = entries.map(
      (b) => PluginBiographyCompatibility.legacyId(b.id),
    );
    expect(legacyIds.toSet().length, entries.length);
    expect(
      legacyIds.every((id) => id < 0 && id.abs() <= 9007199254740991),
      isTrue,
    );
    expect(bundle.credits, isNotEmpty);
    expect(
      entries
          .expand((b) => b.sources)
          .every((s) => bundle.credits.containsKey(s.credit)),
      isTrue,
    );
  }, skip: path.isEmpty ? 'BIO_FILE not provided' : false);

  testWidgets('הנצי״ב: כל פרטי המשפחה והתלמידים נכנסים במסך טלפון', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bundle = BiographiesCodec.decode(File(path).readAsBytesSync());
    final bio = bundle.entries.firstWhere((b) => b.id == 'Q1861531');
    final ids = bundle.entries.map((b) => b.id).toSet();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                BiographyCard(
                  biography: bio,
                  initiallyExpanded: true,
                  canOpen: ids.contains,
                  onOpen: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: path.isEmpty);
}
