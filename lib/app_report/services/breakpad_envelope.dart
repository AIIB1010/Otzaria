import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// התיקייה (תחת `.sentry-native`) שאליה נשלפים ה-dumps. נפרדת מ-`reports` של
/// crashpad, כי ב-breakpad אין מי שינקה אותה ואנחנו מנקים רק אותה.
const String recoveredMinidumpsDirName = 'recovered_minidumps';

/// dump שנשלף נשמר כך לצורך דיווח באיחור, ואז נמחק.
const Duration recoveredMinidumpRetention = Duration(days: 14);

/// `event.minidump` ב-envelope של Sentry.
const String _minidumpAttachmentType = 'event.minidump';

/// envelope גדול מזה אינו crash envelope תקין (dump מינימלי הוא כמה מאות KB).
const int maxEnvelopeBytes = 64 * 1024 * 1024;

const int _mdmpSignature = 0x504d444d; // 'MDMP'

/// ה-minidump שב-[envelope], או null כשאין או שהמבנה פגום. לא זורק.
///
/// המבנה: שורת כותרת, ואז לכל פריט שורת כותרת (`type`, `length`, ...) ומיד אחריה
/// הנתונים — `length` בתים. בין פריט לפריט מפרידה שורה חדשה.
Uint8List? extractMinidumpFromEnvelope(Uint8List envelope) {
  try {
    var pos = _lineEnd(envelope, 0) + 1; // מדלגים על כותרת ה-envelope
    while (pos < envelope.length) {
      if (envelope[pos] == 0x0a) {
        pos++;
        continue;
      }
      final headerEnd = _lineEnd(envelope, pos);
      final header = jsonDecode(
        utf8.decode(envelope.sublist(pos, headerEnd), allowMalformed: true),
      );
      pos = headerEnd + 1;
      if (header is! Map) return null;

      final isMinidump =
          header['type'] == 'attachment' &&
          header['attachment_type'] == _minidumpAttachmentType;
      final length = header['length'];
      // פריט בלי length נגמר בסוף השורה; ב-dump בינארי זה חותך אותו באמצע,
      // ולכן את ה-minidump עצמו קוראים רק לפי length.
      if (isMinidump && length is! int) return null;
      final end = length is int ? pos + length : _lineEnd(envelope, pos);
      if ((length is int && length < 0) || end > envelope.length) return null;

      if (isMinidump) {
        final payload = Uint8List.sublistView(envelope, pos, end);
        return _looksLikeMinidump(payload) ? payload : null;
      }
      pos = end;
    }
  } catch (_) {
    // envelope פגום אינו ראיה.
  }
  return null;
}

bool _looksLikeMinidump(Uint8List bytes) =>
    bytes.length >= 32 &&
    ByteData.sublistView(bytes).getUint32(0, Endian.little) == _mdmpSignature;

/// אינדקס ה-`\n` הבא מ-[from], או סוף המערך.
int _lineEnd(Uint8List bytes, int from) {
  final index = bytes.indexOf(0x0a, from);
  return index < 0 ? bytes.length : index;
}

/// שולף dumps של breakpad מ-envelopes ב-`*.run` שנכתבו מ-[since] והלאה.
/// יש לקרוא לפני אתחול Sentry, שמוחק envelopes ישנים אחרי שליחתם.
Future<void> recoverBreakpadMinidumps(String sentryDir, DateTime since) async {
  final targetDir = p.join(sentryDir, recoveredMinidumpsDirName);
  try {
    final root = Directory(sentryDir);
    if (!await root.exists()) return;
    await for (final dir in root.list(followLinks: false)) {
      if (dir is! Directory || !dir.path.endsWith('.run')) continue;
      try {
        await _recoverFrom(dir, targetDir, since);
      } catch (error) {
        // תיקייה אחת שנמחקה או ננעלה באמצע הסריקה לא עוצרת את השאר.
        debugPrint('recoverBreakpadMinidumps: ${dir.path}: $error');
      }
    }
  } catch (error) {
    debugPrint('recoverBreakpadMinidumps: $error');
  }
}

/// מוחק dumps ושאריות `.tmp` ישנים, גם בהפעלות שלא קדמה להן קריסה.
Future<void> pruneRecoveredMinidumps(
  String sentryDir, {
  DateTime Function()? clock,
}) async {
  try {
    final dir = Directory(p.join(sentryDir, recoveredMinidumpsDirName));
    if (!await dir.exists()) return;
    final now = (clock ?? DateTime.now)();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final age = now.difference((await entity.stat()).modified);
        if (age > recoveredMinidumpRetention) await entity.delete();
      } catch (_) {
        // קובץ נעול יימחק בפעם הבאה.
      }
    }
  } catch (error) {
    debugPrint('pruneRecoveredMinidumps: $error');
  }
}

Future<void> _recoverFrom(
  Directory dir,
  String targetDir,
  DateTime since,
) async {
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.envelope')) continue;
    try {
      final stat = await entity.stat();
      if (stat.modified.isBefore(since) || stat.size > maxEnvelopeBytes) {
        continue;
      }
      final target = File(
        p.join(targetDir, '${p.basenameWithoutExtension(entity.path)}.dmp'),
      );
      if (await target.exists()) continue;
      final dump = extractMinidumpFromEnvelope(await entity.readAsBytes());
      if (dump == null) continue;

      await target.parent.create(recursive: true);
      // כתיבה לקובץ זמני והחלפה: קריסה באמצע לא משאירה dmp קטוע.
      final temp = File('${target.path}.tmp');
      await temp.writeAsBytes(dump, flush: true);
      await temp.rename(target.path);
      // זמן הקריסה, לא זמן השליפה — כך נבחר ה-dump החדש ביותר נכון.
      await target.setLastModified(stat.modified);
    } catch (error) {
      debugPrint('recoverBreakpadMinidumps: ${entity.path}: $error');
    }
  }
}
