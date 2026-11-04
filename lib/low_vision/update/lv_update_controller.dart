import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:otzaria/low_vision/update/lv_update_service.dart';

enum LvUpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  waitingForInstaller,
  needsPermission,
  noRelease,
  readingFile,
  localReady,
  localNotNewer,
  error,
}

class LvUpdateState {
  const LvUpdateState({
    this.status = LvUpdateStatus.idle,
    this.latest,
    this.progress = 0,
    this.error,
    this.localApk,
    this.localBuild,
  });

  final LvUpdateStatus status;
  final LvUpdateInfo? latest;
  final double progress;
  final String? error;

  /// קובץ עדכון שנבחר מהאחסון (דיסק USB), ומספר הבנייה שבו.
  final File? localApk;
  final int? localBuild;

  bool get isBusy =>
      status == LvUpdateStatus.checking ||
      status == LvUpdateStatus.downloading ||
      status == LvUpdateStatus.readingFile;
}

/// מחזיק את מצב העדכון ברמת האפליקציה, ולא בתוך מסך ההגדרות: יציאה מהמסך או
/// לחיצה על כפתור אחר לא מבטלת הורדה שכבר התחילה.
class LvUpdateController {
  LvUpdateController({
    LvUpdateService? service,
    Future<File?> Function()? pickApk,
    int? installedBuild,
  }) : service = service ?? LvUpdateService(),
       _pickApk = pickApk ?? _pickApkFromStorage,
       _installedBuild = installedBuild ?? kLvBuildNumber;

  final LvUpdateService service;
  final Future<File?> Function() _pickApk;

  /// מספר הבנייה של האפליקציה הרצה (0 בבנייה מקומית).
  final int _installedBuild;

  /// בורר הקבצים של המערכת (מציג גם דיסק USB), ומעתיק את הקובץ למטמון.
  static Future<File?> _pickApkFromStorage() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['apk'],
      dialogTitle: 'בחרו את קובץ העדכון',
    );
    if (picked.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final copy = File('${dir.path}/otzaria-humanware-local.apk');
    await picked.first.xFile.saveTo(copy.path);
    return copy;
  }

  final ValueNotifier<LvUpdateState> state = ValueNotifier(
    const LvUpdateState(),
  );

  void _set(LvUpdateState value) => state.value = value;

  Future<void> check() async {
    if (state.value.isBusy) return;
    _set(const LvUpdateState(status: LvUpdateStatus.checking));
    try {
      final latest = await service.fetchLatest();
      _set(
        LvUpdateState(
          latest: latest,
          status: latest == null
              ? LvUpdateStatus.noRelease
              : latest.isNewerThan(_installedBuild)
              ? LvUpdateStatus.available
              : LvUpdateStatus.upToDate,
        ),
      );
    } on LvUpdateException catch (error) {
      _set(LvUpdateState(status: LvUpdateStatus.error, error: error.message));
    }
  }

  /// עדכון בלי אינטרנט: בוחרים קובץ APK מהאחסון (למשל דיסק USB), בודקים שהוא של
  /// האפליקציה הזו ושהוא חדש יותר מהמותקנת, ואז מתקינים אותו על גביה.
  Future<void> pickLocalFile() async {
    if (state.value.isBusy) return;
    _set(const LvUpdateState(status: LvUpdateStatus.readingFile));
    try {
      final file = await _pickApk();
      if (file == null) {
        _set(const LvUpdateState());
        return;
      }
      final info = await service.inspect(file);
      if (!info.isOurs) {
        _set(
          const LvUpdateState(
            status: LvUpdateStatus.error,
            error: 'הקובץ שנבחר אינו של אוצריא HumanWare.',
          ),
        );
        return;
      }
      final newer = _installedBuild == 0 || info.build > _installedBuild;
      _set(
        LvUpdateState(
          status: newer
              ? LvUpdateStatus.localReady
              : LvUpdateStatus.localNotNewer,
          localApk: file,
          localBuild: info.build,
        ),
      );
    } on LvUpdateException catch (error) {
      _set(LvUpdateState(status: LvUpdateStatus.error, error: error.message));
    } on Object catch (error) {
      _set(
        LvUpdateState(
          status: LvUpdateStatus.error,
          error: 'לא ניתן לקרוא את הקובץ ($error).',
        ),
      );
    }
  }

  Future<void> installLocalFile() async {
    final current = state.value;
    final file = current.localApk;
    if (file == null || current.status != LvUpdateStatus.localReady) return;
    try {
      final result = await service.install(file);
      _set(
        LvUpdateState(
          localApk: file,
          localBuild: current.localBuild,
          status: result == LvInstallResult.needsPermission
              ? LvUpdateStatus.needsPermission
              : LvUpdateStatus.waitingForInstaller,
        ),
      );
    } on LvUpdateException catch (error) {
      _set(LvUpdateState(status: LvUpdateStatus.error, error: error.message));
    }
  }

  Future<void> update() async {
    final latest = state.value.latest;
    if (latest == null || state.value.status == LvUpdateStatus.downloading) {
      return;
    }
    _set(LvUpdateState(status: LvUpdateStatus.downloading, latest: latest));
    try {
      final apk = await service.download(
        latest,
        onProgress: (value) => _set(
          LvUpdateState(
            status: LvUpdateStatus.downloading,
            latest: latest,
            progress: value,
          ),
        ),
      );
      final result = await service.install(apk);
      _set(
        LvUpdateState(
          latest: latest,
          status: result == LvInstallResult.needsPermission
              ? LvUpdateStatus.needsPermission
              : LvUpdateStatus.waitingForInstaller,
        ),
      );
    } on LvUpdateException catch (error) {
      _set(
        LvUpdateState(
          status: LvUpdateStatus.error,
          latest: latest,
          error: error.message,
        ),
      );
    }
  }

  void dispose() {
    service.dispose();
    state.dispose();
  }
}
