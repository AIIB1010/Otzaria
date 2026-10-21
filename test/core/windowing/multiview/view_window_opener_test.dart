import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../../test_helpers/fake_view_window.dart';

/// סשנים בזיכרון: בלי קובץ אמיתי בתוך FakeAsync.
class _MemorySessions extends WindowSessionStore {
  final Map<int, WindowSession> rows = {};
  final List<int> boundsWrites = [];

  @override
  Future<void> save(
    int slot, {
    required String tabsJson,
    required int currentIndex,
  }) async {
    final old = rows[slot];
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: tabsJson,
      currentIndex: currentIndex,
      activeWorkspaceId: old?.activeWorkspaceId,
      boundsJson: old?.boundsJson,
    );
  }

  WindowSession _row(int slot) =>
      rows[slot] ?? WindowSession(slot: slot, tabsJson: '[]', currentIndex: 0);

  @override
  Future<void> saveActiveWorkspace(int slot, String? workspaceId) async {
    final old = _row(slot);
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: old.tabsJson,
      currentIndex: old.currentIndex,
      activeWorkspaceId: workspaceId,
      boundsJson: old.boundsJson,
    );
  }

  @override
  Future<void> saveBounds(int slot, String? boundsJson) async {
    boundsWrites.add(slot);
    final old = _row(slot);
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: old.tabsJson,
      currentIndex: old.currentIndex,
      activeWorkspaceId: old.activeWorkspaceId,
      boundsJson: boundsJson,
    );
  }

  @override
  Future<WindowSession?> load(int slot) async => rows[slot];

  @override
  Future<void> delete(int slot) async => rows.remove(slot);
}

