import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/multiview/view_window_scope.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';

import '../../../helpers/memory_settings_cache.dart';
import '../../../test_helpers/fake_view_window.dart';

/// אתחול מחדש בזמן שדיאלוג סגירה פתוח בחלון Dart: Flutter אינו משלים את
/// הדיאלוג כשה-Navigator נהרס, והתור הגלובלי של הסגירות היה ננעל לכל החלונות.
void main() {
  late Directory tmp;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('view_window_close_restart_');
    AppPaths.debugProfileDataRootPath = tmp.path;
    UserStateDatabase.instance.overridePath('${tmp.path}/user_state.db');
    MultiViewMode.debugOverride = true;
  });

  tearDown(() {
    MultiViewMode.debugOverride = null;
    AppPaths.debugProfileDataRootPath = null;
    AppWindowKeys.resetForTest();
    LastActiveWindow.resetForTest();
    UserStateDatabase.instance.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows עלול להחזיק את הקובץ עוד רגע; תיקיית temp בלבד.
    }
  });

  Future<Map<int, BuildContext>> pumpApp(
    WidgetTester tester,
    ViewWindowRegistry registry,
    ViewWindowCloseFlowFactory closeFlow,
  ) async {
    final contexts = <int, BuildContext>{};
    await tester.pumpWidget(
      RestartWidget(
        // כמו AppBootstrap: מסך פתיחה בין העצים. בלעדיו ה-GlobalKey של
        // ה-Navigator מעביר את אותו State, והדיאלוג פשוט שורד.
        child: _Bootstrap(
          child: AppScopeProviders(
            settingsRepository: SettingsRepository(),
            child: MultiViewHost(
              registry: registry,
              contentBuilder: (context, entry) => ViewWindowScope(
                entry: entry,
                closeFlow: closeFlow,
                child: Builder(
                  builder: (context) => MaterialApp(
                    navigatorKey: AppWindowKeys.of(context).navigator,
                    home: Builder(
                      builder: (context) {
                        contexts[entry.slot] = context;
                        context.read<TabsBloc>();
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return contexts;
  }

  Future<void> scenario(
    WidgetTester tester,
    Future<bool> Function(BuildContext, List<OpenedTab>) confirm,
  ) async {
    final windows = FakeViewWindows(tester);
    // תור סגירה אחד לכל החלונות, כמו ב-ViewWindowOpener.instance.
    final opener = ViewWindowOpener(
      registry: windows.registry,
      native: windows.native,
    );
    final contexts = await pumpApp(
      tester,
      windows.registry,
      (entry) => ViewWindowCloseFlow(
        entry: entry,
        opener: opener,
        confirm: confirm,
        flush: () async {},
        discardSession: (_) async {},
      ),
    );
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // X ב-A: הדיאלוג פתוח בתוך הקטע הסדרתי.
    bool? closedA;
    a.controller.close().then((_) => closedA = windows.stubOf(a).destroyed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('לסגור?'), findsOneWidget);

    // אתחול מחדש מ-B מפרק את ה-Navigator של A עם הדיאלוג.
    AppQuit.restartAll(contexts[b.slot]!);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('לסגור?'), findsNothing);
    expect(closedA, isFalse);
    expect(windows.registry.windows, [a, b]);

    // התור משוחרר: X ב-B פותח דיאלוג, ואישור סוגר את B.
    final closingB = b.controller.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('לסגור?'), findsOneWidget);
    b.keys.navigator.currentState!.pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await closingB;
    expect(windows.stubOf(b).destroyed, isTrue);
    expect(windows.registry.windows, [a]);

    // וגם X חוזר ב-A עובד.
    final closingA = a.controller.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('לסגור?'), findsOneWidget);
    a.keys.navigator.currentState!.pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await closingA;
    expect(windows.stubOf(a).destroyed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('דיאלוג האפליקציה שנפרק באתחול מחדש נחשב לביטול ומשחרר את התור', (
    tester,
  ) async {
    await scenario(
      tester,
      (context, _) async =>
          await showWarningDialog(
            context: context,
            title: 'לסגור?',
            content: 'תוכן',
            confirmText: 'סגור',
          ) ==
          true,
    );
  });

  testWidgets('גם דיאלוג שאינו מוגן: פירוק היקף החלון משחרר את התור', (
    tester,
  ) async {
    await scenario(
      tester,
      (context, _) async =>
          await showDialog<bool>(
            context: context,
            builder: (_) => const Text('לסגור?'),
          ) ==
          true,
    );
  });

  testWidgets('showDialogUntilTornDown: תשובה רגילה עוברת כמו שהיא', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
    );
    final result = showDialogUntilTornDown<int>(
      context: navigator.currentContext!,
      builder: (_) => const Text('שאלה'),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop(7);
    await tester.pumpAndSettle();
    expect(await result, 7);
    expect(find.text('שאלה'), findsNothing);
  });

  testWidgets('showDialogUntilTornDown: פירוק ה-Navigator מחזיר null', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
    );
    int? value = -1;
    var done = false;
    showDialogUntilTornDown<int>(
      context: navigator.currentContext!,
      builder: (_) => const Text('שאלה'),
    ).then((v) {
      value = v;
      done = true;
    });
    await tester.pumpAndSettle();
    expect(find.text('שאלה'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(done, isTrue);
    expect(value, isNull);
  });
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.child});

  final Widget child;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}
