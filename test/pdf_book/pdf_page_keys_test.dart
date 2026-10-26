// PageDown/PageUp מדפדפים בקורא ה-PDF כמו ←/→ (issue #3272).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/pdf_document_dispose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-page-keys-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(PdfBookBloc, PdfBookTab)> pumpBook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 12; i++) {
        pdf.addPage(pw.Page(build: (_) => pw.Text('page ${i + 1}')));
      }
      await file.writeAsBytes(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: file.path),
      pageNumber: 1,
    );
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _SettingsBloc();
    final tour = TourCubit();
    addTearDown(tabsBloc.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: PdfBookScreen(tab: tab),
        ),
      ),
    );
    final bloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
    for (var i = 0; i < 100 && bloc.state is! PdfBookLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(bloc.state, isA<PdfBookLoaded>());
    await settle(tester, rounds: 30);
    return (bloc, tab);
  }

  Future<void> dragIntoViewer(WidgetTester tester) async {
    await tester.dragFrom(
      tester.getCenter(find.byType(PdfViewer)),
      const Offset(0, -60),
    );
    await settle(tester, rounds: 5);
    final readerFocus = Focus.of(tester.element(find.byType(PdfViewer)));
    expect(readerFocus.hasFocus, isTrue);
    expect(readerFocus.hasPrimaryFocus, isFalse);
  }

  for (final bookView in [false, true]) {
    testWidgets(
      'PageDown לעמוד הבא ו-PageUp לקודם, Alt+PageDown אינו מדפדף: '
      'bookView=$bookView (issue #3272)',
      (tester) async {
        final (bloc, tab) = await pumpBook(tester);
        final controller = tab.pdfViewerController;
        final document = controller.document;
        try {
          if (bookView) {
            bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
            await settle(tester, rounds: 30);
          }
          // לחיצה באזור הקריאה, כמו המשתמש.
          await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
          await settle(tester, rounds: 3);
          expect(controller.pageNumber, 1);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
          await settle(tester, rounds: 20);
          expect(controller.pageNumber, 2);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
          await settle(tester, rounds: 20);
          expect(controller.pageNumber, 1);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          await settle(tester, rounds: 20);
          expect(controller.pageNumber, 1, reason: 'Alt+PageDown שייך לקיצור');
          // גרירה מעבירה את הפוקוס ל-pdfrx; גם שם מדפדפים כמו בחץ (זוג עמודים).
          await dragIntoViewer(tester);
          for (final modifier in [
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.altLeft,
            LogicalKeyboardKey.metaLeft,
          ]) {
            await tester.sendKeyDownEvent(modifier);
            await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
            await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
            await tester.sendKeyUpEvent(modifier);
            await settle(tester, rounds: 3);
            expect(controller.pageNumber, 1, reason: '$modifier שייך לקיצורים');
          }
          for (var i = 0; i < 2; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
            await settle(tester, rounds: 20);
          }
          expect(controller.pageNumber, bookView ? 4 : 3);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await disposePdfDocument(tester, document);
        }
      },
    );
    testWidgets(
      'החזקת PageDown/PageUp אחרי גרירה ממשיכה לדפדף: bookView=$bookView',
      (tester) async {
        final (bloc, tab) = await pumpBook(tester);
        final controller = tab.pdfViewerController;
        final document = controller.document;
        try {
          if (bookView) {
            bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
            await settle(tester, rounds: 30);
          }
          await dragIntoViewer(tester);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
          await settle(tester, rounds: 20);
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
            await settle(tester, rounds: 20);
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
          expect(controller.pageNumber, bookView ? 8 : 5);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.pageUp);
          await settle(tester, rounds: 20);
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageUp);
            await settle(tester, rounds: 20);
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.pageUp);
          expect(controller.pageNumber, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await disposePdfDocument(tester, document);
        }
      },
    );
  }

  testWidgets('שחרור PageDown אחרי גרירה מבטל דפדופים שממתינים בתצוגת ספר', (
    tester,
  ) async {
    final (bloc, tab) = await pumpBook(tester);
    final controller = tab.pdfViewerController;
    final document = controller.document;
    try {
      bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
      await settle(tester, rounds: 30);
      await dragIntoViewer(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
      await settle(tester, rounds: 30);
      expect(controller.pageNumber, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await settle(tester, rounds: 20);
      expect(controller.pageNumber, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await settle(tester, rounds: 30);
      expect(controller.pageNumber, 8, reason: 'לחיצות קצרות נשמרות בתור');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
    }
  });
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
