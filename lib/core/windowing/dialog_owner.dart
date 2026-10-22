import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';

/// החלון שדיאלוג מערכת (קבצים, הדפסה) צריך להיות מודאלי אליו. עם חלונות Dart
/// ה-runner מכיר רק את הראשי, שעשוי להיות מוסתר — ואז הדיאלוג חסר בעלים נכון.
abstract final class DialogOwner {
  static int? _mainWindowHwnd;

  /// ה-HWND של החלון הראשי; נקבע בעלייה, אחרי window_manager.
  static set mainWindowHwnd(int? hwnd) => _mainWindowHwnd = hwnd;

  /// החלון של [context], ובלעדיו — החלון הפעיל. `null` כשאין חלון גלוי
  /// מוכר: הפלאגין נופל אז לחלון שבחזית, כמו קודם.
  static int? hwnd({
    BuildContext? context,
    ViewWindowRegistry? registry,
    bool? isMainShown,
  }) {
    final id = context != null
        ? AppWindowKeys.of(context).id
        : AppWindowKeys.current.id;
    if (MultiViewMode.enabled && id != AppWindowId.primary) {
      final entry = (registry ?? ViewWindowRegistry.instance).windows
          .where((w) => w.id == id)
          .firstOrNull;
      final hwnd = entry?.handle.hwnd;
      if (hwnd != null) return hwnd;
    }
    // ראשי מוסתר אינו בעלים: דיאלוג שלו לא היה מופיע מעל חלון שרואים.
    final mainShown =
        !MultiViewMode.enabled ||
        (isMainShown ?? InProcessTabDrops.instance.isMainShown);
    return mainShown ? _mainWindowHwnd : null;
  }

  @visibleForTesting
  static void resetForTest() => _mainWindowHwnd = null;
}
