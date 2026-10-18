import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/windows_print_data.dart';
import 'package:pdf/pdf.dart';

int _int16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getInt16(offset, Endian.little);

Uint8List _devNames(String driver, String device, String port) {
  final units = <int>[0, 0, 0, 0];
  int append(String text) {
    final offset = units.length;
    units
      ..addAll(text.codeUnits)
      ..add(0);
    return offset;
  }

  units[0] = append(driver);
  units[1] = append(device);
  units[2] = append(port);
  final bytes = ByteData(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    bytes.setUint16(i * 2, units[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('paperDevMode', () {
    test('A4 לאורך: מידות בעשיריות מ"מ, כמו בחבילת printing', () {
      final mode = paperDevMode(PdfPageFormat.a4);
      expect(mode.length, devModeSize);
      expect(_int16(mode, 68), devModeSize);
      expect(
        ByteData.sublistView(mode).getUint32(72, Endian.little),
        dmOrientation | dmPaperSize | dmPaperLength | dmPaperWidth,
      );
      expect(_int16(mode, 76), dmOrientPortrait);
      expect(_int16(mode, 78), 0);
      expect(_int16(mode, 82), 2100);
      expect(_int16(mode, 80), 2970);
    });

    test('דף רחב מגובהו יוצא לרוחב, והנייר נמדד לפי הצלע הקצרה', () {
      final mode = paperDevMode(PdfPageFormat.a4.landscape);
      expect(_int16(mode, 76), dmOrientLandscape);
      expect(_int16(mode, 82), 2100);
      expect(_int16(mode, 80), 2970);
    });
  });

  test('parseDevNames קורא את השמות לפי ההיסטים', () {
    final names = parseDevNames(
      _devNames('winspool', 'מדפסת המשרד', 'USB001'),
    );
    expect(names.driver, 'winspool');
    expect(names.device, 'מדפסת המשרד');
    expect(names.port, 'USB001');
  });

  group('pageIndicesForRanges', () {
    test('בלי טווחים — כל העמודים', () {
      expect(pageIndicesForRanges(null, 3), [0, 1, 2]);
    });

    test('טווחים בסדר שהוזנו, וחלק שמעבר לסוף נחתך', () {
      expect(pageIndicesForRanges([(4, 6), (1, 2)], 5), [3, 4, 0, 1]);
    });

    test('טווח הפוך מתפרש כרגיל, וטווח מחוץ למסמך ריק', () {
      expect(pageIndicesForRanges([(3, 2)], 5), [1, 2]);
      expect(pageIndicesForRanges([(7, 9)], 5), isEmpty);
    });
  });

  test('pageFormatFromDeviceCaps: נייר ושוליים בנקודות PDF', () {
    // A4 at 600 dpi with a quarter-inch unprintable border all round.
    final format = pageFormatFromDeviceCaps((
      logPixelsX: 600,
      logPixelsY: 600,
      physicalWidth: 4960,
      physicalHeight: 7016,
      printableWidth: 4660,
      printableHeight: 6716,
      offsetX: 150,
      offsetY: 150,
    ));
    expect(format.width, closeTo(595.2, 0.01));
    expect(format.height, closeTo(841.92, 0.01));
    expect(format.marginLeft, closeTo(18, 0.01));
    expect(format.marginTop, closeTo(18, 0.01));
    expect(format.marginRight, closeTo(18, 0.01));
    expect(format.marginBottom, closeTo(18, 0.01));
  });

  group('fileOutputExtension', () {
    test('פורט שמבקש שם קובץ — סיומת לפי סוג המדפסת', () {
      expect(
        fileOutputExtension(
          printerName: 'Microsoft Print to PDF',
          port: 'PORTPROMPT:',
        ),
        'pdf',
      );
      expect(
        fileOutputExtension(
          printerName: 'Microsoft XPS Document Writer',
          port: ' portprompt: ',
        ),
        'oxps',
      );
      expect(
        fileOutputExtension(printerName: 'HP LaserJet', port: 'FILE:'),
        'prn',
      );
    });

    test('מדפסות Microsoft לקובץ מזוהות גם בלי פורט', () {
      expect(fileOutputExtension(printerName: 'Microsoft Print to PDF'), 'pdf');
    });

    test('מדפסת נייר אינה מבקשת קובץ', () {
      for (final port in ['USB001', 'LPT1:', 'WSD-abc', 'nul:', null]) {
        expect(
          fileOutputExtension(printerName: 'HP LaserJet', port: port),
          isNull,
          reason: port,
        );
      }
    });
  });

  test('printOutputFileName מנקה תווים אסורים', () {
    expect(printOutputFileName('שו"ע: או"ח/א', 'pdf'), 'שו_ע_ או_ח_א.pdf');
    expect(printOutputFileName('  ', 'oxps'), 'document.oxps');
  });
}
