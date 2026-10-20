import 'package:otzaria/core/windowing/host_relay.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';

/// עדכון הספרייה הוא פר-תהליך ורץ רק במארח. חלון משני מעביר אליו את פעולות
/// המשתמש ומציג את המצב שהוא משדר.
class LibraryUpdateWindowLink {
  const LibraryUpdateWindowLink();

  /// פעולת משתמש מחלון משני.
  static const String requestEvent = 'libraryUpdate.event';

  /// מצב העדכון: בקשה למארח, או שידור שלו לחלונות המשניים.
  static const String requestState = 'libraryUpdate.state';

  bool get isSecondary => WindowRole.isSecondary;

  /// משבצת החלון הזה באפיק, או null כשאינו רשום.
  int? get slot => WindowBus.instance.slot;

  bool isWindowOpen(int slot) => WindowBus.instance.isSlotRegistered(slot);

  /// true רק כשהמארח אישר שקיבל את [event].
  Future<bool> forward(String event) async {
    final response = await HostRelay.sendToHost(
      requestEvent,
      args: {'event': event, 'fromSlot': slot},
    );
    return response.delivered && response.result == true;
  }

  Future<Map<String, Object?>?> fetchState() =>
      HostRelay.fetchHostSnapshot(requestState);

  HostStateBroadcaster broadcaster(Map<String, Object?> Function() snapshot) =>
      HostStateBroadcaster(requestState, snapshot);
}
