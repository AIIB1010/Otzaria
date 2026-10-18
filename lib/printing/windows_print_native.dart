/// Win32 printing calls. Each entry point except [printDialogOwnerWindow] runs
/// on a background isolate, so a slow driver or spooler never freezes the UI.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/printing/windows_print_data.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:printing/printing.dart' show Printer;
import 'package:win32/win32.dart' as win32;

/// The printer a job goes to: [driver] and [device] as `CreateDC` takes them,
/// and the DEVMODEW to apply, or null for the printer's own defaults.
typedef WindowsPrintTarget = ({
  String driver,
  String device,
  Uint8List? devMode,
});

/// What the user chose in the print dialog. [ranges] are one-based and
/// inclusive; null means all pages.
typedef WindowsPrintChoice = ({
  WindowsPrintTarget target,
  List<(int, int)>? ranges,
});

typedef WindowsPrintJob = ({
  String? pdfiumModulePath,
  WindowsPrintTarget target,
  String name,
  String? outputPath,
  Uint8List pdf,
  List<(int, int)>? ranges,
});

@visibleForTesting
final class PrintDlgExW extends Struct {
  @Uint32()
  external int lStructSize;
  external Pointer hwndOwner;
  external Pointer hDevMode;
  external Pointer hDevNames;
  external Pointer hDC;
  @Uint32()
  external int flags;
  @Uint32()
  external int flags2;
  @Uint32()
  external int exclusionFlags;
  @Uint32()
  external int nPageRanges;
  @Uint32()
  external int nMaxPageRanges;
  external Pointer<PrintPageRange> lpPageRanges;
  @Uint32()
  external int nMinPage;
  @Uint32()
  external int nMaxPage;
  @Uint32()
  external int nCopies;
  external Pointer hInstance;
  external Pointer<Utf16> lpPrintTemplateName;
  external Pointer lpCallback;
  @Uint32()
  external int nPropertyPages;
  external Pointer lphPropertyPages;
  @Uint32()
  external int nStartPage;
  @Uint32()
  external int dwResultAction;
}

@visibleForTesting
final class PrintPageRange extends Struct {
  @Uint32()
  external int nFromPage;
  @Uint32()
  external int nToPage;
}

@visibleForTesting
final class DocInfoW extends Struct {
  @Int32()
  external int cbSize;
  external Pointer<Utf16> lpszDocName;
  external Pointer<Utf16> lpszOutput;
  external Pointer<Utf16> lpszDatatype;
  @Uint32()
  external int fwType;
}

const int _pdPageNums = 0x2;
const int _pdNoSelection = 0x4;
const int _pdUseDevModeCopiesAndCollate = 0x40000;
const int _pdNoCurrentPage = 0x800000;
const int _pdResultPrint = 1;
const int _startPageGeneral = 0xFFFFFFFF;
const int _maxPageRanges = 32;
const int _gmemMoveable = 0x2;
const int _coinitApartmentThreaded = 0x2;

const int _horzRes = 8;
const int _vertRes = 10;
const int _logPixelsX = 88;
const int _logPixelsY = 90;
const int _physicalWidth = 110;
const int _physicalHeight = 111;
const int _physicalOffsetX = 112;
const int _physicalOffsetY = 113;

const int _printerStatusPaused = 0x1;
const int _printerStatusError = 0x2;
const int _printerStatusOffline = 0x80;
const int _printerStatusNotAvailable = 0x1000;

final _comdlg32 = DynamicLibrary.open('comdlg32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _ole32 = DynamicLibrary.open('ole32.dll');
final _user32 = DynamicLibrary.open('user32.dll');

final _printDlgEx = _comdlg32
    .lookupFunction<
      Int32 Function(Pointer<PrintDlgExW>),
      int Function(Pointer<PrintDlgExW>)
    >('PrintDlgExW');

final _createDC = _gdi32
    .lookupFunction<
      Pointer Function(Pointer<Utf16>, Pointer<Utf16>, Pointer, Pointer<Uint8>),
      Pointer Function(Pointer<Utf16>, Pointer<Utf16>, Pointer, Pointer<Uint8>)
    >('CreateDCW');
final _deleteDC = _gdi32
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>('DeleteDC');
final _getDeviceCaps = _gdi32
    .lookupFunction<Int32 Function(Pointer, Int32), int Function(Pointer, int)>(
      'GetDeviceCaps',
    );
final _startDoc = _gdi32
    .lookupFunction<
      Int32 Function(Pointer, Pointer<DocInfoW>),
      int Function(Pointer, Pointer<DocInfoW>)
    >('StartDocW');
final _endDoc = _gdi32
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>('EndDoc');
final _abortDoc = _gdi32
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>('AbortDoc');
final _startPage = _gdi32
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
      'StartPage',
    );
