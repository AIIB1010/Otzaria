import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jsonString = File('assets/Acronyms.json').readAsStringSync();

  Future<List<List<Object>>> oracleCatalog() async {
    final raw = jsonDecode(jsonString) as Map<String, dynamic>;
    final oracle = DictionaryLookupRepository(
      loadAcronyms: () async => raw.map(
        (key, value) =>
            MapEntry(key, value is List ? value.cast<String>() : <String>[]),
      ),
    );
    await oracle.ensureAcronymsLoaded();
    return [
      for (final e in oracle.getAcronymSearchCatalog())
        [e.normalizedKey, e.displayAcronym, e.meanings],
    ];
  }

  test('פענוח ונרמול המילון כולו רצים ב-isolate נפרד', () async {
    final index = await Isolate.run(
      () => DictionaryLookupRepository.decodeAcronymIndex(jsonString),
    );

    final expected = await oracleCatalog();
    expect(index.byKey.length, expected.length);
    for (final [key as String, display, meanings] in expected) {
      expect(index.byKey[key], meanings, reason: key);
      expect(index.originalByKey[key], display, reason: key);
    }
  });

  test('טעינת ברירת המחדל מהנכס זהה לטעינה מהמפה הגולמית', () async {
    final repository = DictionaryLookupRepository();
    await repository.ensureAcronymsLoaded();

    final actual = [
      for (final e in repository.getAcronymSearchCatalog())
        [e.normalizedKey, e.displayAcronym, e.meanings],
    ];
    expect(actual, await oracleCatalog());
  });
}
