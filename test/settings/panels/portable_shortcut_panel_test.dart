import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/portable_host_shortcut.dart';
import 'package:otzaria/settings/panels/portable_shortcut_panel.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String appDir;
  late String hostDir;
  late List<String> commands;

  setUp(() {
    root = Directory.systemTemp.createTempSync('otzaria_portable_panel');
    appDir = p.join(root.path, 'OtzariaPortable');
    hostDir = p.join(root.path, 'host');
    Directory(appDir).createSync(recursive: true);
    File(p.join(appDir, 'otzaria_launcher.exe')).writeAsStringSync('x');
    commands = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// מדמה את launcher.cpp: יצירה כותבת launcher.ini עם מזהה העותק, הסרה מוחקת.
  Future<int> fakeLauncher(String launcher, List<String> args) async {
    commands.add(args.single);
    final ini = File(p.join(hostDir, 'launcher.ini'));
    if (args.single == '--install-shortcut') {
      final idFile = File(p.join(appDir, 'otzaria_data', 'portable_id'));
      if (!idFile.existsSync()) {
        idFile.parent.createSync(recursive: true);
        idFile.writeAsStringSync('{native-id}');
      }
      final id = idFile.readAsStringSync();
      ini.parent.createSync(recursive: true);
      ini.writeAsStringSync('[Otzaria]\nId=$id\nRoot=$appDir\n');
    } else if (args.single == '--remove-shortcut') {
      ini.deleteSync();
    }
    return 0;
  }

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PortableShortcutPanel(
              shortcut: PortableHostShortcut(
                appDir: appDir,
                hostDir: hostDir,
                runLauncher: fakeLauncher,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('יצירה והסרה של הקיצור מעדכנות את הכרטיס', (tester) async {
    await pumpPanel(tester);

    expect(find.text('גרסה ניידת'), findsOneWidget);
    expect(find.text('קיצור דרך במחשב הזה'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('portable-drive-root-launcher')),
      findsNothing,
    );

    await tester.tap(find.text('צור קיצור'));
    await settle(tester);

    expect(commands, ['--install-shortcut']);
    expect(find.text('הסר'), findsOneWidget);
    expect(
      find.text(
        'בשולחן העבודה ובתפריט התחל יש קיצור "אוצריא (נייד)" שפותח את העותק הזה',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('הסר'));
    await settle(tester);

    expect(commands, ['--install-shortcut', '--remove-shortcut']);
    expect(find.text('צור קיצור'), findsOneWidget);
  });

  testWidgets('קיצור של עותק אחר מוצע להחלפה', (tester) async {
    Directory(hostDir).createSync(recursive: true);
    File(
      p.join(hostDir, 'launcher.ini'),
    ).writeAsStringSync('[Otzaria]\nId={other}\n');

    await pumpPanel(tester);

    expect(
      find.text('הקיצור במחשב הזה פותח עותק נייד אחר של אוצריא'),
      findsOneWidget,
    );
    expect(find.text('החלף'), findsOneWidget);
  });

  testWidgets('בלי המפעיל ליד התוכנה הכרטיס אינו מוצג', (tester) async {
    File(p.join(appDir, 'otzaria_launcher.exe')).deleteSync();

    await pumpPanel(tester);

    expect(find.text('גרסה ניידת'), findsNothing);
  });
}

/// קלט/פלט אמיתי של קבצים לא מתקדם בזמן המדומה של testWidgets.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
