import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/library_update_window_link.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

class _FullDownloadService implements LibraryUpdateService {
  int checks = 0;

  /// כשהוא מסופק — הבדיקה ממתינה לו.
  Completer<void>? gate;

  @override
  Future<LibraryUpdatePlan> checkForUpdate({
    required bool allowPrerelease,
  }) async {
    checks++;
    await gate?.future;
    return LibraryUpdatePlan.fullDownload(
      localVersion: 1,
      targetVersion: 3,
      asset: const ReleaseAsset(
        name: 'seforim.db.zst',
        downloadUrl: 'https://x',
        size: 1200000000,
      ),
      releaseTag: 'v3',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _FakeLink extends LibraryUpdateWindowLink {
  _FakeLink({required this.isSecondary, this.slot = 2});

  @override
  final bool isSecondary;

  @override
  final int? slot;

  final forwarded = <String>[];
  bool delivered = true;
  Map<String, Object?>? hostState;

  @override
  Future<bool> forward(String event) async {
    forwarded.add(event);
    return delivered;
  }

  @override
  Future<Map<String, Object?>?> fetchState() async => hostState;

  final openWindows = <int>{2, 3};

  @override
  bool isWindowOpen(int slot) => openWindows.contains(slot);
}

LibraryUpdateBloc _bloc(LibraryUpdateService service, _FakeLink link) =>
    LibraryUpdateBloc(
      repository: service,
      isOfflineMode: () => false,
      areUpdatesEnabled: () => true,
      allowPrerelease: () => false,
      hasInternet: () async => true,
      isSourceReachable: () async => true,
      windowLink: link,
    );

/// עדכון הספרייה רץ רק במארח; חלון משני מעביר אליו את פעולות המשתמש ומציג
/// את המצב שהוא משדר.
void main() {
  group('חלון משני', () {
    test('פעולות המשתמש מועברות למארח ואינן בודקות עדכון מקומית', () async {
      final service = _FullDownloadService();
      final link = _FakeLink(isSecondary: true);
      final bloc = _bloc(service, link);

      bloc
        ..add(const StartLibraryUpdate())
        ..add(const ConfirmFullDownload())
        ..add(const ConfirmHeavyDelta())
        ..add(const DeclineFullDownload())
        ..add(const CancelLibraryUpdate())
        ..add(const ResetLibraryUpdate());
      await pumpEventQueue();

      expect(link.forwarded, [
        'start',
        'confirmFull',
        'confirmHeavyDelta',
        'declineFull',
        'cancel',
        'reset',
      ]);
      expect(service.checks, 0);
      await bloc.close();
    });

    test('כשהמארח לא קיבל את הבקשה — הודעה שאינה "עדכונים מושבתים"', () async {
      final link = _FakeLink(isSecondary: true)..delivered = false;
      final bloc = _bloc(_FullDownloadService(), link);

      bloc.add(const StartLibraryUpdate());
      await pumpEventQueue();

      expect(bloc.state.status, LibraryUpdateStatus.error);
      expect(bloc.state.message, WindowMessages.mainWindowRequestFailed);
      await bloc.close();
    });

    test('מציג את מצב המארח, בלי hasUpdate שהיה מרענן פעם שנייה', () async {
      final host = _bloc(
        _FullDownloadService(),
        _FakeLink(isSecondary: false, slot: 1),
      );
      host.handleHostEvent({'event': 'start', 'fromSlot': 2});
      await pumpEventQueue();
      expect(host.state.status, LibraryUpdateStatus.needsFullConfirmation);

      final link = _FakeLink(isSecondary: true, slot: 2)
        ..hostState = host.hostSnapshot();
      // נפתח באמצע: מושך את מצב המארח בלי פעולת משתמש.
      final secondary = _bloc(_FullDownloadService(), link);
      await pumpEventQueue();

      expect(
        secondary.state.status,
        LibraryUpdateStatus.needsFullConfirmation,
      );
      expect(secondary.state.hasUpdate, isFalse);
      expect(secondary.state.fullDownloadSize, 1200000000);
      // החלון שביקש הוא ששואל את המשתמש — לא המארח.
      expect(secondary.promptsInThisWindow, isTrue);
      expect(host.promptsInThisWindow, isFalse);

      final other = _bloc(
        _FullDownloadService(),
        _FakeLink(isSecondary: true, slot: 3)..hostState = host.hostSnapshot(),
      );
      await pumpEventQueue();
      expect(other.promptsInThisWindow, isFalse);

      await Future.wait([host.close(), secondary.close(), other.close()]);
    });
  });

  group('מארח', () {
    test('החלון שביקש נסגר — השאלה חוזרת למארח', () async {
      final link = _FakeLink(isSecondary: false, slot: 1);
      final host = _bloc(_FullDownloadService(), link);
      host.handleHostEvent({'event': 'start', 'fromSlot': 2});
      await pumpEventQueue();
      expect(host.promptsInThisWindow, isFalse);

      link.openWindows.remove(2);
      expect(host.promptsInThisWindow, isTrue);
      await host.close();
    });

    // בקשת חלון משני בזמן שבדיקת המארח רצה אינה לוקחת ממנו את השאלה.
    test('המשבצת נקבעת לפי הבקשה שהתחילה את הריצה', () async {
      final service = _FullDownloadService()..gate = Completer<void>();
      final host = _bloc(service, _FakeLink(isSecondary: false, slot: 1));
      host
        ..add(const StartLibraryUpdate())
        ..handleHostEvent({'event': 'start', 'fromSlot': 2});
      await pumpEventQueue();
      service.gate!.complete();
      await pumpEventQueue();
      expect(service.checks, 1);
      expect(host.state.status, LibraryUpdateStatus.needsFullConfirmation);
      expect(host.promptsInThisWindow, isTrue);
      await host.close();
    });

    test('ריצה שהמארח התחיל שואלת בו', () async {
      final host = _bloc(
        _FullDownloadService(),
        _FakeLink(isSecondary: false, slot: 1),
      );
      host.add(const StartLibraryUpdate());
      await pumpEventQueue();

      expect(host.state.status, LibraryUpdateStatus.needsFullConfirmation);
      expect(host.promptsInThisWindow, isTrue);
      expect(host.hostSnapshot()['promptSlot'], 1);
      await host.close();
    });

    test('פעולה לא מוכרת נדחית', () async {
      final host = _bloc(
        _FullDownloadService(),
        _FakeLink(isSecondary: false, slot: 1),
      );
      expect(host.handleHostEvent({'event': 'מחק הכל'}), isFalse);
      await host.close();
    });

    test('חלון משני אינו מבצע פעולות של חלון אחר', () async {
      final secondary = _bloc(
        _FullDownloadService(),
        _FakeLink(isSecondary: true),
      );
      expect(secondary.handleHostEvent({'event': 'start'}), isFalse);
      await secondary.close();
    });
  });
}
