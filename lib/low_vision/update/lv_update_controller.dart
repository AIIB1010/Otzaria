import 'package:flutter/foundation.dart';
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
  error,
}

class LvUpdateState {
  const LvUpdateState({
    this.status = LvUpdateStatus.idle,
    this.latest,
    this.progress = 0,
    this.error,
  });

  final LvUpdateStatus status;
  final LvUpdateInfo? latest;
  final double progress;
  final String? error;

  bool get isBusy =>
      status == LvUpdateStatus.checking || status == LvUpdateStatus.downloading;
}

/// מחזיק את מצב העדכון ברמת האפליקציה, ולא בתוך מסך ההגדרות: יציאה מהמסך או
/// לחיצה על כפתור אחר לא מבטלת הורדה שכבר התחילה.
class LvUpdateController {
  LvUpdateController({LvUpdateService? service})
    : service = service ?? LvUpdateService();

  final LvUpdateService service;
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
              : latest.isNewerThan(kLvBuildNumber)
              ? LvUpdateStatus.available
              : LvUpdateStatus.upToDate,
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
