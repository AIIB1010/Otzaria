import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// ספרים שהוחלט להחליף את מסמכיהם באינדקס, וטרם נחתמו מחדש.
///
/// עד ה-commit הספר נשאר באינדקס עם תוכנו הישן, ולכן הסימון חייב לשרוד
/// קריסה או ביטול — אחרת הספר ייחשב מאונדקס ולא יוחלף לעולם.
/// הקובץ: `{"version": 1, "keys": ["id:5", ...]}` בתוך תיקיית האינדקס.
class PendingReindexStore {
  PendingReindexStore._(this._file);

  static const fileName = 'otzaria_pending_reindex.json';
  static const _version = 1;

  /// null כשאין אינדקס פתוח.
  static PendingReindexStore? forIndex(String? indexPath) => indexPath == null
      ? null
      : PendingReindexStore._(File(p.join(indexPath, fileName)));

  // עותק בזיכרון: כשהכתיבה לדיסק נכשלת, ביטול באותה הפעלה עדיין לא מאבד אותו.
  static final Map<String, Set<String>> _memory = {};

  @visibleForTesting
  static void resetMemoryForTesting() => _memory.clear();

  final File _file;

  Set<String> get _cached => _memory.putIfAbsent(_file.path, () => {});

  Future<Set<String>> load() async {
    final keys = {..._cached};
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is Map && json['version'] == _version) {
          keys.addAll((json['keys'] as List).cast<String>());
        }
      }
    } catch (e) {
      debugPrint('⚠️ קריאת רשימת הספרים להחלפה באינדקס נכשלה: $e');
    }
    return keys;
  }

  /// מחליף את הרשימה כולה; רשימה ריקה מוחקת את הקובץ. מחזיר האם נשמר בדיסק.
  Future<bool> save(Set<String> keys) async {
    _cached
      ..clear()
      ..addAll(keys);
    try {
      if (keys.isEmpty) {
        if (await _file.exists()) await _file.delete();
        return true;
      }
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'version': _version, 'keys': keys.toList()..sort()}),
        flush: true,
      );
      await temp.rename(_file.path);
      return true;
    } catch (e) {
      debugPrint('⚠️ שמירת רשימת הספרים להחלפה באינדקס נכשלה: $e');
      return false;
    }
  }
}
