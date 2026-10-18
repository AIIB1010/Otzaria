import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show Rect;
import 'package:otzaria/printing/windows_print_data.dart';
import 'package:otzaria/printing/windows_print_native.dart';
import 'package:otzaria/printing/windows_printer_ports.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:pdf/pdf.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
// ignore: implementation_imports
import 'package:printing/src/method_channel.dart';
import 'package:window_manager/window_manager.dart';

/// Printing on Windows off the platform thread, where the `printing` plugin
/// renders the whole job and freezes the window. Other calls go to the plugin.
class WindowsPrintingPlatform extends PrintingPlatform {
  WindowsPrintingPlatform(this._plugin);

  final PrintingPlatform _plugin;

  /// Routes `Printing` through this class on Windows, unless something other
  /// than the plugin's default (such as a test fake) is already installed.
  static void install() {
    if (!Platform.isWindows) return;
    final current = PrintingPlatform.instance;
    if (current is MethodChannelPrinting) {
      PrintingPlatform.instance = WindowsPrintingPlatform(current);
    }
  }

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    final paper = usePrinterSettings ? null : paperDevMode(format);
    final WindowsPrintTarget target;
    List<(int, int)>? ranges;
    final String? port;
    if (printer == null) {
      // Every window of the app shares the platform thread, so its active
      // window may be another of ours; the engine knows its own.
      final ownWindow = await windowManager.getId();
      final owner = ownWindow != 0 ? ownWindow : printDialogFallbackOwner();
      // On the platform thread the dialog's modal loop would run engine tasks
      // into Dart while it is still inside the FFI call.
      final choice = await Isolate.run(
        () => showWindowsPrintDialog(owner, paper),
      );
      if (choice == null) return false;
      target = choice.target;
      ranges = choice.ranges;
      port = choice.port;
    } else {
      target = (driver: 'WINSPOOL', device: printer.url, devMode: paper);
      port = (await Isolate.run(windowsPrinterPorts))[printer.url];
    }

    // Asked here, since a driver asking from PDFium's worker would block all
    // PDF rendering behind a dialog that has no owner window.
    String? outputPath;
    final extension = fileOutputExtension(
      printerName: target.device,
      port: port,
    );
    if (extension != null) {
      outputPath = await saveFileWithExtension(
        fileName: printOutputFileName(name, extension),
        extension: extension,
        bytes: Uint8List(0),
      );
      if (outputPath == null) return false;
    }

    final caps = await Isolate.run(() => queryPrinterDeviceCaps(target));
    if (caps == null) return false;
    final pdf = await onLayout(pageFormatFromDeviceCaps(caps));

    await pdfrxFlutterInitialize();
    return PdfrxEntryFunctions.instance.compute(runWindowsPrintJob, (
      pdfiumModulePath: Pdfrx.pdfiumModulePath,
      target: target,
      name: name,
      outputPath: outputPath,
      pdf: pdf,
      ranges: ranges,
    ));
  }

  @override
  Future<List<Printer>> listPrinters() => Isolate.run(listWindowsPrinters);

  @override
  Future<PrintingInfo> info() => _plugin.info();

  @override
  Future<Printer?> pickPrinter(Rect bounds) => _plugin.pickPrinter(bounds);

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) => _plugin.sharePdf(bytes, filename, bounds, subject, body, emails);

  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) => _plugin.convertHtml(html, baseUrl, format);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      _plugin.raster(document, pages, dpi);
}
