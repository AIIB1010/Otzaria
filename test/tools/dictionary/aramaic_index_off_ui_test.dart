import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jsonString = File('assets/dictionary.json').readAsStringSync();

  bool isPlaceholder(String hebrew) => hebrew
      .split('***')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .every(
        (part) =>
            part == '*' || part == '(סימן)' || !RegExp('[א-ת]').hasMatch(part),
      );

  List<AramaicDictionaryEntry> rawEntries() {
    final raw = jsonDecode(jsonString) as Map<String, dynamic>;
    const main = AramaicDictionaryEntry.peshitaDictionary;
    return [
      for (final name in [main, ...raw.keys.where((k) => k != main)])
        for (final entry
            in (raw[name] as List).whereType<Map<String, dynamic>>())
          if (entry.isNotEmpty &&
              !isPlaceholder(entry[entry.keys.first].toString()))
            AramaicDictionaryEntry(
              aramaic: entry.keys.first,
              hebrew: entry[entry.keys.first].toString(),
              dictionary: name,
            ),
    ];
  }

  Future<DictionaryLookupRepository> oracle() async {
    final entries = rawEntries();
    final repository = DictionaryLookupRepository(
      loadAramaicEntries: () async => entries,
    );
    await repository.ensureAramaicLoaded();
    return repository;
  }

  List<List<String>> shape(List<AramaicDictionaryEntry> entries) => [
    for (final e in entries) [e.aramaic, e.hebrew, e.dictionary],
  ];

  test('פענוח המילון ובניית האינדקס רצים ב-isolate נפרד', () async {
    final index = await Isolate.run(
      () => DictionaryLookupRepository.decodeAramaicIndex(jsonString),
    );

    final expected = await oracle();
    expect(shape(index.entries), shape(expected.getAllAramaicEntries()));
    expect(index.index.length, index.entries.length);
    final all = {...expected.aramaicDictionaryNames};
    // מילים עם סימני פיסוק פנימיים ("ל...") אינן יציבות לנרמול ואינן ניתנות לחיפוש.
    for (final term in index.terms.where(RegExp(r'^[א-ת\s-]+$').hasMatch)) {
      expect(
        expected.findAramaicMatches(term, dictionaries: all),
        isNotEmpty,
        reason: term,
      );
    }
  });

  test('טעינת ברירת המחדל מהנכס זהה לטעינה מרשימת הערכים', () async {
    final repository = DictionaryLookupRepository();
    await repository.ensureAramaicLoaded();
    final expected = await oracle();

    expect(
      shape(repository.getAllAramaicEntries()),
      shape(expected.getAllAramaicEntries()),
    );
    final all = {...expected.aramaicDictionaryNames};
    // כל ערך עשירי: סריקה מלאה לכל שאילתה על כל המילונים כבדה מדי.
    final sample = expected.getAllAramaicEntries().indexed.where(
      (e) => e.$1 % 10 == 0,
    );
    for (final (_, entry) in sample) {
      for (final query in [entry.aramaic, ...entry.aramaic.split(' ')]) {
        for (final dictionaries in [
          const {AramaicDictionaryEntry.peshitaDictionary},
          all,
        ]) {
          expect(
            shape(
              repository.findAramaicMatches(query, dictionaries: dictionaries),
            ),
            shape(
              expected.findAramaicMatches(query, dictionaries: dictionaries),
            ),
            reason: query,
          );
        }
      }
    }
  });
}
