import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';

/// עמודי PDF עוברים למנוע כחוצץ ארוז; הוא חייב לאנדקס אותם בדיוק כמו
/// רשימת העמודים, כולל עמוד ריק ותווים שהקידוד מחליף.
void main() {
  const pages = [
    (
      reference: 'ספר, עמוד 1',
      text: 'שורה ראשונה\n\n≡≡≡ ∴∴∴ ⊕⊗⊘',
      pageIndex: 0,
    ),
    (reference: '', text: '', pageIndex: 1),
    (
      reference: 'ספר, עמוד 3',
      text: 'בְּרֵאשִׁית ברא\r\nזוג \uD800 חסר',
      pageIndex: 4,
    ),
  ];

  test('packPdfPages: הפניה ואחריה טקסט לכל עמוד, וסופם ב-ends', () {
    final packed = IndexingRepository.packPdfPages(pages);
    final decoded = <String>[];
    var start = 0;
    for (final end in packed.ends) {
      decoded.add(utf8.decode(packed.bytes.sublist(start, end)));
      start = end;
    }
    expect(start, packed.bytes.length);
    expect(decoded, [
      for (final page in pages) ...[
        page.reference,
        utf8.decode(utf8.encode(page.text)),
      ],
    ]);
    expect(packed.pageIndexes, [0, 1, 4]);
  });

  test('addPdfBookBytes על packPdfPages זהה ל-addPdfBook', () async {
    if (!await tryInitSearchEngine()) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    final directory = await Directory.systemTemp.createTemp('pdf_bytes_equiv');
    final engine = await SearchEngine.newInstance(path: directory.path);
    addTearDown(() async {
      engine.dispose();
      await directory.delete(recursive: true);
    });

    final viaList = await engine.addPdfBook(
      title: 'ספר',
      topics: '/a',
      filePath: 'list.pdf',
      pages: [
        for (final page in pages)
          PdfPageInput(
            reference: page.reference,
            text: page.text,
            pageIndex: page.pageIndex,
          ),
      ],
    );
    final packed = IndexingRepository.packPdfPages(pages);
    final viaBytes = await engine.addPdfBookBytes(
      title: 'ספר',
      topics: '/a',
      filePath: 'bytes.pdf',
      bytes: packed.bytes,
      ends: packed.ends,
      pageIndexes: packed.pageIndexes,
    );
    await engine.commit();
    expect(viaBytes, viaList);
    expect(viaBytes, greaterThan(0));

    Future<List<String>> hits(String query) async {
      final results = await engine.searchExact(
        query: query,
        facets: const [],
        limit: 20,
        offset: 0,
        order: ResultsOrder.catalogue,
        matchNikud: false,
        matchTaamim: false,
      );
      return [
        for (final hit in results)
          '${hit.filePath}|${hit.reference}|${hit.segment}|${hit.text}',
      ]..sort();
    }

    for (final query in ['שורה ראשונה', 'בראשית ברא', 'חסר']) {
      final found = await hits(query);
      final fromList = found.where((h) => h.startsWith('list.pdf|')).toList();
      final fromBytes = found.where((h) => h.startsWith('bytes.pdf|')).toList();
      expect(fromList, isNotEmpty, reason: query);
      expect(
        fromBytes.map((h) => h.replaceFirst('bytes.pdf|', '')),
        fromList.map((h) => h.replaceFirst('list.pdf|', '')),
        reason: query,
      );
    }
  });
}
