import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:path/path.dart' as p;

import 'tar_stream_extractor_test.dart' show header, padded;

class _DelayedFile implements File {
  _DelayedFile(this.file);

  final File file;

  @override
  bool existsSync() => file.existsSync();

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _DelayedWrite(file.openSync(mode: mode));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedWrite implements RandomAccessFile {
  _DelayedWrite(this.file);

  final RandomAccessFile file;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) {
    // dart:io מעתיק בקריאה; רק השלמת הכתיבה תלויה במהירות הדיסק.
    final bytes = Uint8List.fromList(buffer.sublist(start, end));
    return Future.delayed(
      const Duration(milliseconds: 20),
      () => file.writeFrom(bytes),
    );
  }

  @override
  Future<void> close() => file.close();

  @override
  void closeSync() => file.closeSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final (firstName, secondName) in [
    ('\u00e9.bin', 'e\u0301.bin'),
    ('Alias.bin', 'alias.bin'),
  ]) {
    test('רשומות לאותו קובץ בשמות שונים: $firstName / $secondName', () async {
      final dir = Directory.systemTemp.createTempSync('tar_alias');
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = File(p.join(dir.path, firstName));
      final second = File(p.join(dir.path, secondName));
      first.writeAsBytesSync([0]);
      if (!second.existsSync() ||
          !FileSystemEntity.identicalSync(first.path, second.path)) {
        markTestSkipped('מערכת הקבצים מבחינה בין השמות האלה');
        return;
      }
      first.deleteSync();
      final replacement = Uint8List(5000)..fillRange(0, 5000, 2);
      final bytes = BytesBuilder()
        ..add(header(firstName, 3 << 20))
        ..add(padded(Uint8List(3 << 20)..fillRange(0, 3 << 20, 1)))
        ..add(header(secondName, replacement.length))
        ..add(padded(replacement))
        ..add(Uint8List(1024));
      final files = {first.path: _DelayedFile(first), second.path: second};
      final extractor = TarStreamExtractor(dir.path, rootFolder: null);

      await IOOverrides.runZoned(
        () => extractor.add(bytes.takeBytes()),
        createFile: (path) => files[path]!,
      );
      extractor.close();

      expect(second.readAsBytesSync(), replacement);
      expect(extractor.filesWritten, 2);
    });
  }
}
