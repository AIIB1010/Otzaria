@TestOn('windows')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/windows_print_native.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;

const _printToPdf = 'Microsoft Print to PDF';

void main() {
  test('מבני Win32 בגודל של windows.h ב-64 ביט', () {
    expect(sizeOf<PrintDlgExW>(), 136);
    expect(sizeOf<PrintPageRange>(), 8);
    expect(sizeOf<DocInfoW>(), 40);
  });

  test('גרסת PDFium של printing זהה לזו של pdfium_dart', () async {
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
    final release = RegExp(r"_pdfiumRelease = 'chromium%2F(\d+)'")
        .firstMatch(
          File.fromUri(hook).readAsStringSync(),
        )!
        .group(1);
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(PDFIUM_VERSION "$release"'));
  });

  test('listWindowsPrinters מחזיר מדפסות, לכל היותר אחת ברירת מחדל', () async {
    final printers = await Isolate.run(listWindowsPrinters);
    expect(printers.where((printer) => printer.isDefault).length, lessThan(2));
  });

  group(
    'הדפסה ל-$_printToPdf',
    () {
      late final bool installed;
      late Directory temp;

      setUpAll(() async {
        installed = (await Isolate.run(
          listWindowsPrinters,
        )).any((printer) => printer.name == _printToPdf);
        Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
        await pdfrxFlutterInitialize();
      });

      setUp(() => temp = Directory.systemTemp.createTempSync('otzaria_print'));
      tearDown(() => temp.deleteSync(recursive: true));

      Future<int> printPages(List<(int, int)>? ranges) async {
        final doc = pw.Document();
        for (var i = 1; i <= 4; i++) {
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) => pw.Center(child: pw.Text('page$i')),
            ),
          );
        }
        final output = p.join(temp.path, 'out.pdf');
        const target = (driver: 'WINSPOOL', device: _printToPdf, devMode: null);
        expect(
          await Isolate.run(() => queryPrinterDeviceCaps(target)),
          isNotNull,
        );
        final printed = await PdfrxEntryFunctions.instance.compute(
          runWindowsPrintJob,
          (
            pdfiumModulePath: Pdfrx.pdfiumModulePath,
            target: target,
            name: 'otzaria test',
            outputPath: output,
            pdf: await doc.save(),
            ranges: ranges,
          ),
        );
        expect(printed, isTrue);
        // The spooler writes the file after EndDoc returns.
        final deadline = DateTime.now().add(const Duration(minutes: 1));
        while (true) {
          try {
            final result = await PdfDocument.openFile(output);
            try {
              return result.pages.length;
            } finally {
              await result.dispose();
            }
          } on Exception {
            if (DateTime.now().isAfter(deadline)) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      test('כל העמודים נכתבים לקובץ', () async {
        if (!installed) return markTestSkipped('$_printToPdf not installed');
        expect(await printPages(null), 4);
      });

      test('טווח עמודים מהדיאלוג מדפיס רק אותו', () async {
        if (!installed) return markTestSkipped('$_printToPdf not installed');
        expect(await printPages([(2, 3)]), 2);
      });
    },
  );
}
