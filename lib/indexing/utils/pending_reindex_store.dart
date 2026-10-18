import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// ספרים שמסמכיהם באינדקס ממתינים להחלפה, ובקשת בדיקה מלאה שטרם רצה —
/// שורדים קריסה או ביטול. הקובץ: `{"version":1,"keys":[...],"checkLibrary":true}`.
class PendingReindexStore {
  PendingReindexStore._(this._file);

  static const fileName = 'otzaria_pending_reindex.json';
  static const _version = 1;

  /// null כשאין אינדקס פתוח.
  static PendingReindexStore? forIndex(String? indexPath) => indexPath == null
      ? null
      : PendingReindexStore._(File(p.join(indexPath, fileName)));

  // עותק בזיכרון: כשהכתיבה לדיסק נכשלת, ביטול באותה הפעלה עדיין לא מאבד אותו.
  static final Map<String, ({Set<String> keys, bool checkLibrary})> _memory =
      {};

  /// האינדקס נמחק או הוחלף — מה שנזכר עליו כבר אינו נכון.
  static void clearMemory() => _memory.clear();

  @visibleForTesting
  static void resetMemoryForTesting() => clearMemory();

  final File _file;

  Future<({Set<String> keys, bool checkLibrary})> _read() async {
    final cached = _memory[_file.path];
    final keys = {...?cached?.keys};
    var checkLibrary = cached?.checkLibrary ?? false;
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is Map && json['version'] == _version) {
          keys.addAll((json['keys'] as List).cast<String>());
          checkLibrary |= json['checkLibrary'] == true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ קריאת רשימת הספרים להחלפה באינדקס נכשלה: $e');
    }
    return (keys: keys, checkLibrary: checkLibrary);
  }

  Future<Set<String>> load() async => (await _read()).keys;

  /// האם נדחתה בדיקה מלאה של הספרייה (ריצה שבוטלה לפני שבדקה).
  Future<bool> checkLibraryPending() async => (await _read()).checkLibrary;

  /// מחליף את הרשימה כולה; [checkLibrary] null שומר את הקיים. מחזיר האם נשמר.
  Future<bool> save(Set<String> keys, {bool? checkLibrary}) async {
    final check = checkLibrary ?? (await _read()).checkLibrary;
    _memory[_file.path] = (keys: {...keys}, checkLibrary: check);
    try {
      if (keys.isEmpty && !check) {
        if (await _file.exists()) await _file.delete();
        return true;
      }
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': _version,
          'keys': keys.toList()..sort(),
          if (check) 'checkLibrary': true,
        }),
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
