import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/exclusive_pdfium_print.dart';
import 'package:pdf/pdf.dart';
import 'package:pdfrx/pdfrx.dart';

/// Stands in for pdfrx's worker: work waits while it is suspended.
class _FakeWorker {
  final events = <String>[];
  Completer<void>? _resumed;

  Future<void> suspend(Future<void> Function() whileSuspended) async {
    events.add('suspend');
    _resumed = Completer<void>();
    try {
      await whileSuspended();
    } finally {
      events.add('resume');
      _resumed!.complete();
      _resumed = null;
    }
  }

  Future<void> work(String name) async {
    await _resumed?.future;
    events.add(name);
  }
}

void main() {
  test('pdfrx נעצר רק אחרי onLayout, ומשתחרר כשההדפסה מסתיימת', () async {
    final worker = _FakeWorker();
    final spool = Completer<bool>();
    late Future<void> concurrent;

    final printed = printWithExclusivePdfium(
      (format) async {
        // Building the document uses pdfrx; it must not wait on the suspension.
        await worker.work('layout uses pdfrx');
        return Uint8List(0);
      },
      (onLayout) async {
        await onLayout(PdfPageFormat.a4);
        worker.events.add('spool');
        concurrent = worker.work('preview render');
        await Future<void>.delayed(Duration.zero);
        worker.events.add('spool done');
        spool.complete(true);
        return spool.future;
      },
      suspend: worker.suspend,
      enabled: true,
    );

    expect(await printed, isTrue);
    await concurrent;
    expect(worker.events, [
      'layout uses pdfrx',
      'suspend',
      'spool',
      'spool done',
      'resume',
      'preview render',
    ]);
  });

  test('כשל ב-onLayout אינו עוצר את pdfrx', () async {
    final worker = _FakeWorker();
    final printed = printWithExclusivePdfium(
      (format) => throw StateError('layout'),
      (onLayout) async {
        await onLayout(PdfPageFormat.a4);
        return true;
      },
      suspend: worker.suspend,
      enabled: true,
    );
    await expectLater(printed, throwsStateError);
    expect(worker.events, isEmpty);
  });

  test('מחוץ ל-Windows ההדפסה עוברת כמו שהיא', () async {
    var suspended = false;
    final printed = await printWithExclusivePdfium(
      (format) async => Uint8List(0),
      (onLayout) async {
        await onLayout(PdfPageFormat.a4);
        return true;
      },
      suspend: (action) async {
        suspended = true;
        await action();
      },
      enabled: false,
    );
    expect(printed, isTrue);
    expect(suspended, isFalse);
  });

  test(
    'עם ה-worker האמיתי של pdfrx: עבודה ממתינה להדפסה, בלי קיפאון',
    () async {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      await pdfrxFlutterInitialize();
      final events = <String>[];
      late Future<void> render;

      final printed = await printWithExclusivePdfium(
        (format) async {
          await PdfrxEntryFunctions.instance.compute((_) => 1, null);
          events.add('layout');
          return Uint8List(0);
        },
        (onLayout) async {
          await onLayout(PdfPageFormat.a4);
          render = PdfrxEntryFunctions.instance
              .compute((_) => 1, null)
              .then((_) => events.add('render'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
          events.add('spool done');
          return true;
        },
        enabled: true,
      );
      await render.timeout(const Duration(seconds: 10));
      expect(printed, isTrue);
      expect(events, ['layout', 'spool done', 'render']);
    },
  );
}
