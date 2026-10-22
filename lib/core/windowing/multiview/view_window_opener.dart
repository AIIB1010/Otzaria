import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:window_manager/window_manager.dart';

/// מסגרת פיזית, כמו ב-[WindowOpener.openWindow].
typedef PhysicalBounds = ({int left, int top, int width, int height});

/// חלון שנסגר ואפשר לשחזר ב-Ctrl+Shift+T: סשן של חלון Dart, או החלון הראשי.
class _ClosedWindow {
  const _ClosedWindow.view(this.session) : isMain = false;
  const _ClosedWindow.main() : session = null, isMain = true;

  final WindowSession? session;
  final bool isMain;
}

/// פתיחת חלונות כחלונות Dart באותו מנוע (ריבוי תצוגות), במקום תהליך-מנוע
/// חדש לכל חלון. המשבצות נקבעות כאן, ולכן אין מרוץ על המשבצת הפנויה.
class ViewWindowOpener implements WindowOpener {
  ViewWindowOpener({
    this._registry,
    ViewWindowNative? native,
    this._sessions,
    Future<bool> Function()? isMainWindowVisible,
    Future<bool> Function()? restoreMainWindow,
    Size Function()? defaultSize,
    this.firstFrameTimeout = const Duration(seconds: 20),
  }) : _native = native ?? const Win32ViewWindowNative(),
       _isMainWindowVisible = isMainWindowVisible ?? windowManager.isVisible,
       _restoreMainWindow =
           restoreMainWindow ??
           const MultiWindowService().restoreLastClosedWindow,
       _defaultSize = defaultSize ?? _implicitViewSize;

  static final ViewWindowOpener instance = ViewWindowOpener();

  /// כמו ב-runner: מסגרת קטנה מזה אינה הצמדה אמיתית.
  static const int minBoundsWidth = 320;
  static const int minBoundsHeight = 240;

  /// כמה חלונות סגורים נזכרים לשחזור.
  static const int closedLimit = 10;

  final ViewWindowRegistry? _registry;
  final ViewWindowNative _native;
  final WindowSessionStore? _sessions;
  final Future<bool> Function() _isMainWindowVisible;
  final Future<bool> Function() _restoreMainWindow;
  final Size Function() _defaultSize;
  final Duration firstFrameTimeout;

  ViewWindowRegistry get registry => _registry ?? ViewWindowRegistry.instance;
  WindowSessionStore get _store => _sessions ?? WindowSessionStore.instance;

  /// יציאה מהתוכנה כשנסגר החלון האחרון שעל המסך; נקבע ב-main.
  Future<void> Function()? endProcess;

  /// משבצות שממתינות לשחזור בהפעלה; חלון חדש אינו תופס אותן.
  final Set<int> _pendingRestore = {};
  final List<_ClosedWindow> _closed = [];
  Future<void> _queue = Future.value();
  Future<void> _closeQueue = Future.value();

