import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
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
  ) {
    return (job = Completer<bool>()).future;
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
        child: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
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
            createPdfOverride: (_) async => source!,
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

  testWidgets('בזמן ההדפסה הכפתור מראה "מדפיס…" והמסך נשאר פתוח', (
    tester,
  ) async {
    final platform = await openScreen(tester);

    await tester.tap(find.text('הדפסה'));
    await tester.pump();

    expect(platform.job, isNotNull);
    expect(find.text('מדפיס…'), findsOneWidget);
    expect(find.text('הדפסה'), findsNothing);
    expect(find.byType(PrintingScreen), findsOneWidget);
    // לחיצה נוספת אינה פותחת עבודה שנייה.
    final firstJob = platform.job;
    await tester.tap(find.text('מדפיס…'), warnIfMissed: false);
    await tester.pump();
    expect(platform.job, same(firstJob));

    platform.job!.complete(true);
    await tester.pump();
    // מעבר היציאה של המסך.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text(PdfMessages.printSent), findsOneWidget);
    expect(find.byType(PrintingScreen), findsNothing);
    await closeScreen(tester);
  });

  testWidgets('כשל בהדפסה מוצג, והכפתור חוזר לפעולה', (tester) async {
    final platform = await openScreen(tester);

    await tester.tap(find.text('הדפסה'));
    await tester.pump();
    platform.job!.completeError(StateError('spooler'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('ההדפסה נכשלה'), findsOneWidget);
    expect(find.text('הדפסה'), findsOneWidget);
    expect(find.byType(PrintingScreen), findsOneWidget);
    await closeScreen(tester);
  });
}
