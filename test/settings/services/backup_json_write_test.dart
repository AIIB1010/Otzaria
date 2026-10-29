import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_json_write_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('כתיבת JSON שומרת את התוכן ואת אורך המחרוזת', () async {
    final data = <String, dynamic>{
      'settings': {'title': 'גיבוי 📚', 'enabled': true},
      'bookmarks': [1, 2, 3],
    };
    final path = p.join(tempDir.path, 'backup.json');

    final length = await BackupService.writeBackupJson(path, data);

    expect(length, json.encode(data).length);
    expect(await File(path).readAsBytes(), utf8.encode(json.encode(data)));
  });

  test('שגיאת כתיבה מוחזרת למי שממתין לגיבוי', () async {
    await expectLater(
      BackupService.writeBackupJson(
        p.join(tempDir.path, 'missing', 'backup.json'),
        {'title': 'גיבוי'},
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
