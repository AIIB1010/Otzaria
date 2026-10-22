import 'dart:async';

import 'package:flutter/material.dart';

/// כמו [showDialog], אבל מחזיר `null` כשהדיאלוג פורק בלי תשובה. Flutter אינו
/// משלים את ה-Future כשה-Navigator נהרס (אתחול מחדש), והממתין היה נתקע לנצח.
Future<T?> showDialogUntilTornDown<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final tornDown = Completer<T?>();
  final shown = showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => _TearDownSignal(
      onDispose: () {
        if (!tornDown.isCompleted) tornDown.complete(null);
      },
      child: builder(dialogContext),
    ),
  );
  // אחרי pop רגיל התשובה קודמת לפירוק (שמגיע רק בסוף אנימציית היציאה).
  return Future.any([shown, tornDown.future]);
}

class _TearDownSignal extends StatefulWidget {
  const _TearDownSignal({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_TearDownSignal> createState() => _TearDownSignalState();
}

class _TearDownSignalState extends State<_TearDownSignal> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
