import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

typedef SuspendPdfium =
    Future<void> Function(Future<void> Function() whileSuspended);

/// Runs [print] so that the PDFium calls of the `printing` plugin, which on
/// Windows spools on its own thread, never overlap pdfrx's PDFium worker.
///
/// pdfrx is held only after [onLayout] returns: the document may be built
/// with pdfrx, and from then on the plugin only spools it.
Future<bool> printWithExclusivePdfium(
  LayoutCallback onLayout,
  Future<bool> Function(LayoutCallback onLayout) print, {
  @visibleForTesting SuspendPdfium? suspend,
  @visibleForTesting bool? enabled,
}) async {
  if (!(enabled ?? Platform.isWindows)) return print(onLayout);
  final suspendPdfium = suspend ?? _suspendPdfrxWorker;
  final release = Completer<void>();
  Future<void>? held;

  Future<Uint8List> guardedLayout(PdfPageFormat format) async {
    final bytes = await onLayout(format);
    if (held == null) {
      final acquired = Completer<void>();
      held = suspendPdfium(() {
        acquired.complete();
        return release.future;
      });
      await Future.any([acquired.future, held!]);
    }
    return bytes;
  }

  try {
    return await print(guardedLayout);
  } finally {
    release.complete();
    await held;
  }
}

Future<void> _suspendPdfrxWorker(Future<void> Function() whileSuspended) =>
    PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(
      whileSuspended,
    );