final _endPage = _gdi32
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>('EndPage');

final _globalAlloc = _kernel32
    .lookupFunction<
      Pointer Function(Uint32, IntPtr),
      Pointer Function(int, int)
    >('GlobalAlloc');
final _globalLock = _kernel32
    .lookupFunction<
      Pointer<Uint8> Function(Pointer),
      Pointer<Uint8> Function(Pointer)
    >(
      'GlobalLock',
    );
final _globalUnlock = _kernel32
    .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
      'GlobalUnlock',
    );
final _globalSize = _kernel32
    .lookupFunction<IntPtr Function(Pointer), int Function(Pointer)>(
      'GlobalSize',
    );
final _globalFree = _kernel32
    .lookupFunction<Pointer Function(Pointer), Pointer Function(Pointer)>(
      'GlobalFree',
    );

final _coInitializeEx = _ole32
    .lookupFunction<
      Int32 Function(Pointer, Uint32),
      int Function(Pointer, int)
    >(
      'CoInitializeEx',
    );
final _coUninitialize = _ole32.lookupFunction<Void Function(), void Function()>(
  'CoUninitialize',
);

final _getActiveWindow = _user32
    .lookupFunction<Pointer Function(), Pointer Function()>('GetActiveWindow');
final _getForegroundWindow = _user32
    .lookupFunction<Pointer Function(), Pointer Function()>(
      'GetForegroundWindow',
    );

typedef _RenderPageNative =
    Void Function(
      Pointer,
      pdfium_bindings.FPDF_PAGE,
      Int,
      Int,
      Int,
      Int,
      Int,
      Int,
    );
typedef _RenderPage =
    void Function(
      Pointer,
      pdfium_bindings.FPDF_PAGE,
      int,
      int,
      int,
      int,
      int,
      int,
    );

/// The window the print dialog belongs to. Must run on the platform thread,
/// whose active window is the app's.
int printDialogOwnerWindow() {
  final active = _getActiveWindow();
  return active.address != 0 ? active.address : _getForegroundWindow().address;
}

/// Shows the system print dialog, owned by [ownerWindow] and blocking until
/// it closes. Returns null when the user cancels.
WindowsPrintChoice? showWindowsPrintDialog(
  int ownerWindow,
  Uint8List? devMode,
) {
  final com = _coInitializeEx(nullptr, _coinitApartmentThreaded);
  try {
    return using((arena) {
      final dialog = arena<PrintDlgExW>();
      final ranges = arena<PrintPageRange>(_maxPageRanges);
      dialog.ref
        ..lStructSize = sizeOf<PrintDlgExW>()
        ..hwndOwner = Pointer.fromAddress(ownerWindow)
        ..hDevMode = devMode == null ? nullptr : _toGlobal(devMode)
        ..flags =
            _pdUseDevModeCopiesAndCollate | _pdNoSelection | _pdNoCurrentPage
        ..nMaxPageRanges = _maxPageRanges
        ..lpPageRanges = ranges
        ..nMinPage = 1
        ..nMaxPage = 0xFFFF
        ..nCopies = 1
        ..nStartPage = _startPageGeneral;
      final result = _printDlgEx(dialog);
      try {
        if (result != 0) {
          throw StateError(
            'PrintDlgEx failed: 0x${result.toUnsigned(32).toRadixString(16)}',
          );
        }
        if (dialog.ref.dwResultAction != _pdResultPrint) return null;
        final names = parseDevNames(_globalBytes(dialog.ref.hDevNames));
        final pageNums = dialog.ref.flags & _pdPageNums != 0;
        return (
          target: (
            driver: names.driver,
            device: names.device,
            devMode: dialog.ref.hDevMode == nullptr
                ? null
                : _globalBytes(dialog.ref.hDevMode),
          ),
          ranges: pageNums
              ? [
                  for (var i = 0; i < dialog.ref.nPageRanges; i++)
                    (ranges[i].nFromPage, ranges[i].nToPage),
                ]
              : null,
        );
      } finally {
        for (final handle in [dialog.ref.hDevMode, dialog.ref.hDevNames]) {
          if (handle != nullptr) _globalFree(handle);
        }
        if (dialog.ref.hDC != nullptr) _deleteDC(dialog.ref.hDC);
      }
    });
  } finally {
    if (com >= 0) _coUninitialize();
  }
}

