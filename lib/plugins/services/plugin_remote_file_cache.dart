import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:path/path.dart' as p;

/// קובץ שהורד למטמון ([PluginRemoteFileCache.fetch]).
typedef PluginRemoteFile = ({String path, String name, int size});

/// מטמון זמני, פרטי לכל תוסף, לקבצים ש-`network.fetchFile` הוריד.
///
/// הקובץ נשמר בתיקיית הטמפ' של המערכת ולא בתיקיית המשתמש, והתוסף מקבל אותו רק
/// כ-token של שרת הקבצים — לעולם לא נתיב. כל הורדה יושבת בתיקייה משלה
/// (`<תוסף>/<מזהה>/<שם>`), כך שהשם נשמר גם כששני קבצים נקראים אותו דבר.
class PluginRemoteFileCache {
  PluginRemoteFileCache({
    Directory? root,
    this.quotaBytes = defaultQuotaBytes,
    this.staleAfter = defaultStaleAfter,
    this.emptyDirGrace = defaultEmptyDirGrace,
  }) : root =
           root ??
           Directory(p.join(Directory.systemTemp.path, _defaultDirName));

  static final PluginRemoteFileCache instance = PluginRemoteFileCache();

  static const String _defaultDirName = 'otzaria_plugin_remote_files';

  /// המכסה הכוללת לתוסף. מעליה נמחקים הקבצים הוותיקים ביותר שלו.
  static const int defaultQuotaBytes = 256 * 1024 * 1024;

  /// תקרת קובץ בודד כשהתוסף לא ביקש אחרת, ותקרה שאי אפשר לעבור.
  static const int defaultMaxBytes = 50 * 1024 * 1024;
  static const int maxBytesLimit = 100 * 1024 * 1024;

  /// מספר ההורדות המקבילות המרבי לתוסף. המכסה נאכפת רק אחרי שהורדה מסתיימת,
  /// ולכן בלי תקרה כאן תוסף יכול להחזיק במקביל כמה פעמים את [maxBytesLimit].
  static const int maxConcurrentFetchesPerPlugin = 3;

  static const Duration defaultTimeout = Duration(minutes: 2);
  static const Duration maxTimeout = Duration(minutes: 10);

  /// קובץ שוותק מזה נמחק בהורדה הראשונה בהפעלה: הניקוי נעשה בעצלתיים, לא
  /// בעליית האפליקציה. הסף נדיב כי חלון משני רץ כתהליך נפרד על אותה תיקייה.
  static const Duration defaultStaleAfter = Duration(hours: 24);

  /// תיקיית הורדה ריקה צעירה מזה עשויה להיות הורדה שזה עתה נוצרה (אולי בתהליך
  /// אחר), ולכן הניקוי אינו נוגע בה.
  static const Duration defaultEmptyDirGrace = Duration(minutes: 5);

  final Directory root;
  final int quotaBytes;
  final Duration staleAfter;
  final Duration emptyDirGrace;
  bool _sweptStale = false;
  final Random _random = Random.secure();

  /// הורדות שרצות כעת, לפי נתיב תיקיית התוסף. נספרות עד שההורדה עצמה מסתיימת, גם אם ה-RPC
  /// כבר נכשל ב-timeout.
  final Map<String, int> _activeFetches = {};

  String? _canonicalRoot;

  /// תיקיית התוסף. מזהה ריק או של נקודות בלבד (`..`) היה מצביע על השורש או
  /// מחוצה לו, ו-[deleteForPlugin] מוחק אותה רקורסיבית.
  Directory _pluginDir(String pluginId) {
    final name = pluginId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final unsafe = RegExp(r'^\.*$').hasMatch(name);
    return Directory(
      p.join(root.path, unsafe ? '_${name.replaceAll('.', '_')}' : name),
    );
  }

  /// האם [path] הוא קובץ שהמטמון הוריד (`<root>/<תוסף>/<מזהה>/<שם>`).
  bool owns(String path) {
    final canonical = canonicalizeNearestExisting(path);
    return canonical != null && ownsCanonical(canonical);
  }