  static Size _implicitViewSize() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || view.devicePixelRatio <= 0) {
      return const Size(1280, 800);
    }
    final size = view.physicalSize / view.devicePixelRatio;
    return size.isEmpty ? const Size(1280, 800) : size;
  }

  /// פתיחה אחת בכל רגע: משבצת פנויה ומחיקת השארית שלה אינן מתנגשות.
  /// כשל הוא false, כמו במודל הקודם: הקוראים אינם מצפים לחריגה.
  Future<bool> _serialized(Future<bool> Function() body) {
    final result = _queue.then((_) => body()).catchError((Object e) {
      debugPrint('ViewWindowOpener failed: $e');
      return false;
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// בדיקת החלון האחרון והסגירה חייבות להיות יחידה אחת בין כל החלונות.
  Future<bool> serializeClose(Future<bool> Function() close) {
    final result = _closeQueue.then((_) => close());
    _closeQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    PhysicalBounds? bounds,
    bool inheritPlacement = true,
  }) => _serialized(() async {
    if (!registry.canOpenAnotherWindow) return false;
    final slot = registry.freeSlot(excluding: _pendingRestore);
    // שארית מקריסה במשבצת הזו אינה שייכת לחלון החדש.
    await _store.delete(slot);
    return _open(
      slot: slot,
      tab: tab == null ? null : OpenedTab.fromJson(tab.toTransferJson()),
      origin: origin,
      bounds: bounds,
      deleteRowOnTimeout: true,
    );
  });

  @override
  Future<bool> openEmptyWindow() async {
    if (!await canOpenAnotherWindow()) {
      await reportOpenWindowFailure();
      return false;
    }
    final opened = await openWindow();
    if (!opened) await reportOpenWindowFailure();
    return opened;
  }

  /// שומר את [slots] לשחזור עוד לפני שהוא מתחיל, כדי שחלון חדש לא ימחק אותן.
  void reserveForRestore(Iterable<int> slots) => _pendingRestore.addAll(slots);

  /// "שחזר את כל החלונות": חלון לכל משבצת, עם הסשן והגבולות שלה. משבצת
  /// שנכשלה נשארת שמורה, כדי שהסשן שלה יאומץ בהפעלה הבאה ולא יימחק.
  Future<void> restoreAllWindows(List<int> slots) async {
    reserveForRestore(slots);
    for (final slot in slots) {
      if (!await _serialized(() => _openSession(slot))) {
        debugPrint('שחזור חלונות נעצר: פתיחת חלון למשבצת $slot נכשלה');
        return;
      }
      _pendingRestore.remove(slot);
    }
  }

  Future<bool> _openSession(int slot) async {
    if (registry.isSlotOpen(slot) || !registry.canOpenAnotherWindow) {
      return false;
    }
    final session = await _store.load(slot);
    final saved = WindowBounds.decode(session?.boundsJson);
    return _open(
      slot: slot,
      bounds: saved?.toPhysical(),
      maximized: saved?.maximized ?? false,
    );
  }

  @override
  Future<bool> restoreLastClosedWindow() => _serialized(() async {
    while (_closed.isNotEmpty) {
      final closed = _closed.last;
      if (closed.isMain) {
        // false: הראשי כבר גלוי, ממשיכים לחלון הקודם.
        if (await _restoreMainWindow()) {
          _closed.remove(closed);
          return true;
        }
        _closed.remove(closed);
        continue;
      }
      final session = closed.session!;
      if (!registry.canOpenAnotherWindow) {
        await reportOpenWindowFailure();
        return false;
      }
      final slot = registry.freeSlot(excluding: _pendingRestore);
      await _store.delete(slot);
      await _store.save(
        slot,
        tabsJson: session.tabsJson,
        currentIndex: session.currentIndex,
      );
      if (session.activeWorkspaceId != null) {
        await _store.saveActiveWorkspace(slot, session.activeWorkspaceId);
      }
      if (session.boundsJson != null) {
        await _store.saveBounds(slot, session.boundsJson);
      }
      if (await _openSession(slot)) {
        _closed.remove(closed);
        return true;
      }
      // נכשל: השורה שנכתבה כאן אינה של אף חלון, והחלון נשאר לניסיון חוזר.
      await _store.delete(slot);
      return false;
    }
    return false;
  });

  @override
  Future<bool> canOpenAnotherWindow() async => registry.canOpenAnotherWindow;

  /// החלון הראשי נספר תמיד, גם מוסתר: הוא חי ותופס מקום בתקרה.
  @override
  Future<({int count, int max, int engines})?> windowCount() async => (
    count: registry.windows.length + 1,
    max: ViewWindowRegistry.maxWindows,
    engines: 1,
  );

  @override
  Future<void> reportOpenWindowFailure() async {
    final info = await windowCount();
    if (info != null && info.count >= info.max) {
      UiSnack.show(WindowMessages.windowLimitReached(info.max));
    } else {
      UiSnack.showError(WindowMessages.openWindowFailed);
    }
  }

  Future<bool> _open({
    required int slot,
    OpenedTab? tab,
    ({int x, int y})? origin,
    PhysicalBounds? bounds,
    bool maximized = false,
    bool deleteRowOnTimeout = false,
  }) async {
    final entry = registry.open(
      size: _defaultSize(),
      initialTab: tab,
      slot: slot,
    );
    if (entry == null) {
      tab?.dispose();
      return false;
    }
    _place(entry, origin: origin, bounds: bounds);
    try {
      await entry.firstFrame.timeout(firstFrameTimeout);
    } on TimeoutException {
      // הקורא לא יסיר את הכרטיסיה מהמקור, ולכן החלון לא יוצג אחר כך עם עותק.
      entry.endSession();
      // עותק שלא נקלט עדיין בעץ החלון אינו של אף אחד.
      entry.takeInitialTab()?.dispose();
      entry.handle.destroy();
      // סשן משוחזר נשאר: הוא יאומץ בהפעלה הבאה.
      if (deleteRowOnTimeout) await _store.delete(slot);
      return false;
    }
    if (maximized) entry.handle.setMaximized(true);
    return true;
  }

  /// לפני הפריים הראשון, כשהחלון עוד מוסתר. בלי מיקום — ברירת המחדל של המערכת.
  void _place(
    ViewWindowEntry entry, {
    ({int x, int y})? origin,
    PhysicalBounds? bounds,
  }) {
    final hwnd = entry.handle.hwnd;
    if (hwnd == null) return;
    if (bounds != null &&
        bounds.width >= minBoundsWidth &&
        bounds.height >= minBoundsHeight) {
      final target = Rect.fromLTWH(
        bounds.left.toDouble(),
        bounds.top.toDouble(),
        bounds.width.toDouble(),
        bounds.height.toDouble(),
      );
      _native.setWindowRect(hwnd, target);
      // מסך עם DPI אחר משנה את הגודל ב-WM_DPICHANGED; שם כבר אין שינוי.
      if (_native.windowRect(hwnd) != target) {
        _native.setWindowRect(hwnd, target);
      }
      return;
    }
    if (origin == null) return;
    final current = _native.windowRect(hwnd);
    if (current == null) return;
    final x = origin.x.toDouble(), y = origin.y.toDouble();
    _native.setWindowRect(
      hwnd,
      Rect.fromLTWH(x, y, current.width, current.height),
    );
    // המעבר למסך אחר עשוי לשנות את הגודל לפי ה-DPI שלו; מהדקים אחריו.
    final moved = _native.windowRect(hwnd) ?? current;
    final area = _native.workArea(hwnd);
    if (area == null) return;
    _native.setWindowRect(hwnd, clampToArea(moved, area));
  }

  /// כמו `OriginForDrop` ב-runner: מזיז לתוך אזור העבודה בלי לשנות גודל.
  @visibleForTesting
  static Rect clampToArea(Rect rect, Rect area) {
    var left = rect.left, top = rect.top;
    if (left + rect.width > area.right) left = area.right - rect.width;
    if (left < area.left) left = area.left;
    if (top + rect.height > area.bottom) top = area.bottom - rect.height;
    if (top < area.top) top = area.top;
    return Rect.fromLTWH(left, top, rect.width, rect.height);
  }

  /// האם [entry] הוא החלון האחרון שעל המסך, כלומר סגירתו היא יציאה.
  Future<bool> isLastVisibleWindow(ViewWindowEntry entry) async {
    if (registry.windows.any((w) => w != entry)) return false;
    try {
      return !await _isMainWindowVisible();
    } catch (e) {
      // לא ידוע: לא לצאת, החלון נסגר לבדו.
      debugPrint('isMainWindowVisible failed: $e');
      return false;
    }
  }

  /// נקרא אחרי ה-flush ולפני מחיקת הסשן, כדי ש-Ctrl+Shift+T יחזיר אותו.
  Future<void> rememberClosed(int slot) async {
    try {
      final session = await _store.load(slot);
      if (session != null) _push(_ClosedWindow.view(session));
    } catch (e) {
      debugPrint('rememberClosed failed: $e');
    }
  }

  /// לפני הסתרת החלון הראשי: חלון שעוד נפתח מוסתר עד הפריים הראשון,
  /// וה-runner משאיר את התהליך חי רק בזכות חלון Dart גלוי.
  Future<void> beforeMainWindowHides() async {
    _push(const _ClosedWindow.main());
    final pending = [for (final w in registry.windows) w.firstFrame];
    if (pending.isEmpty) return;
    await Future.wait(pending).timeout(firstFrameTimeout, onTimeout: () => []);
  }

  void _push(_ClosedWindow closed) {
    _closed.add(closed);
    if (_closed.length > closedLimit) _closed.removeAt(0);
  }

  @visibleForTesting
  int get closedCountForTest => _closed.length;

  @visibleForTesting
  Set<int> get pendingRestoreForTest => Set.unmodifiable(_pendingRestore);
}
