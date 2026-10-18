import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/print_work_status.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';

void main() {
  group('PrintWorkStatus', () {
    test('כל עבודה מקבלת פריט משלה, והספירה יורדת בסיום', () {
      final cubit = WorkStatusCubit();
      addTearDown(cubit.close);

      final first = PrintWorkStatus.start(cubit, documentName: 'א');
      final second = PrintWorkStatus.start(
        cubit,
        documentName: 'ב',
        printerName: 'HP',
      );

      expect(first.id, isNot(second.id));
      expect(PrintWorkStatus.hasActiveJobs, isTrue);
      expect(cubit.state.items[first.id]!.message, PdfMessages.printSpooling);
      expect(
        cubit.state.items[second.id]!.message,
        PdfMessages.printSpoolingTo('HP'),
      );

      first.complete(false);
      expect(cubit.state.items.keys, [second.id]);
      expect(PrintWorkStatus.hasActiveJobs, isTrue);

      second.complete(false);
      second.complete(false);
      expect(cubit.state.items, isEmpty);
      expect(PrintWorkStatus.hasActiveJobs, isFalse);
    });

    test('בלי חיווי עבודה בעץ הספירה עדיין נשמרת', () {
      final job = PrintWorkStatus.start(null, documentName: 'א');
      expect(PrintWorkStatus.hasActiveJobs, isTrue);
      job.complete(false);
      expect(PrintWorkStatus.hasActiveJobs, isFalse);
    });

    testWidgets('כשל משאיר פריט כשל שיורד מעצמו', (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
      );
      final cubit = WorkStatusCubit();
      addTearDown(cubit.close);
      final job = PrintWorkStatus.start(cubit, documentName: 'א');

      job.fail(StateError('spooler'), StackTrace.current);
      expect(tester.takeException(), isA<StateError>());

      final item = cubit.state.items[job.id]!;
      expect(item.kind, WorkStatusKind.failed);
      expect(PrintWorkStatus.hasActiveJobs, isFalse);
      await tester.pump(kPrintFailureAutoDismiss);
      expect(cubit.state.items, isEmpty);
      // מעבר לזמן התצוגה של UiSnack.
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('confirmCloseWhilePrinting', () {
    Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    testWidgets('בלי הדפסה פעילה — מאשר בלי דיאלוג', (tester) async {
      await pumpApp(tester);
      expect(await confirmCloseWhilePrinting(), isTrue);
      expect(find.text(PdfMessages.closeWhilePrinting), findsNothing);
    });

    for (final confirm in [true, false]) {
      testWidgets('בהדפסה פעילה — שואל, ומחזיר את הבחירה ($confirm)', (
        tester,
      ) async {
        await pumpApp(tester);
        final job = PrintWorkStatus.start(null, documentName: 'א');
        addTearDown(() => job.complete(false));

        final result = confirmCloseWhilePrinting();
        await tester.pumpAndSettle();
        expect(find.text(PdfMessages.closeWhilePrinting), findsOneWidget);

        await tester.tap(
          find.text(confirm ? PdfMessages.closeWhilePrintingConfirm : 'ביטול'),
        );
        await tester.pumpAndSettle();
        expect(await result, confirm);
      });
    }
  });
}
