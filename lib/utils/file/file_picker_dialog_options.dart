import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_darwin/file_picker_darwin.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:windows_file_picker/windows_file_picker.dart';

/// דיאלוגי המערכת נפתחים מודאליים מעל חלון האפליקציה. ההגדרה נפרדת לכל
/// פלטפורמה, ושתיהן חייבות להיקבע יחד — אחרת הדיאלוג מודאלי רק באחת מהן.
/// ב-Windows הבעלים הוא החלון של [context] (או הפעיל), ולא החלון שבחזית.
WindowsOptions modalWindowsOptions([BuildContext? context]) =>
    FilePickerWindowsOptions(
      lockParentWindow: true,
      parentWindowHandle: DialogOwner.hwnd(context: context),
    );

const kModalLinuxOptions = LinuxOptions(lockParentWindow: true);

/// מריץ את [action] עם בורר שבעליו הוא החלון של [context]. ב-macOS זה בורר
/// משלו לכל בקשה; חלון שנסגר בינתיים מבטל את הבקשה, כמו ב-Windows.
Future<T?> withFilePickerOwner<T>(
  BuildContext? context,
  Future<T?> Function(FilePickerPlatform picker) action,
) async {
  if (context != null && !context.mounted) return null;
  if (Platform.isWindows &&
      context != null &&
      DialogOwner.hwnd(context: context) == null) {
    return null;
  }
  final viewId = context == null ? null : View.maybeOf(context)?.viewId;
  if (!Platform.isMacOS || viewId == null) {
    return action(FilePickerPlatform.instance);
  }
  try {
    return await action(FilePickerDarwin(viewId: viewId));
  } on PlatformException catch (e) {
    if (e.code == 'window_not_found') return null;
    rethrow;
  }
}
