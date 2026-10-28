import 'package:flutter/material.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

Future<String?> passwordDialog(BuildContext context) async {
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return const InputDialog(
        title: 'הזנת סיסמה',
        labelText: 'סיסמה',
        keyboardType: TextInputType.visiblePassword,
        obscureText: true,
        confirmText: 'אישור',
        cancelText: 'ביטול',
      );
    },
  );
}