void main() {
  setUp(() => MultiViewMode.debugOverride = true);

  tearDown(() {
    MultiViewMode.debugOverride = null;
    WindowOpener.debugOverride = null;
    AppWindowKeys.resetForTest();
  });

  late FakeViewWindows windows;
  late _MemorySessions sessions;
  late bool mainVisible;
  late int mainRestores;

  ViewWindowOpener makeOpener(WidgetTester tester, {Duration? timeout}) {
    windows = FakeViewWindows(tester);
    sessions = _MemorySessions();
    mainVisible = true;
    mainRestores = 0;
    return ViewWindowOpener(
      registry: windows.registry,
      native: windows.native,
      sessions: sessions,
      isMainWindowVisible: () async => mainVisible,
      restoreMainWindow: () async {
        mainRestores++;
        return true;
      },
      defaultSize: () => const Size(1000, 700),
      firstFrameTimeout: timeout ?? const Duration(seconds: 20),
    );
  }

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
    MultiViewHost(registry: windows.registry, child: const SizedBox()),
  );

  /// מריץ פעולה עד שהחלון שלה מצייר פריים ראשון.
  Future<T> settle<T>(WidgetTester tester, Future<T> future) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    return future;
  }

  testWidgets('הדגל קובע את המימוש של WindowOpener.current', (tester) async {
    expect(WindowOpener.current, same(ViewWindowOpener.instance));
    MultiViewMode.debugOverride = false;
    expect(WindowOpener.current, isA<MultiWindowService>());
  });

  testWidgets('openWindow: חלון עם כרטיסיה, שארית במשבצת נמחקת', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    sessions.rows[2] = const WindowSession(
      slot: 2,
      tabsJson: '[{"stale":true}]',
      currentIndex: 0,
    );
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');

    expect(await settle(tester, opener.openWindow(tab: tab)), isTrue);

    final entry = windows.registry.windows.single;
    expect(entry.slot, 2);
    expect(entry.openedWithTab, isTrue);
    expect(sessions.rows[2], isNull, reason: 'שארית מקריסה אינה נטענת');
    expect(windows.native.hooked, [windows.handleOf(entry).fakeHwnd]);
    final count = (await opener.windowCount())!;
    expect((count.count, count.max, count.engines), (2, 8, 1));
  });

  testWidgets('מיקום לפני הפריים הראשון: מסגרת, מסגרת קטנה מדי, פינה', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    windows.native.area = const Rect.fromLTWH(0, 0, 1920, 1040);

    expect(
      await settle(
        tester,
        opener.openWindow(
          bounds: (left: 960, top: 0, width: 960, height: 1040),
        ),
      ),
      isTrue,
    );
    expect(windows.native.rects[100], const Rect.fromLTWH(960, 0, 960, 1040));

    // תצוגת גרירה בגודל כרטיסיה אינה מסגרת חלון.
    expect(
      await settle(
        tester,
        opener.openWindow(bounds: (left: 5, top: 5, width: 176, height: 40)),
      ),
      isTrue,
    );
    expect(windows.native.rects[101], isNull);

    // פינה בקצה המסך: הגודל נשמר והחלון מהודק לאזור העבודה.
    windows.native.rects[102] = const Rect.fromLTWH(0, 0, 1000, 700);
    expect(
      await settle(tester, opener.openWindow(origin: (x: 1500, y: 900))),
      isTrue,
    );
    expect(windows.native.rects[102], const Rect.fromLTWH(920, 340, 1000, 700));
  });

  testWidgets('תקרה: 8 כולל הראשי; משבצת שהתפנתה נלקחת שוב', (tester) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    for (var i = 0; i < 7; i++) {
      expect(await settle(tester, opener.openWindow()), isTrue);
    }
    expect(await opener.canOpenAnotherWindow(), isFalse);
    expect(await settle(tester, opener.openWindow()), isFalse);
    final count = (await opener.windowCount())!;
    expect(count.count >= count.max, isTrue, reason: 'הודעת התקרה');

    final slot3 = windows.registry.windows.firstWhere((w) => w.slot == 3);
    windows.stubOf(slot3).destroy();
    await tester.pump();
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(windows.registry.windows.last.slot, 3);
  });

  testWidgets('פריים ראשון שלא הגיע: false, החלון נהרס והסשן נמחק', (
    tester,
  ) async {
    final opener = makeOpener(tester, timeout: const Duration(seconds: 1));
    // בלי MultiViewHost אין מי שיצייר את החלון.
    await tester.pumpWidget(const SizedBox());
    final future = opener.openWindow();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await future, isFalse);
    expect(windows.handles.single.stub.destroyed, isTrue);
    expect(windows.registry.windows, isEmpty);
    expect(sessions.rows[2], isNull);
  });

  testWidgets('שחזור כל החלונות: משבצת וגבולות שמורים; פתיחה במקביל לא גונבת', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    sessions.rows[2] = WindowSession(
      slot: 2,
      tabsJson: '[]',
      currentIndex: 0,
      boundsJson: const WindowBounds(
        left: 10,
        top: 20,
        width: 800,
        height: 600,
        dpr: 1.5,
      ).encode(),
    );
    sessions.rows[3] = WindowSession(
      slot: 3,
      tabsJson: '[]',
      currentIndex: 0,
      boundsJson: const WindowBounds(maximized: true).encode(),
    );

    final restore = opener.restoreAllWindows([2, 3]);
    final fresh = opener.openWindow();
    await settle(tester, restore);
    expect(await settle(tester, fresh), isTrue);

    final bySlot = {for (final w in windows.registry.windows) w.slot: w};
    expect(bySlot.keys.toSet(), {2, 3, 4});
    expect(sessions.rows[2], isNotNull, reason: 'הסשן שוחזר ולא נמחק');
    expect(sessions.rows[3], isNotNull);
    expect(
      windows.native.rects[windows.handleOf(bySlot[2]!).fakeHwnd],
      const Rect.fromLTWH(15, 30, 1200, 900),
    );
    expect(windows.stubOf(bySlot[3]!).maximized, isTrue);
    expect(opener.pendingRestoreForTest, isEmpty);
  });

  testWidgets('Ctrl+Shift+T: חלון שנסגר חוזר עם הסשן שלו; אחריו הראשי', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    await sessions.save(2, tabsJson: '["a","b"]', currentIndex: 1);
    // הראשי הוסתר קודם, ולכן הוא השני בתור.
    await opener.beforeMainWindowHides();

    final flow = ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: sessions.delete,
      opener: opener,
    );
    expect(await settle(tester, flow.run()), isTrue);
    await tester.pump();
    expect(windows.registry.windows, isEmpty);
    expect(sessions.rows[2], isNull);

    expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
    expect(windows.registry.windows.single.slot, 2);
    expect(sessions.rows[2]!.tabsJson, '["a","b"]');
    expect(sessions.rows[2]!.currentIndex, 1);
    expect(mainRestores, 0);

    expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
    expect(mainRestores, 1);
    expect(await settle(tester, opener.restoreLastClosedWindow()), isFalse);
  });

  testWidgets('החלון האחרון על המסך (הראשי מוסתר): סגירה היא יציאה', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    var exits = 0;
    opener.endProcess = () async => exits++;
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final [a, b] = windows.registry.windows;
    await sessions.save(a.slot, tabsJson: '[]', currentIndex: 0);
    await sessions.save(b.slot, tabsJson: '[]', currentIndex: 0);
    mainVisible = false;
    ViewWindowCloseFlow flowOf(ViewWindowEntry entry) => ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: sessions.delete,
      opener: opener,
    );

    // עוד חלון Dart פתוח: סגירה רגילה.
    expect(await opener.isLastVisibleWindow(a), isFalse);
    expect(await settle(tester, flowOf(a).run()), isTrue);
    await tester.pump();
    expect(exits, 0);
    expect(sessions.rows[a.slot], isNull);

    // האחרון: מסלול היציאה, בלי מחיקת הסשן ובלי הריסה (בוטל או יוצא).
    expect(await opener.isLastVisibleWindow(b), isTrue);
    expect(await settle(tester, flowOf(b).run()), isFalse);
    expect(exits, 1);
    expect(AppWindowKeys.current, same(b.keys));
    expect(sessions.rows[b.slot], isNotNull);
    expect(windows.stubOf(b).destroyed, isFalse);

    // הראשי גלוי: אינו האחרון.
    mainVisible = true;
    expect(await opener.isLastVisibleWindow(b), isFalse);
  });

  testWidgets('שמירת גבולות שהסשן הסתיים באמצעה אינה יוצרת אותו מחדש', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    windows.native.rects[windows.handleOf(entry).fakeHwnd!] =
        const Rect.fromLTWH(0, 0, 800, 600);
    var calls = 0;
    final binding = WindowPersistenceBinding(
      controller: entry.controller,
      geometry: entry.controller,
      sessions: sessions,
      devicePixelRatio: () => 1.0,
      // הקריאה הראשונה לפני ה-await-ים, השנייה ממש לפני הכתיבה.
      slot: () => calls++ == 0 ? entry.slot : null,
    );
    binding.scheduleSave();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(calls, 2);
    expect(sessions.boundsWrites, isEmpty);
    expect(sessions.rows[entry.slot], isNull);
    binding.dispose();
  });
}
