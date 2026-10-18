/// Plain data for the Windows print path, kept free of FFI so it can cross
/// isolates and be tested on any platform.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';

/// `sizeof(DEVMODEW)`.
const int devModeSize = 220;

const int _dmSizeOffset = 68;
const int _dmFieldsOffset = 72;
const int _dmOrientationOffset = 76;
const int _dmPaperSizeOffset = 78;
const int _dmPaperLengthOffset = 80;
const int _dmPaperWidthOffset = 82;

const int dmOrientation = 0x1;
const int dmPaperSize = 0x2;
const int dmPaperLength = 0x4;
const int dmPaperWidth = 0x8;
const int dmOrientPortrait = 1;
const int dmOrientLandscape = 2;

/// A DEVMODEW that asks the driver for a custom paper of [format]'s size, in
/// tenths of a millimetre, landscape when the page is wider than tall.
Uint8List paperDevMode(PdfPageFormat format) {
  final bytes = Uint8List(devModeSize);
  final data = ByteData.sublistView(bytes);
  final landscape = format.width > format.height;
  final shortSide = landscape ? format.height : format.width;
  final longSide = landscape ? format.width : format.height;
  data.setUint16(_dmSizeOffset, devModeSize, Endian.little);
  data.setUint32(
    _dmFieldsOffset,
    dmOrientation | dmPaperSize | dmPaperLength | dmPaperWidth,
    Endian.little,
  );
  data.setInt16(
    _dmOrientationOffset,
    landscape ? dmOrientLandscape : dmOrientPortrait,
    Endian.little,
  );
  data.setInt16(_dmPaperSizeOffset, 0, Endian.little);
  data.setInt16(_dmPaperWidthOffset, _tenthsOfMm(shortSide), Endian.little);
  data.setInt16(_dmPaperLengthOffset, _tenthsOfMm(longSide), Endian.little);
  return bytes;
}

int _tenthsOfMm(double points) => (points * 254 / PdfPageFormat.inch).round();

/// The driver, device and port names of a DEVNAMES block. Its offsets count
/// UTF-16 units from the block's start.
({String driver, String device, String port}) parseDevNames(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final units = Uint16List(bytes.length ~/ 2);
  for (var i = 0; i < units.length; i++) {
    units[i] = data.getUint16(i * 2, Endian.little);
  }
  String at(int offset) {
    var end = offset;
    while (end < units.length && units[end] != 0) {
      end++;
    }
    return String.fromCharCodes(units, offset, end);
  }

  return (
    driver: at(data.getUint16(0, Endian.little)),
    device: at(data.getUint16(2, Endian.little)),
    port: at(data.getUint16(4, Endian.little)),
  );
}

/// Zero-based page indices to print, in the order the user listed the
/// one-based [ranges]. Null prints every page.
List<int> pageIndicesForRanges(List<(int, int)>? ranges, int pageCount) {
  if (ranges == null) return [for (var i = 0; i < pageCount; i++) i];
  final indices = <int>[];
  for (final (from, to) in ranges) {
    final first = from < to ? from : to;
    final last = from < to ? to : from;
    for (var page = first; page <= last && page <= pageCount; page++) {
      if (page >= 1) indices.add(page - 1);
    }
  }
  return indices;
}

/// The `GetDeviceCaps` values of a printer DC that place a PDF page on paper.
typedef PrinterDeviceCaps = ({
  int logPixelsX,
  int logPixelsY,
  int physicalWidth,
  int physicalHeight,
  int printableWidth,
  int printableHeight,
  int offsetX,
  int offsetY,
});

/// The paper and its unprintable margins, in PDF points.
PdfPageFormat pageFormatFromDeviceCaps(PrinterDeviceCaps caps) {
  final dpiX = caps.logPixelsX / PdfPageFormat.inch;
  final dpiY = caps.logPixelsY / PdfPageFormat.inch;
  final width = caps.physicalWidth / dpiX;
  final height = caps.physicalHeight / dpiY;
  final marginLeft = caps.offsetX / dpiX;
  final marginTop = caps.offsetY / dpiY;
  return PdfPageFormat(
    width,
    height,
    marginLeft: marginLeft,
    marginTop: marginTop,
    marginRight: width - caps.printableWidth / dpiX - marginLeft,
    marginBottom: height - caps.printableHeight / dpiY - marginTop,
  );
}
