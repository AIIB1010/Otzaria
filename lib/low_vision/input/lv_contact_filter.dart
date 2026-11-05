import 'dart:ui';

import 'package:flutter/foundation.dart';

/// נגיעה שהמסך דיווח עליה, ומה עשינו איתה.
class LvContactSample {
  const LvContactSample({required this.size, required this.rejected});

  /// גודל המגע כפי שהמסך מדווח (0 = המסך לא מדווח גודל).
  final double size;
  final bool rejected;
}

/// מסנן נגיעות גדולות (אף, לחי, כף יד) לפני שהן מגיעות לאפליקציה.
///
/// נגיעה מתחילה ב"הנחה": אם גודלה גדול מ-[maxSize], כל האירועים שלה נזרקים
/// עד ההרמה. נגיעות רגילות לא מושפעות, ולכן הרגישות לאצבע לא יורדת.
class LvContactFilter {
  /// הגודל המרבי של נגיעה מתקבלת; 0 = כבוי.
  double maxSize = 0;

  /// כשפעיל (בזמן כיול) הכול עובר, והנגיעות רק נמדדות.
  bool measureOnly = false;

  final ValueNotifier<LvContactSample?> last = ValueNotifier(null);
  final ValueNotifier<int> rejectedCount = ValueNotifier(0);

  final Set<int> _blocked = {};
  PointerDataPacketCallback? _original;
  PointerDataPacketCallback? _installed;

  /// גודל הנגיעה: רדיוס המגע, ובהיעדרו `size`.
  static double sizeOf(PointerData data) =>
      data.radiusMajor > 0 ? data.radiusMajor : data.size;

  /// עוטף את קבלת האירועים של המערכת. קריאה חוזרת לא עושה כלום.
  void install([PlatformDispatcher? dispatcher]) {
    final target = dispatcher ?? PlatformDispatcher.instance;
    if (_installed != null) return;
    final original = target.onPointerDataPacket;
    _original = original;
    void wrapper(PointerDataPacket packet) {
      final filtered = filter(packet);
      if (filtered.data.isNotEmpty) original?.call(filtered);
    }

    _installed = wrapper;
    target.onPointerDataPacket = wrapper;
  }

  /// מחזיר את המצב שלפני [install], אם איש לא עטף אחרינו.
  void uninstall([PlatformDispatcher? dispatcher]) {
    final target = dispatcher ?? PlatformDispatcher.instance;
    if (_installed != null && target.onPointerDataPacket == _installed) {
      target.onPointerDataPacket = _original;
    }
    _installed = null;
    _original = null;
  }

  /// זורק את האירועים של נגיעות גדולות מדי.
  PointerDataPacket filter(PointerDataPacket packet) {
    final kept = <PointerData>[];
    for (final data in packet.data) {
      if (data.kind != PointerDeviceKind.touch) {
        kept.add(data);
        continue;
      }
      switch (data.change) {
        case PointerChange.down:
          final size = sizeOf(data);
          final reject = !measureOnly && maxSize > 0 && size > maxSize;
          last.value = LvContactSample(size: size, rejected: reject);
          if (reject) {
            _blocked.add(data.device);
            rejectedCount.value++;
            continue;
          }
          kept.add(data);
        case PointerChange.move:
          if (!_blocked.contains(data.device)) kept.add(data);
        case PointerChange.up:
        case PointerChange.cancel:
          if (!_blocked.remove(data.device)) kept.add(data);
        default:
          kept.add(data);
      }
    }
    return PointerDataPacket(data: kept);
  }

  void dispose() {
    uninstall();
    last.dispose();
    rejectedCount.dispose();
  }
}
