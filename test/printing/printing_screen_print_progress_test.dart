import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/print_work_status.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';

import '../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

/// עבודת הדפסה שהבדיקה מסיימת בעצמה, כמו spooler איטי.
class _PendingPrintingPlatform extends PrintingPlatform {
  Completer<bool>? job;

  /// כמו ה-plugin: מבקש את ה-PDF, וכשל ב-onLayout מסיים את העבודה בשגיאה.
  bool requestLayout = false;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    final pending = job = Completer<bool>();
    if (requestLayout) {
      // פורמט של המדפסת, שונה מזה של התצוגה המקדימה השמורה.
      await onLayout(PdfPageFormat.a5);
    }
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Uint8List> _onePagePdf() {
  final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('page')));
  return doc.save();
}

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late PrintingPlatform originalPlatform;
  late Directory tempDir;
  late WorkStatusCubit workStatus;
  var layoutFails = false;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    originalPlatform = PrintingPlatform.instance;
    tempDir = Directory.systemTemp.createTempSync('otzaria-print-progress-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (_) async => tempDir.path,
        );
  });

  tearDownAll(() {
    PrintingPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    tempDir.deleteSync(recursive: true);
  });

  Future<_PendingPrintingPlatform> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    layoutFails = false;
    workStatus = WorkStatusCubit();
    addTearDown(workStatus.close);
    final platform = _PendingPrintingPlatform();
    PrintingPlatform.instance = platform;
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    final source = await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      return _onePagePdf();
    });

    await tester.pumpWidget(
      RepositoryProvider<SettingsRepository>.value(
        value: _FakeSettingsRepository(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<WorkStatusCubit>.value(value: workStatus),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
            home: const SizedBox(),
          ),
        ),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<bool>(
          builder: (_) => PrintingScreen(
            data: Future.value(''),
            bookId: 'test',
            createPdfOverride: (_) async {
              if (layoutFails) throw StateError('layout');
              return source!;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    bool previewDone() =>
        find.byType(Image).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty;
    for (var i = 0; i < 200 && !previewDone(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(previewDone(), isTrue);
    return platform;
  }

  Future<void> closeScreen(WidgetTester tester) async {
    // מעבר לזמן התצוגה של UiSnack, כדי שלא יישאר טיימר פתוח.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    // מעבר היציאה של המסך.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('עד שה-PDF נמסר הכפתור מראה "מכין…" והמסך נשאר פתוח', (
    tester,
  ) async {
    final platform = await openScreen(tester);

    await tester.tap(find.text('הדפסה'));
    await tester.pump();

    expect(platform.job, isNotNull);
    expect(find.text(PdfMessages.printPreparing), findsOneWidget);
    expect(find.text('הדפסה'), findsNothing);
    expect(find.byType(PrintingScreen), findsOneWidget);
    // לחיצה נוספת אינה פותחת עבודה שנייה.
    final firstJob = platform.job;
    await tester.tap(
      find.text(PdfMessages.printPreparing),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(platform.job, same(firstJob));
    // גם ESC אינו סוגר את המסך כל עוד דיאלוג ההדפסה פתוח.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PrintingScreen), findsOneWidget);

    platform.job!.complete(true);
    await tester.pump();
    await pumpFrames(tester);

    expect(find.text(PdfMessages.printSent), findsOneWidget);
    expect(find.byType(PrintingScreen), findsNothing);
    expect(workStatus.state.items, isEmpty);
    await closeScreen(tester);
  });

  testWidgets('אחרי מסירת ה-PDF המסך נסגר וההדפסה ממשיכה בחיווי העבודה', (
    tester,
  ) async {
    final platform = await openScreen(tester);
    platform.requestLayout = true;

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    await pumpFrames(tester);

    expect(find.byType(PrintingScreen), findsNothing);
    expect(PrintWorkStatus.hasActiveJobs, isTrue);
    final item = workStatus.state.items.values.single;
    expect(item.kind, WorkStatusKind.running);
    expect(item.progress, isNull);
    expect(item.message, PdfMessages.printSpooling);
    expect(find.text(PdfMessages.printSent), findsNothing);

    platform.job!.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(workStatus.state.items, isEmpty);
    expect(PrintWorkStatus.hasActiveJobs, isFalse);
    expect(find.text(PdfMessages.printSent), findsOneWidget);
    await closeScreen(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('מחוץ ל-Windows המסך נשאר פתוח עד סוף ההדפסה', (tester) async {
    final platform = await openScreen(tester);
    platform.requestLayout = true;

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    await pumpFrames(tester);

    expect(find.byType(PrintingScreen), findsOneWidget);
    expect(find.text(PdfMessages.printPreparing), findsOneWidget);
    expect(PrintWorkStatus.hasActiveJobs, isFalse);
    expect(workStatus.state.items, isEmpty);

    platform.job!.complete(true);
    await tester.pump();
    await pumpFrames(tester);

    expect(find.byType(PrintingScreen), findsNothing);
    expect(find.text(PdfMessages.printSent), findsOneWidget);
    await closeScreen(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('כשל אחרי המסירה מוצג בחיווי העבודה ובהודעה אחת', (
    tester,
  ) async {
    final platform = await openScreen(tester);
    platform.requestLayout = true;

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    await pumpFrames(tester);
    platform.job!.completeError(StateError('spooler'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isA<StateError>());
    expect(PrintWorkStatus.hasActiveJobs, isFalse);
    final item = workStatus.state.items.values.single;
    expect(item.kind, WorkStatusKind.failed);
    expect(item.autoDismissAfter, kPrintFailureAutoDismiss);
    expect(find.text(PdfMessages.printError), findsOneWidget);
    await tester.pump(kPrintFailureAutoDismiss);
    expect(workStatus.state.items, isEmpty);
    await closeScreen(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('ביטול דיאלוג ההדפסה משאיר את המסך פתוח', (tester) async {
    final platform = await openScreen(tester);

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    platform.job!.complete(false);
    await tester.pump();
    await pumpFrames(tester);

    expect(find.byType(PrintingScreen), findsOneWidget);
    expect(find.text('הדפסה'), findsOneWidget);
    expect(workStatus.state.items, isEmpty);
    expect(PrintWorkStatus.hasActiveJobs, isFalse);
    await closeScreen(tester);
  });

  testWidgets('כשל בהדפסה מוצג, והכפתור חוזר לפעולה', (tester) async {
    final platform = await openScreen(tester);

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    platform.job!.completeError(StateError('spooler'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());

    expect(find.text(PdfMessages.printError), findsOneWidget);
    expect(find.text('הדפסה'), findsOneWidget);
    expect(find.byType(PrintingScreen), findsOneWidget);
    expect(workStatus.state.items, isEmpty);
    await closeScreen(tester);
  });

  testWidgets('כשל ביצירת ה-PDF מחזיר את הכפתור לפעולה', (tester) async {
    final platform = await openScreen(tester);
    platform.requestLayout = true;
    layoutFails = true;

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
    expect(find.text(PdfMessages.printError), findsOneWidget);
    expect(find.text('הדפסה'), findsOneWidget);
    expect(find.text(PdfMessages.printPreparing), findsNothing);
    expect(find.byType(PrintingScreen), findsOneWidget);
    expect(workStatus.state.items, isEmpty);
    await closeScreen(tester);
  });

  testWidgets('"מכין…" נכנס בשורה אחת בכפתור של פאנל ההגדרות', (tester) async {
    await openScreen(tester);

    await tester.tap(find.text('הדפסה'));
    await tester.pump();

    final label = tester.renderObject<RenderParagraph>(
      find.text(PdfMessages.printPreparing),
    );
    final lineTops = label
        .getBoxesForSelection(
          const TextSelection(
            baseOffset: 0,
            extentOffset: PdfMessages.printPreparing.length,
          ),
        )
        .map((box) => box.top)
        .toSet();
    expect(lineTops, hasLength(1));
    await closeScreen(tester);
  });
}
