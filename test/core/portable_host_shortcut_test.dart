import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/portable_host_shortcut.dart';
import 'package:path/path.dart' as p;

/// כמו launcher.cpp: BOM של UTF-16LE ואחריו שורות ה-ini.
List<int> utf16Ini(String text) => [
  0xFF,
  0xFE,
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

void main() {
  late Directory root;
  late String appDir;
  late String hostDir;
  late List<List<String>> calls;
  late int exitCode;

  PortableHostShortcut shortcut() => PortableHostShortcut(
    appDir: appDir,
    hostDir: hostDir,
    runLauncher: (launcher, args) async {
      calls.add([launcher, ...args]);
      return exitCode;
    },
  );

  void writeId(String id) {
    final file = File(p.join(appDir, 'otzaria_data', 'portable_id'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(id);
  }

  void writeHostConfig({required String id, String? rootPath}) {
    Directory(hostDir).createSync(recursive: true);
    File(p.join(hostDir, 'launcher.ini')).writeAsBytesSync(
      utf16Ini(
        '[Otzaria]\r\nId=$id\r\nRoot=${rootPath ?? appDir}\r\n'
        'Folder=\\OtzariaPortable\r\n',
      ),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('otzaria_portable_shortcut');
    appDir = p.join(root.path, 'drive', 'OtzariaPortable');
    hostDir = p.join(root.path, 'local', 'OtzariaPortable');
    Directory(appDir).createSync(recursive: true);
    File(p.join(appDir, 'otzaria_launcher.exe')).writeAsStringSync('launcher');
    calls = [];
    exitCode = 0;
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('ini ב-UTF-16 עם שם תיקייה בעברית נקרא כמו שנכתב', () {
    final values = PortableHostShortcut.parseLauncherConfig(
      utf16Ini('[Otzaria]\r\nId={abc}\r\nRoot=E:\\אוצריא נייד\r\nFolder=\r\n'),
    );

    expect(values['Id'], '{abc}');
    expect(values['Root'], 'E:\\אוצריא נייד');
    expect(values['Folder'], '');
  });

  group('state', () {
    test('אין קיצור במחשב', () async {
      expect(await shortcut().state(), PortableShortcutState.none);
    });

    test('הקיצור שייך לעותק הזה, בלי תלות ברישיות', () async {
      writeId('{ABCD}');
      writeHostConfig(id: '{abcd}');

      expect(await shortcut().state(), PortableShortcutState.thisCopy);
    });

    test('הקיצור שייך לעותק אחר', () async {
      writeId('{mine}');
      writeHostConfig(id: '{theirs}');

      expect(await shortcut().state(), PortableShortcutState.otherCopy);
    });

    test('עותק שעוד לא יצר מזהה אינו בעל הקיצור', () async {
      writeHostConfig(id: '{theirs}');

      expect(await shortcut().state(), PortableShortcutState.otherCopy);
    });
  });

  group('create', () {
    test('יצירת המזהה נעשית בידי המפעיל ולא כותבת מראש לתיקייה', () async {
      File(p.join(appDir, 'otzaria_data')).writeAsStringSync('not a directory');

      final result = await shortcut().create();

      expect(result, PortableShortcutResult.created);
      expect(calls, [
        [p.join(appDir, 'otzaria_launcher.exe'), '--install-shortcut'],
      ]);
      expect(
        File(p.join(appDir, 'otzaria_data')).readAsStringSync(),
        'not a directory',
      );
    });

    test('כשל יצירת מזהה בידי המפעיל מוחזר בלי כתיבה מקדימה', () async {
      File(p.join(appDir, 'otzaria_data')).writeAsStringSync('not a directory');
      exitCode = 3;

      expect(await shortcut().create(), PortableShortcutResult.failed);
    });

    test('מזהה קיים נשמר', () async {
      writeId('{keep}');

      await shortcut().create();

      expect(
        File(p.join(appDir, 'otzaria_data', 'portable_id')).readAsStringSync(),
        '{keep}',
      );
    });

    test('קוד יציאה של כשל מוחזר ככשל', () async {
      exitCode = 5;

      expect(await shortcut().create(), PortableShortcutResult.failed);
    });
  });

  group('refreshIfNeeded', () {
    void copyLauncherToHost() {
      final source = File(p.join(appDir, 'otzaria_launcher.exe'));
      final host = File(p.join(hostDir, 'otzaria_launcher.exe'));
      source.copySync(host.path);
      host.setLastModifiedSync(source.lastModifiedSync());
    }

    test('בלי שינוי — שום תהליך לא נפתח', () async {
      writeId('{id}');
      writeHostConfig(id: '{id}');
      copyLauncherToHost();

      await shortcut().refreshIfNeeded();

      expect(calls, isEmpty);
    });

    test('התיקייה עברה מקום — המפעיל מתעדכן', () async {
      writeId('{id}');
      writeHostConfig(id: '{id}', rootPath: r'F:\Old');
      copyLauncherToHost();

      await shortcut().refreshIfNeeded();

      expect(calls.single.last, '--refresh');
    });

    test('המפעיל במחשב ישן — מתעדכן', () async {
      writeId('{id}');
      writeHostConfig(id: '{id}');
      Directory(hostDir).createSync(recursive: true);
      File(p.join(hostDir, 'otzaria_launcher.exe')).writeAsStringSync('old');

      await shortcut().refreshIfNeeded();

      expect(calls.single.last, '--refresh');
    });

    test('קיצור של עותק אחר אינו נוגעים בו', () async {
      writeId('{mine}');
      writeHostConfig(id: '{theirs}', rootPath: r'F:\Old');

      await shortcut().refreshIfNeeded();

      expect(calls, isEmpty);
    });
  });

  test('רענון אינו משנה קובץ הפעלה קיים מחוץ לעותק הנייד', () async {
    final unrelated = File(p.join(root.path, 'drive', 'אוצריא.exe'));
    unrelated.writeAsStringSync('unrelated app');
    final isolatedShortcut = _IsolatedDriveShortcut(
      appDir: appDir,
      hostDir: hostDir,
      rootLauncherPath: unrelated.path,
    );

    await isolatedShortcut.refreshIfNeeded();

    expect(unrelated.readAsStringSync(), 'unrelated app');
    expect(await isolatedShortcut.state(), PortableShortcutState.none);
    expect(File(p.join(hostDir, 'launcher.ini')).existsSync(), isFalse);
  });
}

class _IsolatedDriveShortcut extends PortableHostShortcut {
  _IsolatedDriveShortcut({
    required super.appDir,
    required super.hostDir,
    required this.rootLauncherPath,
  });

  final String rootLauncherPath;

  // מבודד את קובץ הכונן כדי שהבדיקה לא תכתוב מחוץ לתיקייה הזמנית.
  String get driveRootLauncherPath => rootLauncherPath;
}
