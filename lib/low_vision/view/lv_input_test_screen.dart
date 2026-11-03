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

  void _add(String text) {
    setState(() {
      _events.insert(0, text);
      if (_events.length > 12) _events.removeLast();
    });
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _add('כפתור חזרה של המכשיר נקלט');
      },
      child: LvKeyScope(
        onRawKey: _onKey,
        actions: const {},
        child: Listener(
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              _add(
                'גלגלת: אנכי ${signal.scrollDelta.dy.toStringAsFixed(1)}, '
                'אופקי ${signal.scrollDelta.dx.toStringAsFixed(1)}',
              );
            }
          },
          child: LvScaffold(
            title: 'בדיקת כפתורים',
            holdToGoBack: false,
            onBack: () => Navigator.of(context).pop(),
            backLabel: 'יציאה',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'לחצו על כפתור כלשהו במכשיר: החוגה, כפתור החזרה, מקש או גלגלת. '
                  'כאן יופיע מה שהאפליקציה קיבלה. אם לא מופיע כלום, הכפתור '
                  'מטופל על ידי המכשיר עצמו ואינו מגיע לאפליקציה.',
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: m.label,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
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
