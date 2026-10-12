import 'dart:convert';
import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// "מה חדש" של release אחד בספרייה — תוכן `library-changes.md` שלו.
class LibraryChangesNote {
  const LibraryChangesNote({
    required this.releaseTag,
    required this.markdown,
    required this.path,
  });

  final String releaseTag;
  final String markdown;
  final String path;

  /// גרסת הספרייה לפי התג (`v32-20261010190601` → 32), 0 כשאין מספר.
  int get version =>
      LibraryUpdateDiscovery.parseVersionFromTag(releaseTag) ?? 0;

  /// החדש קודם: לפי גרסה, ובאותה גרסה לפי התג (שכולל חותמת זמן).
  static int newestFirst(LibraryChangesNote a, LibraryChangesNote b) {
    final byVersion = b.version.compareTo(a.version);
    return byVersion != 0 ? byVersion : b.releaseTag.compareTo(a.releaseTag);
  }
}

/// `<dataRoot>/pending_library_changes/<releaseTag>.md` (טרם הוצג; גם המעדכן
/// הלא-מקוון כותב לשם) ו-`library_changes_seen` (הוצג; [keepSeen] אחרונים).
class LibraryChangesStore {
  LibraryChangesStore({Future<String> Function()? dataRootProvider})
    : _dataRoot = dataRootProvider ?? AppPaths.getDataRootPath;

  static const pendingFolderName = 'pending_library_changes';
  static const seenFolderName = 'library_changes_seen';
  static const keepSeen = 10;

  final Future<String> Function() _dataRoot;

  // תג הוא שם קובץ — אסור שיכיל מפריד נתיב או "..".
  static final _safeTag = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  static bool isSafeTag(String tag) =>
      _safeTag.hasMatch(tag) && !tag.contains('..');

  Future<Directory> _dir(String name) async =>
      Directory(p.join(await _dataRoot(), name));

  /// כותב אטומית (tmp + rename) את ההערות של [releaseTag] לתיקיית ה-pending.
  Future<void> writePending(String releaseTag, String markdown) async {
    if (!isSafeTag(releaseTag)) {
      throw ArgumentError.value(releaseTag, 'releaseTag');
    }
    final dir = await _dir(pendingFolderName);
    await dir.create(recursive: true);
    final target = p.join(dir.path, '$releaseTag.md');
    final tmp = File('$target.tmp');
    await tmp.writeAsString(markdown, encoding: utf8, flush: true);
    await tmp.rename(target);
  }

  /// האם כבר יש הערות ל-[releaseTag] (ממתינות או שהוצגו).
  Future<bool> contains(String releaseTag) async {
    for (final name in const [pendingFolderName, seenFolderName]) {
      final file = File(p.join((await _dir(name)).path, '$releaseTag.md'));
      if (await file.exists()) return true;
    }
    return false;
  }

  Future<List<LibraryChangesNote>> readPending() => _read(pendingFolderName);

  Future<List<LibraryChangesNote>> readSeen() => _read(seenFolderName);

  /// כל ההערות השמורות, החדשה קודם.
  Future<List<LibraryChangesNote>> readAll() async =>
      [...await readPending(), ...await readSeen()]
        ..sort(LibraryChangesNote.newestFirst);

  Future<bool> hasAny() async =>
      (await readPending()).isNotEmpty || (await readSeen()).isNotEmpty;

  Future<List<LibraryChangesNote>> _read(String folder) async {
    final dir = await _dir(folder);
    if (!await dir.exists()) return const [];
    final notes = <LibraryChangesNote>[];
    await for (final entity in dir.list()) {
      if (entity is! File || p.extension(entity.path) != '.md') continue;
      final tag = p.basenameWithoutExtension(entity.path);
      try {
        final bytes = await entity.readAsBytes();
        var text = utf8.decode(bytes, allowMalformed: true);
        if (text.startsWith('﻿')) text = text.substring(1);
        notes.add(
          LibraryChangesNote(
            releaseTag: tag,
            markdown: text,
            path: entity.path,
          ),
        );
      } on FileSystemException {
        // קובץ שנכתב ברגע זה או נעול — ייקרא בפעם הבאה.
      }
    }
    return notes..sort(LibraryChangesNote.newestFirst);
  }

  /// מעביר את [notes] שבתיקיית ה-pending לתיקיית ה-seen, ומשאיר שם רק את
  /// [keepSeen] החדשות.
  Future<void> markSeen(List<LibraryChangesNote> notes) async {
    final pendingDir = await _dir(pendingFolderName);
    final seenDir = await _dir(seenFolderName);
    await seenDir.create(recursive: true);
    for (final note in notes) {
      if (!p.equals(p.dirname(note.path), pendingDir.path)) continue;
      final source = File(note.path);
      if (!await source.exists()) continue;
      await source.rename(p.join(seenDir.path, p.basename(note.path)));
    }
    final seen = await readSeen();
    for (final old in seen.skip(keepSeen)) {
      await File(old.path).delete();
    }
  }
}
