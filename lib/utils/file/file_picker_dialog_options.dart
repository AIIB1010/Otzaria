import 'package:file_picker/file_picker.dart';
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