  /// כמו [owns] לנתיב שכבר קנוני, בלי גישה לדיסק (אחרי הקריאה הראשונה):
  /// בדיקה לקסיקלית מול השורש הקנוני.
  bool ownsCanonical(String canonicalPath) {
    final base = _canonicalRoot ??= canonicalizeNearestExisting(root.path);
    return base != null &&
        p.equals(p.dirname(p.dirname(p.dirname(canonicalPath))), base);
  }

  /// מוריד את [uri] למטמון של [pluginId]. [timeout] חל על ההורדה כולה; אחרי
  /// שהמכסה חרגה נמחקים הקבצים הוותיקים של התוסף, מהישן לחדש. יותר מ-
  /// [maxConcurrentFetchesPerPlugin] הורדות במקביל נדחות ב-
  /// `error.too_many_requests`.
  Future<PluginRemoteFile> fetch(
    String pluginId,
    Uri uri, {
    required PluginFileDownloadService downloader,
    required Future<bool> Function(Uri) isAllowed,
    bool Function(Uri previous, Uri target)? isRedirectAllowed,
    int maxBytes = defaultMaxBytes,
    Duration timeout = defaultTimeout,
  }) async {
    final pluginDir = _pluginDir(pluginId);
    final key = pluginDir.path;
    if ((_activeFetches[key] ?? 0) >= maxConcurrentFetchesPerPlugin) {
      throw Exception(
        'error.too_many_requests: too many concurrent file downloads',
      );
    }
    // נספר לפני ה-await הראשון, כדי שקריאות מקבילות לא יעקפו את התקרה.
    _activeFetches[key] = (_activeFetches[key] ?? 0) + 1;
    final dir = Directory(p.join(pluginDir.path, _randomId()));
    var timedOut = false;
    Future<PluginRemoteFile> download() async {
      try {
        await _sweepStale();
        final saved = await downloader.downloadToDirectory(
          uri,
          dir,
          isAllowed: isAllowed,
          isRedirectAllowed: isRedirectAllowed,
          maxBytes: maxBytes,
          expired: () => timedOut,
        );
        // סיימה אחרי שה-RPC כבר נכשל: אף אחד לא יקבל token לקובץ הזה.
        if (timedOut) throw TimeoutException(null);
        return (
          path: saved.path,
          name: saved.filename,
          size: await File(saved.path).length(),
        );
      } catch (_) {
        await _deleteDir(dir);
        rethrow;
      } finally {
        final remaining = (_activeFetches[key] ?? 1) - 1;
        if (remaining > 0) {
          _activeFetches[key] = remaining;
        } else {
          _activeFetches.remove(key);
        }
      }
    }

    try {
      final file = await download().timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          throw TimeoutException('Remote file download timed out');
        },
      );
      await _evictOldest(pluginDir, keep: dir);
      return file;
    } catch (_) {
      await _removeIfIdle(pluginDir);
      rethrow;
    }
  }

  /// מוחק את ההורדה ש-[path] שייך לה, אם הוא במטמון, ואת תיקיית התוסף אם
  /// התרוקנה. בטוח לקרוא על כל נתיב.
  Future<void> delete(String path) async {
    if (!owns(path)) return;
    final downloadDir = File(path).parent;
    await _deleteDir(downloadDir);
    await _removeIfIdle(downloadDir.parent);
  }

  /// מוחק את כל הקבצים של [pluginId] — בהסרה, בכיבוי או באיפוס של התוסף.
  Future<void> deleteForPlugin(String pluginId) =>
      _deleteDir(_pluginDir(pluginId));

  String _randomId() => List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// מוחק הורדות ישנות עד שהסך של [pluginDir] נכנס במכסה. ההורדה שזה עתה
  /// הסתיימה ([keep]) אינה נמחקת, וגודלה מוגבל ל-[maxBytesLimit] < המכסה.
  /// הורדה שעדיין רצה (יש בתיקייה שלה קובץ בשם
  /// [PluginFileDownloadService.partialFileName], שקובץ שהתוסף קובע את שמו אינו
  /// יכול לקבל) נספרת במכסה אך אינה נמחקת: הורדות במקביל של אותו תוסף היו
  /// מוחקות זו את זו באמצע. הסדר הוא לפי זמן הכתיבה של הקבצים.
  Future<void> _evictOldest(
    Directory pluginDir, {
    required Directory keep,
  }) async {
    final entries = <({Directory dir, int size, DateTime modified})>[];
    var total = 0;
    try {
      await for (final entry in pluginDir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        var size = 0;
        var downloading = false;
        var modified = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          await for (final file in entry.list(followLinks: false)) {
            if (file is! File) continue;
            final stat = await file.stat();
            size += stat.size;
            if (stat.modified.isAfter(modified)) modified = stat.modified;
            downloading |=
                p.basename(file.path) ==
                PluginFileDownloadService.partialFileName;
          }
        } on FileSystemException {
          continue; // הורדה שהסתיימה או נמחקה בזמן הסריקה.
        }
        total += size;
        if (!downloading && !p.equals(entry.path, keep.path)) {
          entries.add((dir: entry, size: size, modified: modified));
        }
      }
    } on FileSystemException {
      return; // תיקייה שנמחקה במקביל (הסרת תוסף) — אין מה לפנות.
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= quotaBytes) break;
      // קובץ נעול (ווינדוס) נשאר, ולכן גודלו נשאר במכסה.
      if (await _deleteDir(entry.dir)) total -= entry.size;
    }
  }

  Future<void> _sweepStale() async {
    if (_sweptStale) return;
    _sweptStale = true;
    try {
      if (!await root.exists()) return;
      final now = DateTime.now();
      final cutoff = now.subtract(staleAfter);
      final emptyCutoff = now.subtract(emptyDirGrace);
      await for (final plugin in root.list(followLinks: false)) {
        if (plugin is! Directory) continue;
        await for (final entry in plugin.list(followLinks: false)) {
          if (entry is! Directory) continue;
          final modified = (await entry.stat()).modified;
          // גם תיקיית הורדה ריקה — שריד של מחיקה שנחסמה (קובץ פתוח בווינדוס).
          final empty = await entry.list(followLinks: false).isEmpty;
          if (modified.isBefore(cutoff) ||
              (empty && modified.isBefore(emptyCutoff))) {
            await _deleteDir(entry);
          }
        }
        await _removeIfIdle(plugin);
      }
    } catch (_) {
      // ניקוי best-effort; אין להפיל בגללו הורדה.
    }
  }

  /// מוחק את תיקיית התוסף הריקה שנשארה אחרי הורדה שנכשלה, אלא אם הורדה אחרת
  /// שלו רצה (היא הייתה מאבדת את התיקייה באמצע היצירה).
  Future<void> _removeIfIdle(Directory pluginDir) async {
    if (_activeFetches.containsKey(pluginDir.path)) return;
    try {
      if (await pluginDir.exists()) await pluginDir.delete(); // לא רקורסיבי
    } catch (_) {
      // לא ריקה — יש בה הורדות תקינות.
    }
  }

  /// מוחק תיקייה. מחזיר `false` אם היא נשארה (קובץ נעול).
  Future<bool> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return true;
    } catch (_) {
      // בווינדוס קובץ פתוח (למשל PDF שנטען ב-iframe) חוסם את מחיקת התיקייה, גם
      // כשהקובץ עצמו נמחק: מוחקים את התוכן בנפרד ומנסים שוב על התיקייה.
      try {
        await for (final entry in dir.list(followLinks: false)) {
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
        }
        await dir.delete();
      } catch (_) {
        // המכסה והסריקה הבאה (ריקות ישנות) יטפלו בשארית.
      }
      return !await dir.exists();
    }
  }
}
