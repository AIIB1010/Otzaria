import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// לאיזה עותק נייד שייך קיצור הדרך של המחשב הזה.
enum PortableShortcutState { none, thisCopy, otherCopy }

/// תוצאת [PortableHostShortcut.create], לפי קוד היציאה של המפעיל.
enum PortableShortcutResult { created, notPortable, failed }

typedef PortableLauncherRunner =
    Future<int> Function(String launcher, List<String> arguments);

/// קיצור דרך במחשב המארח שפותח עותק נייד גם כשאות הכונן שלו משתנה.
///
/// הקיצור מפעיל עותק של `otzaria_launcher.exe` ב-`%LOCALAPPDATA%`, שמחפש בכל
/// הכוננים את העותק שמזהה [idFileName] שלו תואם (windows/launcher/launcher.cpp).
class PortableHostShortcut {
  PortableHostShortcut({
    required this.appDir,
    required this.hostDir,
    PortableLauncherRunner? runLauncher,
  }) : _runLauncher = runLauncher ?? _runProcess;

  /// העותק הרץ, או `null` כשאין משמעות לקיצור: לא Windows או לא נייד.
  static PortableHostShortcut? forCurrentProcess() {
    if (!Platform.isWindows || !AppPaths.isPortable) return null;
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) return null;
    return PortableHostShortcut(
      appDir: p.dirname(Platform.resolvedExecutable),
      hostDir: p.join(localAppData, hostDirName),
    );
  }

  static const String launcherFileName = 'otzaria_launcher.exe';
  static const String hostDirName = 'OtzariaPortable';
  static const String configFileName = 'launcher.ini';
  static const String idFileName = 'portable_id';
  static const String driveRootLauncherName = 'אוצריא.exe';

  /// תיקיית ה-exe של העותק הנייד.
  final String appDir;

  /// `%LOCALAPPDATA%\OtzariaPortable` במחשב הזה.
  final String hostDir;

  final PortableLauncherRunner _runLauncher;

  String get _launcherPath => p.join(appDir, launcherFileName);
  String get _hostLauncherPath => p.join(hostDir, launcherFileName);
  String get _configPath => p.join(hostDir, configFileName);
  File get _idFile => File(p.join(appDir, 'otzaria_data', idFileName));

  /// גרסה ניידת שנבנתה בלי המפעיל (למשל ריצת פיתוח) אינה מציעה קיצור.
  Future<bool> isAvailable() => File(_launcherPath).exists();

  Future<String?> _readId() async {
    try {
      final id = (await _idFile.readAsString()).trim();
      return id.isEmpty ? null : id;
    } on FileSystemException {
      return null;
    }
  }

  /// המזהה נוצר בבקשה הראשונה לקיצור, ונשאר עם העותק בכל כונן ותיקייה.
  Future<String> _ensureId() async {
    final existing = await _readId();
    if (existing != null) return existing;
    final random = Random.secure();
    final hex = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final id =
        '{${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}}';
    await _idFile.parent.create(recursive: true);
    await _idFile.writeAsString(id, flush: true);
    return id;
  }

  Future<Map<String, String>?> _readConfig() async {
    try {
      return parseLauncherConfig(await File(_configPath).readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  Future<PortableShortcutState> state() async {
    final config = await _readConfig();
    final hostId = config?['Id'];
    if (hostId == null || hostId.isEmpty) return PortableShortcutState.none;
    final id = await _readId();
    return id != null && id.toLowerCase() == hostId.toLowerCase()
        ? PortableShortcutState.thisCopy
        : PortableShortcutState.otherCopy;
  }

  /// יוצר את הקיצור בשולחן העבודה ובתפריט התחל; מחליף קיצור של עותק אחר.
  Future<PortableShortcutResult> create() async {
    await _ensureId();
    final code = await _runLauncher(_launcherPath, const [
      '--install-shortcut',
    ]);
    return switch (code) {
      0 => PortableShortcutResult.created,
      2 => PortableShortcutResult.notPortable,
      _ => PortableShortcutResult.failed,
    };
  }

  Future<bool> remove() async =>
      await _runLauncher(_launcherPath, const ['--remove-shortcut']) == 0;

  /// אחרי העברת התיקייה או עדכון התוכנה, הקיצור במחשב מתעדכן בהפעלה הבאה.
  /// תהליך נפתח רק כשבאמת יש מה לעדכן.
  Future<void> refreshIfNeeded() async {
    final rootLauncher = driveRootLauncherPath;
    if (rootLauncher != null &&
        await File(rootLauncher).exists() &&
        !await _sameFile(_launcherPath, rootLauncher)) {
      await File(_launcherPath).copy(rootLauncher);
    }
    if (await state() != PortableShortcutState.thisCopy) return;
    final root = (await _readConfig())?['Root'] ?? '';
    if (!_samePath(root, appDir) ||
        !await _sameFile(_launcherPath, _hostLauncherPath)) {
      await _runLauncher(_launcherPath, const ['--refresh']);
    }
  }

  /// עותק בשורש: Root נכתב `R:` ו-[appDir] הוא `R:\`.
  static bool _samePath(String a, String b) {
    String strip(String path) =>
        path.replaceAll(RegExp(r'[\\/]+$'), '').toLowerCase();
    return strip(a) == strip(b);
  }

  // ── קובץ ההפעלה בשורש הדיסק ─────────────────────────────────────────────

  /// `E:\אוצריא.exe` לעותק ב-`E:\OtzariaPortable`. `null` כשהעותק אינו בדיוק
  /// תיקייה אחת מתחת לשורש (המפעיל בשורש מחפש רק שם), או בכונן המערכת.
  String? get driveRootLauncherPath {
    final root = p.rootPrefix(appDir);
    if (root.isEmpty || !p.equals(p.dirname(appDir), root)) return null;
    final systemDrive = Platform.environment['SystemDrive'] ?? 'C:';
    if (root.toLowerCase().startsWith(systemDrive.toLowerCase())) return null;
    if (Platform.isWindows && !_isLocalDrive(root)) return null;
    return p.join(root, driveRootLauncherName);
  }

  Future<bool> hasDriveRootLauncher() async {
    final path = driveRootLauncherPath;
    return path != null && await File(path).exists();
  }

  Future<bool> addDriveRootLauncher() async {
    final path = driveRootLauncherPath;
    if (path == null) return false;
    try {
      await File(_launcherPath).copy(path);
      return true;
    } on FileSystemException catch (e) {
      debugPrint('PortableHostShortcut: drive root launcher failed: $e');
      return false;
    }
  }

  Future<bool> removeDriveRootLauncher() async {
    final path = driveRootLauncherPath;
    if (path == null) return false;
    try {
      await File(path).delete();
      return true;
    } on FileSystemException catch (e) {
      debugPrint('PortableHostShortcut: drive root launcher removal: $e');
      return false;
    }
  }

  static Future<bool> _sameFile(String a, String b) async {
    try {
      final (sa, sb) = (await File(a).stat(), await File(b).stat());
      return sa.type == FileSystemEntityType.file &&
          sb.type == FileSystemEntityType.file &&
          sa.size == sb.size &&
          sa.modified == sb.modified;
    } on FileSystemException {
      return false;
    }
  }

  static bool _isLocalDrive(String root) {
    final path = root.toPcwstr();
    try {
      final type = GetDriveType(path);
      return type == DRIVE_REMOVABLE || type == DRIVE_FIXED;
    } finally {
      malloc.free(path);
    }
  }

  static Future<int> _runProcess(String launcher, List<String> args) async =>
      (await Process.run(launcher, args)).exitCode;

  /// `launcher.ini` נכתב ב-UTF-16LE עם BOM, כדי ששם תיקייה בעברית ישרוד.
  @visibleForTesting
  static Map<String, String> parseLauncherConfig(List<int> bytes) {
    final String text;
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2)
          bytes[i] | (bytes[i + 1] << 8),
      ];
      text = String.fromCharCodes(units);
    } else {
      text = String.fromCharCodes(bytes);
    }
    final values = <String, String>{};
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }
    return values;
  }
}