/// The paper metrics of [target], or null when its DC cannot be created.
PrinterDeviceCaps? queryPrinterDeviceCaps(WindowsPrintTarget target) {
  return using((arena) {
    final dc = _createTargetDC(target, arena);
    if (dc == nullptr) return null;
    try {
      return _deviceCaps(dc);
    } finally {
      _deleteDC(dc);
    }
  });
}

/// Prints [job] and returns whether the spooler accepted it. Runs on PDFium's
/// worker isolate, where PDFium is initialized.
bool runWindowsPrintJob(WindowsPrintJob job) {
  final pdfium = pdfium_bindings.getPdfium(modulePath: job.pdfiumModulePath);
  final renderPage = DynamicLibrary.open(
    job.pdfiumModulePath ?? 'pdfium.dll',
  ).lookupFunction<_RenderPageNative, _RenderPage>('FPDF_RenderPage');
  // Drivers that ask for a file name, such as Print to PDF, need COM.
  final com = _coInitializeEx(nullptr, _coinitApartmentThreaded);
  try {
    return using((arena) {
      final data = arena<Uint8>(job.pdf.length);
      data.asTypedList(job.pdf.length).setAll(0, job.pdf);
      final document = pdfium.FPDF_LoadMemDocument64(
        data.cast(),
        job.pdf.length,
        nullptr,
      );
      if (document == nullptr) {
        throw StateError('Cannot print a malformed PDF file');
      }
      try {
        final pages = pageIndicesForRanges(
          job.ranges,
          pdfium.FPDF_GetPageCount(document),
        );
        if (pages.isEmpty) return false;
        final dc = _createTargetDC(job.target, arena);
        if (dc == nullptr) return false;
        try {
          return _printPages(
            pdfium,
            renderPage,
            document,
            pages,
            dc,
            job,
            arena,
          );
        } finally {
          _deleteDC(dc);
        }
      } finally {
        pdfium.FPDF_CloseDocument(document);
      }
    });
  } finally {
    if (com >= 0) _coUninitialize();
  }
}

bool _printPages(
  pdfium_bindings.PDFium pdfium,
  _RenderPage renderPage,
  pdfium_bindings.FPDF_DOCUMENT document,
  List<int> pages,
  Pointer dc,
  WindowsPrintJob job,
  Arena arena,
) {
  final caps = _deviceCaps(dc);
  final dpiX = caps.logPixelsX / 72;
  final dpiY = caps.logPixelsY / 72;
  final docInfo = arena<DocInfoW>();
  docInfo.ref
    ..cbSize = sizeOf<DocInfoW>()
    ..lpszDocName = job.name.toNativeUtf16(allocator: arena)
    ..lpszOutput = job.outputPath == null
        ? nullptr
        : job.outputPath!.toNativeUtf16(allocator: arena);
  if (_startDoc(dc, docInfo) <= 0) return false;
  for (final index in pages) {
    if (_startPage(dc) <= 0) {
      _abortDoc(dc);
      return false;
    }
    final page = pdfium.FPDF_LoadPage(document, index);
    if (page != nullptr) {
      renderPage(
        dc,
        page,
        -caps.offsetX,
        -caps.offsetY,
        (pdfium.FPDF_GetPageWidth(page) * dpiX).toInt(),
        (pdfium.FPDF_GetPageHeight(page) * dpiY).toInt(),
        0,
        pdfium_bindings.FPDF_ANNOT | pdfium_bindings.FPDF_PRINTING,
      );
      pdfium.FPDF_ClosePage(page);
    }
    if (_endPage(dc) <= 0) {
      _abortDoc(dc);
      return false;
    }
  }
  return _endDoc(dc) > 0;
}

