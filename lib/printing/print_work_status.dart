import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';

const kPrintFailureAutoDismiss = Duration(seconds: 8);

/// עבודת הדפסה שנמסרה למדפסת, בכרטיס חיווי העבודה עד שהיא מסתיימת.
///
/// אינה תלויה במסך ההדפסה, שנסגר עם המסירה.
class PrintWorkStatus {
  PrintWorkStatus._(this._cubit, this.id, this.documentName);

  static int _nextId = 0;
  static int _activeJobs = 0;

  /// האם עבודת הדפסה עדיין נשלחת למדפסת.
  static bool get hasActiveJobs => _activeJobs > 0;

  final WorkStatusCubit? _cubit;
  final String id;
  final String documentName;
  bool _finished = false;

  /// [cubit] — `null` כשאין חיווי עבודה בעץ; הספירה נשמרת גם אז.
  factory PrintWorkStatus.start(
    WorkStatusCubit? cubit, {
    required String documentName,
    String? printerName,
  }) {
    final status = PrintWorkStatus._(
      cubit,
      'print_job_${_nextId++}',
      documentName,
    );
    _activeJobs++;
    cubit?.upsert(
      WorkStatusItem(
        id: status.id,
        title: PdfMessages.printWorkTitle,
        message: printerName == null
            ? PdfMessages.printSpooling
            : PdfMessages.printSpoolingTo(printerName),
        detail: documentName,
      ),
    );
    return status;
  }

  /// [printed] `false` בלי שגיאה — המשתמש ביטל, למשל בבחירת קובץ הפלט.
  void complete(bool printed) {
    if (!_finish()) return;
    _cubit?.remove(id);
    if (printed) UiSnack.show(PdfMessages.printSent);
  }

  void fail(Object error, StackTrace stack) {
    if (!_finish()) return;
    _cubit?.upsert(
      WorkStatusItem(
        id: id,
        title: PdfMessages.printWorkTitle,
        message: PdfMessages.printWorkFailed,
        detail: documentName,
        kind: WorkStatusKind.failed,
        autoDismissAfter: kPrintFailureAutoDismiss,
      ),
    );
    UiSnack.showError(PdfMessages.printError(error));
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'printing'),
    );
  }

  bool _finish() {
    if (_finished) return false;
    _finished = true;
    _activeJobs--;
    return true;
  }
}

/// מאשר סגירה כשהדפסה עדיין נשלחת: סגירת החלון עלולה לקטוע אותה.
Future<bool> confirmCloseWhilePrinting() async {
  if (!PrintWorkStatus.hasActiveJobs) return true;
  final context = navigatorKey.currentContext;
  if (context == null) return true;
  final confirmed = await showConfirmationDialog(
    context: context,
    title: PdfMessages.closeWhilePrintingTitle,
    content: PdfMessages.closeWhilePrinting,
    confirmText: PdfMessages.closeWhilePrintingConfirm,
    isDangerous: true,
  );
  return confirmed == true;
}
