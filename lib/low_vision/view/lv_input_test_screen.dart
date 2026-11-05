import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/theme/lv_metrics.dart';
import 'package:otzaria/low_vision/view/lv_settings_screen.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';

/// מציג מה האפליקציה מקבלת מכל כפתור פיזי של המכשיר: מקשים, גלגלת וכפתור חזרה.
/// נועד לגלות מה שולחים החוגה וכפתור החזרה של ה-Reveal, כדי לשייך אותם לפעולות.
class LvInputTestScreen extends StatefulWidget {
  const LvInputTestScreen({super.key});

  @override
  State<LvInputTestScreen> createState() => _LvInputTestScreenState();
}

class _LvInputTestScreenState extends State<LvInputTestScreen> {
  final _events = <String>[];
  final _touchStart = <int, Offset>{};
  final _touchTime = <int, Stopwatch>{};
  final _touchMaxTravel = <int, double>{};
  final _touchPeers = <int, int>{};

  void _add(String text) {
    setState(() {
      _events.insert(0, text);
      if (_events.length > 12) _events.removeLast();
    });
  }

  void _onTouchDown(PointerDownEvent e) {
    _touchStart[e.pointer] = e.position;
    _touchTime[e.pointer] = Stopwatch()..start();
    _touchMaxTravel[e.pointer] = 0;
    // כמה אצבעות נוגעות ברגע ההנחה (כף יד או לחי מגיעות בדרך כלל כמה יחד).
    _touchPeers[e.pointer] = _touchStart.length;
  }

  void _onTouchMove(PointerMoveEvent e) {
    final start = _touchStart[e.pointer];
    if (start == null) return;
    final travel = (e.position - start).distance;
    if (travel > (_touchMaxTravel[e.pointer] ?? 0)) {
      _touchMaxTravel[e.pointer] = travel;
    }
  }

  /// מציג מה הפאנל דיווח: משך, תזוזה, לחץ וגודל המגע. נגיעה שבוטלה על ידי
  /// המערכת מסומנת בנפרד. כך רואים אם הנגיעות הקלות בכלל מגיעות לאפליקציה.
  void _onTouchEnd(PointerEvent e, {required bool cancelled}) {
    final ms = _touchTime.remove(e.pointer)?.elapsedMilliseconds ?? 0;
    final travel = _touchMaxTravel.remove(e.pointer) ?? 0;
    final peers = _touchPeers.remove(e.pointer) ?? 1;
    _touchStart.remove(e.pointer);
    _add(
      cancelled
          ? 'נגיעה בוטלה על ידי המערכת ($ms ms)'
          : 'נגיעה: $ms ms, תזוזה ${travel.round()} px, '
                'לחץ ${e.pressure.toStringAsFixed(2)}, '
                'גודל מגע ${e.radiusMajor.toStringAsFixed(1)}, '
                'size ${e.size.toStringAsFixed(2)}, '
                'רדיוס קטן ${e.radiusMinor.toStringAsFixed(1)}, '
                'במקביל $peers',
    );
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      _add(
        'מקש: ${lvKeyLabel(key.keyId)}   (קוד ${key.keyId.toRadixString(16)})',
      );
    }
    // נצרך, כדי שלא יפעיל פעולה אחרת תוך כדי הבדיקה.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final m = LvMetrics.of(context);
    final p = lvPaletteOf(context);
    final media = MediaQuery.of(context);
    final dpr = media.devicePixelRatio;
    final physical = media.size * dpr;
    final screenInfo =
        'מסך: ${media.size.width.round()}×${media.size.height.round()} '
        '(לוגי), צפיפות ${dpr.toStringAsFixed(2)}, '
        'פיזי ${physical.width.round()}×${physical.height.round()}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _add('כפתור חזרה של המכשיר נקלט');
      },
      child: LvKeyScope(
        onRawKey: _onKey,
        actions: const {},
        child: Listener(
          onPointerDown: _onTouchDown,
          onPointerMove: _onTouchMove,
          onPointerUp: (e) => _onTouchEnd(e, cancelled: false),
          onPointerCancel: (e) => _onTouchEnd(e, cancelled: true),
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              _add(
                'גלגלת: אנכי ${signal.scrollDelta.dy.toStringAsFixed(1)}, '
                'אופקי ${signal.scrollDelta.dx.toStringAsFixed(1)}',
              );
            }
          },
          child: LvScaffold(
            title: 'בדיקת כפתורים ונגיעה',
            holdToGoBack: false,
            onBack: () => Navigator.of(context).pop(),
            backLabel: 'יציאה',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'לחצו על כפתור כלשהו במכשיר (חוגה, חזרה, מקש, גלגלת), או געו במסך '
                  'בנגיעה קלה וחזקה. כאן יופיע מה שהאפליקציה קיבלה, כולל משך וגודל '
                  'כל נגיעה. אם לא מופיע כלום, הכפתור '
                  'מטופל על ידי המכשיר עצמו ואינו מגיע לאפליקציה.',
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: m.label,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: m.gap),
                Text(
                  screenInfo,
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: m.label,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: m.gap * 2),
                Expanded(
                  child: _events.isEmpty
                      ? const SizedBox.shrink()
                      : ListView(
                          children: [
                            for (final line in _events)
                              Padding(
                                padding: EdgeInsets.only(bottom: m.gap),
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    color: p.foreground,
                                    fontSize: m.body,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
