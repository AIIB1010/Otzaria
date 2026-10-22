import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';

/// יוצר חלון נייטיב; ניתן להחלפה בבדיקות.
typedef ViewWindowFactory =
    ViewWindowHandle Function({
      required Size size,
      required String title,
      required void Function(ViewWindowHandle handle) onCloseRequested,
      required void Function(ViewWindowHandle handle) onDestroyed,
    });

/// חלון Dart פתוח. [slot] הוא משבצת הסשן שלו (1 שמורה לחלון הראשי).
class ViewWindowEntry {
  ViewWindowEntry._(this.slot, this.handle);

  final int slot;
  final ViewWindowHandle handle;
  final Completer<void> _firstFrame = Completer<void>();

  /// מסתיים בפריים הראשון של החלון.
  Future<void> get firstFrame => _firstFrame.future;

  void markFirstFrame() {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }
}

/// רשימת חלונות ה-Dart של התהליך. יושבת מעל RestartWidget, כדי שהחלונות
/// ישרדו אתחול מחדש ורק העצים שבתוכם ייבנו מחדש.
class ViewWindowRegistry extends ChangeNotifier {
  ViewWindowRegistry({ViewWindowFactory? factory})
    : _factory = factory ?? createViewWindow;

  static final ViewWindowRegistry instance = ViewWindowRegistry();

  /// תקרה רכה, כולל החלון הראשי.
  static const int maxWindows = 8;

  final ViewWindowFactory _factory;
  final List<ViewWindowEntry> _windows = [];

  List<ViewWindowEntry> get windows => List.unmodifiable(_windows);

  bool get canOpenAnotherWindow => _windows.length + 1 < maxWindows;

  /// פותח חלון ריק; null כשהגענו לתקרה.
  ViewWindowEntry? open({required Size size, String title = 'אוצריא'}) {
    if (!canOpenAnotherWindow) return null;
    late final ViewWindowEntry entry;
    final handle = _factory(
      size: size,
      title: title,
      onCloseRequested: (_) => entry.handle.destroy(),
      onDestroyed: (_) => _remove(entry),
    );
    entry = ViewWindowEntry._(_freeSlot(), handle);
    _windows.add(entry);
    notifyListeners();
    return entry;
  }

  int _freeSlot() {
    final used = {for (final w in _windows) w.slot};
    var slot = 2;
    while (used.contains(slot)) {
      slot++;
    }
    return slot;
  }

  void _remove(ViewWindowEntry entry) {
    if (!_windows.remove(entry)) return;
    notifyListeners();
    // הבקר משוחרר רק אחרי שהעץ שלו פורק בפריים הבא.
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => entry.handle.dispose(),
    );
    SchedulerBinding.instance.scheduleFrame();
  }
}