/// The installed printers, as the `printing` plugin reports them.
List<Printer> listWindowsPrinters() {
  return using((arena) {
    final defaultName = _defaultPrinterName(arena);
    const flags = win32.PRINTER_ENUM_LOCAL | win32.PRINTER_ENUM_CONNECTIONS;
    final needed = arena<Uint32>();
    final returned = arena<Uint32>();
    win32.EnumPrinters(flags, null, 2, null, 0, needed, returned);
    if (needed.value == 0) return const [];
    final buffer = arena<Uint8>(needed.value);
    final ok = win32.EnumPrinters(
      flags,
      null,
      2,
      buffer,
      needed.value,
      needed,
      returned,
    ).value;
    if (!ok) return const [];
    final infos = buffer.cast<win32.PRINTER_INFO_2>();
    return [
      for (var i = 0; i < returned.value; i++)
        if (infos[i].pPrinterName.address != 0)
          _printerFrom(infos[i], defaultName),
    ];
  });
}

Printer _printerFrom(win32.PRINTER_INFO_2 info, String? defaultName) {
  String? text(win32.PWSTR value) =>
      value.address == 0 ? null : value.toDartString();
  final name = info.pPrinterName.toDartString();
  const unavailable =
      _printerStatusNotAvailable |
      _printerStatusError |
      _printerStatusOffline |
      _printerStatusPaused;
  return Printer(
    url: name,
    name: name,
    model: text(info.pDriverName),
    location: text(info.pLocation),
    comment: text(info.pComment),
    isDefault: name == defaultName,
    isAvailable: info.Status & unavailable == 0,
  );
}

String? _defaultPrinterName(Arena arena) {
  final size = arena<Uint32>();
  win32.GetDefaultPrinter(null, size);
  if (size.value == 0) return null;
  final name = arena<Uint16>(size.value).cast<Utf16>();
  if (!win32.GetDefaultPrinter(win32.PWSTR(name), size)) return null;
  return name.toDartString();
}

Pointer _createTargetDC(WindowsPrintTarget target, Arena arena) {
  final devMode = target.devMode;
  Pointer<Uint8> mode = nullptr;
  if (devMode != null) {
    mode = arena<Uint8>(devMode.length);
    mode.asTypedList(devMode.length).setAll(0, devMode);
  }
  return _createDC(
    target.driver.toNativeUtf16(allocator: arena),
    target.device.toNativeUtf16(allocator: arena),
    nullptr,
    mode,
  );
}

PrinterDeviceCaps _deviceCaps(Pointer dc) => (
  logPixelsX: _getDeviceCaps(dc, _logPixelsX),
  logPixelsY: _getDeviceCaps(dc, _logPixelsY),
  physicalWidth: _getDeviceCaps(dc, _physicalWidth),
  physicalHeight: _getDeviceCaps(dc, _physicalHeight),
  printableWidth: _getDeviceCaps(dc, _horzRes),
  printableHeight: _getDeviceCaps(dc, _vertRes),
  offsetX: _getDeviceCaps(dc, _physicalOffsetX),
  offsetY: _getDeviceCaps(dc, _physicalOffsetY),
);

Pointer _toGlobal(Uint8List bytes) {
  final handle = _globalAlloc(_gmemMoveable, bytes.length);
  if (handle == nullptr) throw StateError('GlobalAlloc failed');
  final memory = _globalLock(handle);
  memory.asTypedList(bytes.length).setAll(0, bytes);
  _globalUnlock(handle);
  return handle;
}

Uint8List _globalBytes(Pointer handle) {
  final size = _globalSize(handle);
  final memory = _globalLock(handle);
  try {
    return Uint8List.fromList(memory.asTypedList(size));
  } finally {
    _globalUnlock(handle);
  }
}
