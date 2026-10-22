import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/multiview/view_window_scope.dart';
import 'package:otzaria/core/windowing/window_title_sync.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../../helpers/memory_settings_cache.dart';
import '../../../test_helpers/fake_view_window.dart';
import '../../../test_helpers/second_test_view.dart';

void main() {
  late Directory tmp;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('view_window_scope_');
    UserStateDatabase.instance.overridePath('${tmp.path}/user_state.db');
    MultiViewMode.debugOverride = true;
  });

  tearDown(() {
    MultiViewMode.debugOverride = null;
    AppWindowKeys.resetForTest();
    LastActiveWindow.resetForTest();
    UserStateDatabase.instance.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows עלול להחזיק את הקובץ עוד רגע; תיקיית temp בלבד.
    }
  });

  /// התוכן של כל חלון: MaterialApp עם ה-navigator של החלון, כמו ב-`App`.
  Future<(Map<int, BuildContext>, BuildContext Function())> pumpHost(
    WidgetTester tester,
    ViewWindowRegistry registry, {
    ViewWindowCloseFlowFactory? closeFlow,
  }) async {
    final contexts = <int, BuildContext>{};
    late BuildContext mainContext;
    await tester.pumpWidget(
      AppScopeProviders(
        settingsRepository: SettingsRepository(),
        child: MultiViewHost(
          registry: registry,
          contentBuilder: (context, entry) => ViewWindowScope(
            entry: entry,
            historyRepository: HistoryRepository(),
            closeFlow:
                closeFlow ?? (entry) => ViewWindowCloseFlow(entry: entry),
            child: Builder(
              builder: (context) => MaterialApp(
                navigatorKey: AppWindowKeys.of(context).navigator,
                home: Builder(
                  builder: (context) {
                    contexts[entry.slot] = context;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          child: Builder(
            builder: (context) {
              mainContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return (contexts, () => mainContext);
  }

  testWidgets('כל חלון Dart מקבל היקף, blocs, מפתחות ותפקיד משלו', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(tester, windows.registry);
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');

    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump();

    final ctxA = contexts[a.slot]!;
    final ctxB = contexts[b.slot]!;
    expect(a.id, const AppWindowId('window-view-2'));
    expect(View.of(ctxA), same(a.handle.view));
    expect(View.of(ctxB), same(b.handle.view));

    // בקר ומפתחות של החלון, לא של החלון הראשי.
    expect(AppWindowScope.controllerOf(ctxA), same(a.controller));
    expect(AppWindowScope.geometryOf(ctxB), same(b.controller));
    expect(AppWindowKeys.of(ctxA), same(a.keys));
    expect(AppWindowKeys.of(ctxB), same(b.keys));

    final roleA = AppWindowScope.roleOf(ctxA);
    expect(roleA.isViewWindow, isTrue);
    expect(roleA.isPrimaryView, isFalse);
    expect(roleA.openedWithTab, isTrue);
    expect(AppWindowScope.roleOf(ctxB).openedWithTab, isFalse);

    // עבודת התהליך והתוספים שברקע נשארות בחלון הראשי.
    final duties = ProcessDuties.of(ctxA);
    expect(duties, same(ViewWindowScope.duties));
    expect(duties.isProcessOwner, isFalse);
    expect(duties.hostsPluginBackground, isFalse);

    // הספק עצל: ה-bloc נוצר בקריאה, והאירועים שלו מטופלים בפריים הבא.
    final tabsA = ctxA.read<TabsBloc>();
    final tabsB = ctxB.read<TabsBloc>();
    await tester.pump();
    expect(identical(tabsA, tabsB), isFalse);
    expect(tabsA.state.tabs, [same(tab)]);
    expect(tabsB.state.tabs, isEmpty);
    expect(a.takeInitialTab(), isNull, reason: 'נצרכת פעם אחת');

    final focusA = ctxA.read<FocusRepository>();
    expect(focusA, same(FocusRepository.forWindow(a.keys)));
    expect(identical(focusA, ctxB.read<FocusRepository>()), isFalse);
    expect(identical(focusA, FocusRepository.current), isFalse);

    // תיקוני הקלט של ה-runner הותקנו לכל חלון.
    expect(windows.native.hooked, [a.handle.hwnd, b.handle.hwnd]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('מצב מסך מלא של חלון חדש נקרא מהחלון ולא מהגדרות חלון אחר', (
    tester,
  ) async {
    await Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, true);
    addTearDown(
      () => Settings.setValue<bool>(SettingsRepository.keyIsFullscreen, false),
    );
    final windows = FakeViewWindows(tester);
    final (contexts, _) = await pumpHost(tester, windows.registry);
    final regular = windows.registry.open(size: const Size(800, 600))!;
    final fullscreen = windows.registry.open(size: const Size(800, 600))!;
    windows.stubOf(fullscreen).fullscreen = true;
    await tester.pump();
    expect(
      contexts[regular.slot]!.read<WindowFullscreenCubit>().state,
      isFalse,
    );
    expect(
      contexts[fullscreen.slot]!.read<WindowFullscreenCubit>().state,
      isTrue,
    );
    expect(Settings.getValue<bool>(SettingsRepository.keyIsFullscreen), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('הכותרת נשלחת לחלון שה-context יושב בו', (tester) async {
    final windows = FakeViewWindows(tester);
    final (contexts, mainContext) = await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();

    expect(WindowTitleSync.of(mainContext()), same(WindowTitleSync.current));
    final syncA = WindowTitleSync.of(contexts[a.slot]!);
    expect(identical(syncA, WindowTitleSync.of(contexts[b.slot]!)), isFalse);

    await syncA.sync('בראשית', tabCount: 2);
    expect(windows.stubOf(a).titles, ['בראשית (2) — אוצריא']);
    expect(windows.stubOf(b).titles, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('הפעלת חלון מעדכנת את החלון הפעיל ואת AppWindowKeys.current', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    expect(LastActiveWindow.id, AppWindowId.primary);

    windows.stubOf(b)
      ..activated = true
      ..notify();
    expect(LastActiveWindow.id, b.id);
    expect(AppWindowKeys.current, same(b.keys));

    windows.stubOf(b)
      ..activated = false
      ..notify();
    windows.stubOf(a)
      ..activated = true
      ..notify();
    expect(LastActiveWindow.id, a.id);
    expect(AppWindowKeys.current, same(a.keys));

    // שינוי גודל בחלון שכבר פעיל אינו "הפעלה" חדשה.
    AppWindowKeys.activateWindow(AppWindowId.primary);
    windows.stubOf(a).notify();
    expect(LastActiveWindow.id, AppWindowId.primary);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('הגבולות נשמרים למשבצת החלון לפי ה-DPR של התצוגה שלו', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    await pumpHost(tester, windows.registry);
    final a = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    (a.handle.view as SecondTestView).devicePixelRatio = 2.0;
    windows.native.rects[a.handle.hwnd!] = const Rect.fromLTWH(
      200,
      100,
      1600,
      1200,
    );

    windows.stubOf(a).notify();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final session = await WindowSessionStore.instance.load(a.slot);
    final bounds = WindowBounds.decode(session?.boundsJson)!;
    expect(bounds.left, 100);
    expect(bounds.top, 50);
    expect(bounds.width, 800);
    expect(bounds.height, 600);
    expect(bounds.dpr, 2.0);
    expect(await WindowSessionStore.instance.load(1), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('סגירה: ביטול משאיר את החלון; אישור מוחק סשן, הורס ומפרק', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    var allow = false;
    final asked = <List<OpenedTab>>[];
    final (contexts, _) = await pumpHost(
      tester,
      windows.registry,
      closeFlow: (entry) => ViewWindowCloseFlow(
        entry: entry,
        confirm: (context, tabs) async {
          asked.add(tabs);
          return allow;
        },
      ),
    );
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');
    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final tabsA = contexts[a.slot]!.read<TabsBloc>();
    await tester.pump(const Duration(seconds: 1));
    expect(await WindowSessionStore.instance.load(a.slot), isNotNull);
    windows.stubOf(a)
      ..activated = true
      ..notify();
    expect(AppWindowKeys.current, same(a.keys));

    // X מהמערכת → מסלול הסגירה של החלון הזה, עם הכרטיסיות שלו.
    windows.handleOf(a).requestClose();
    await tester.pump();
    expect(asked.single, [same(tab)]);
    expect(windows.stubOf(a).destroyed, isFalse);
    expect(windows.registry.windows, [a, b]);

    allow = true;
    await a.controller.close();
    await tester.pump();
    expect(windows.stubOf(a).destroyed, isTrue);
    expect(windows.registry.windows, [b]);
    expect(a.tabsSession.slot, isNull);
    expect(find.byType(View), findsNWidgets(2));
    expect(AppWindowKeys.current, isNot(same(a.keys)));

    await tester.pump(const Duration(seconds: 1));
    expect(windows.stubOf(a).disposed, isTrue);
    expect(tabsA.isClosed, isTrue);
    // סגירת ה-blocs אינה יוצרת מחדש את הסשן שנמחק.
    expect(await WindowSessionStore.instance.load(a.slot), isNull);
    expect(windows.stubOf(b).destroyed, isFalse);

    // חלון שנהרס כבר אינו רשום: הפעלה לפי המזהה שלו אינה מחליפה מפתחות.
    AppWindowKeys.activateWindow(a.id);
    expect(AppWindowKeys.current, isNot(same(a.keys)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
