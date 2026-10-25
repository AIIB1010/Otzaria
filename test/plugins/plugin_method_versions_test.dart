import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';

/// מוודא שגרסאות הקטלוג תואמות לטבלה ב-`docs/plugin-sdk/API_REFERENCE.md`.
void main() {
  group('סנכרון גרסאות API (מפה ⇄ טבלת התיעוד ⇄ known methods)', () {
    final versions = PluginExtendedValidator.methodMinVersions;

    test('לכל method מוכר יש גרסת מינימום במפה', () {
      final missing =
          PluginExtendedValidator.knownApiMethods
              .where((m) => !versions.containsKey(m))
              .toList()
            ..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'methods ללא גרסה ב-קטלוג ה-SDK: $missing. הוסף שורה '
            'במפה ובטבלה שב-API_REFERENCE.md.',
      );
    });

    test('כל method במפה הוא method מוכר', () {
      final unknown =
          versions.keys
              .where(
                (m) => !PluginExtendedValidator.knownApiMethods.contains(m),
              )
              .toList()
            ..sort();
      expect(
        unknown,
        isEmpty,
        reason: 'גרסה הוגדרה ל-method שאינו ב-קטלוג ה-SDK: $unknown',
      );
    });

    // 0.9.98 כבר שוחררה: method שנוסף אחריה מסומן לפחות 0.9.98.1, אחרת
    // החנות תגיש ל-0.9.98 תוסף שקורא לו ויקבל error.unknown_method.
    test('רק methods שיצאו ב-0.9.98 מסומנים 0.9.98', () {
      const shippedIn0998 = {
        'fs.deleteFolder',
        'fs.listUserFolder',
        'fs.moveEntry',
        'fs.openFolderFile',
        'fs.pickUserFolder',
        'fs.revokeFolder',
        'library.getBookDetails',
        'library.openBookFile',
        'library.setProviderBooks',
        'tools.biographies',
      };
      final unreleased =
          versions.entries
              .where((e) => e.value == '0.9.98')
              .map((e) => e.key)
              .where((m) => !shippedIn0998.contains(m))
              .toList()
            ..sort();
      expect(unreleased, isEmpty);
    });

    test('כל גרסה במפה ניתנת לפענוח', () {
      for (final entry in versions.entries) {
        expect(
          () => PluginVersionUtils.parseCoreSegments(entry.value),
          returnsNormally,
          reason: 'גרסה לא חוקית עבור ${entry.key}: ${entry.value}',
        );
      }
    });

    test('הטבלה ב-API_REFERENCE.md זהה למפה בקוד', () {
      final md = File('docs/plugin-sdk/API_REFERENCE.md').readAsStringSync();
      final tableVersions = _parseVersionTable(md);

      expect(
        tableVersions,
        isNotEmpty,
        reason: 'לא נמצאה טבלת גרסאות בפורמט "| `x.y` | 0.9.90 |" במסמך.',
      );

      final inMapNotTable =
          versions.keys.where((m) => !tableVersions.containsKey(m)).toList()
            ..sort();
      expect(
        inMapNotTable,
        isEmpty,
        reason: 'methods במפה שחסרים מהטבלה שבמסמך: $inMapNotTable',
      );

      final mismatched = <String>[];
      tableVersions.forEach((method, tableVer) {
        final mapVer = versions[method];
        if (mapVer == null) {
          mismatched.add('$method: בטבלה $tableVer אך לא במפה');
        } else if (mapVer != tableVer) {
          mismatched.add('$method: מפה=$mapVer טבלה=$tableVer');
        }
      });
      expect(
        mismatched,
        isEmpty,
        reason: 'אי-התאמה בין המפה לטבלה: $mismatched',
      );
    });
  });
}

/// מפענח שורות טבלה בפורמט ``| `namespace.method` | 0.9.90 |``, וגם גרסת
/// hotfix בת ארבעה רכיבים.
Map<String, String> _parseVersionTable(String md) {
  final rowRe = RegExp(
    r'^\|\s*`([a-z][a-zA-Z0-9_]*\.[a-zA-Z0-9_]+)`\s*\|\s*(\d+(?:\.\d+){2,3})\s*\|',
    multiLine: true,
  );
  final out = <String, String>{};
  for (final m in rowRe.allMatches(md)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}
